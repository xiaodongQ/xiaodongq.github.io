---
layout: post
title: Redis学习实践（二） -- 关键特性和机制
categories: Redis
tags: Redis 存储
---

* content
{:toc}

Redis学习实践系列，本篇梳理支持的关键特性和机制。



## 1. 背景

继续梳理Redis支持的关键特性和相关机制，如 RDB、AOF，主从复制、哨兵等。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 事件循环和多线程

主线程基于epoll进行IO多路复用判断处理，前面 [梳理Redis中的epoll机制](https://xiaodongq.github.io/2025/02/28/epoll-redis-nginx/) 中已经梳理过，此处不做展开。

`main` -> `initServer` -> `InitServerLast`

```c
// redis/src/server.c
void InitServerLast() {
    // 创建Background后台线程，目前有3个线程：文件延迟关闭、AOF fsync延迟落盘、对象延迟释放
    bioInit();
    // 多线程特性，io_threads_num不为1时启用，对应配置文件中的：io-threads。可在config.c中找配置对应关系
    initThreadedIO();
    // 使用jemalloc时有效，设置 jemalloc 后台线程，配置文件中 jemalloc-bg-thread 默认打开
    set_jemalloc_bg_thread(server.jemalloc_bg_thread);
    server.initial_memory_usage = zmalloc_used_memory();
}
```

initThreadedIO 初始化IO线程流程：

```c
// redis/src/networking.c
#define IO_THREADS_MAX_NUM 128
// 每个 IO 线程的描述符
pthread_t io_threads[IO_THREADS_MAX_NUM];
// 每个 IO 线程对应一个mutex
pthread_mutex_t io_threads_mutex[IO_THREADS_MAX_NUM];
// 等待每个 IO 线程处理的客户端个数
_Atomic unsigned long io_threads_pending[IO_THREADS_MAX_NUM];
// 每个 IO 线程要处理的客户端
list *io_threads_list[IO_THREADS_MAX_NUM];

void initThreadedIO(void) {
    server.io_threads_active = 0; /* We start with threads not active. */

    if (server.io_threads_num == 1) return;

    if (server.io_threads_num > IO_THREADS_MAX_NUM) {
        serverLog(LL_WARNING,"Fatal: too many I/O threads configured. "
                             "The maximum number is %d.", IO_THREADS_MAX_NUM);
        exit(1);
    }

    // 虽然 io_threads 等数组的容量为 128，创建线程的数量还是以 io_threads_num 配置为准
    for (int i = 0; i < server.io_threads_num; i++) {
        // 每个线程创建一个双向队列，用于记录要处理的客户端
        io_threads_list[i] = listCreate();
        // i == 0时不用创建新线程，是主线程
        if (i == 0) continue; /* Thread 0 is the main thread. */

        /* Things we do only for the additional threads. */
        pthread_t tid;
        pthread_mutex_init(&io_threads_mutex[i],NULL);
        io_threads_pending[i] = 0;
        // 持锁。创建线程后，线程中再lock的话就会阻塞，直到其他地方unlock（startThreadedIO中）
        pthread_mutex_lock(&io_threads_mutex[i]); /* Thread will be stopped. */
        // 线程创建，传入i作为上述各数组的下标
        if (pthread_create(&tid,NULL,IOThreadMain,(void*)(long)i) != 0) {
            serverLog(LL_WARNING,"Fatal: Can't initialize IO thread.");
            exit(1);
        }
        io_threads[i] = tid;
    }
}
```

下面是线程处理函数 IOThreadMain，这里说下此处mutex的用法：

* 创建线程时，线程外就持锁了，线程中lock会阻塞，直到外面通知unlock，此处lock才继续往下处理
    * 线程外通过lock操作，可以在没有客户端处理时，让线程阻塞等待，避免不必要的消耗
* 跟踪src/networking.c代码可以看到，`startThreadedIO`和`stopThreadedIO`的时机，以mutex的lock/unlock来控制IO多线程的阻塞等待
    * `beforeSleep` -> `handleClientsWithPendingWritesUsingThreads` -> `startThreadedIO`，而`beforeSleep`函数会注册给事件循环，每次`aeProcessEvents`事件循环处理时都会先调用`beforeSleep`
    * `beforeSleep` -> `handleClientsWithPendingWritesUsingThreads` -> `stopThreadedIOIfNeeded`判断是否需要停止 -> `stopThreadedIO`，同上

```c
// redis/src/networking.c
void *IOThreadMain(void *myid) {
    long id = (unsigned long)myid;
    char thdname[16];

    snprintf(thdname, sizeof(thdname), "io_thd_%ld", id);
    // pthread_setname_np 设置线程名
    redis_set_thread_title(thdname);
    // 设置亲和性，配置项：server_cpulist，没配置则为NULL
    redisSetCpuAffinity(server.server_cpulist);
    // pthread_setcancelstate 设置当前线程为 允许取消
    // 且 pthread_setcanceltype 设置为异步取消，意味着线程可以在任何时刻响应取消请求
    makeThreadKillable();

    while(1) {
        /* Wait for start */
        // 类似轻量级的自旋锁，等待主线程通知。减少不必要的加锁解锁
        for (int j = 0; j < 1000000; j++) {
            if (io_threads_pending[id] != 0) break;
        }

        /* Give the main thread a chance to stop this thread. */
        // 没有要处理的客户端，continue
        if (io_threads_pending[id] == 0) {
            // 线程外持锁了，此处lock会阻塞，直到外面通知unlock，此处lock就继续往下处理了
            // 线程外通过lock操作，可以在没有客户端处理时，让线程阻塞等待，避免不必要的消耗
            pthread_mutex_lock(&io_threads_mutex[id]);
            pthread_mutex_unlock(&io_threads_mutex[id]);
            continue;
        }

        serverAssert(io_threads_pending[id] != 0);

        if (tio_debug) printf("[%ld] %d to handle\n", id, (int)listLength(io_threads_list[id]));

        /* Process: note that the main thread will never touch our list
         * before we drop the pending count to 0. */
        listIter li;
        listNode *ln;
        // 获取IO线程要处理的客户端列表，让`li`指向链表头
        listRewind(io_threads_list[id],&li);
        while((ln = listNext(&li))) {
            // 从客户端列表中获取一个客户端
            client *c = listNodeValue(ln);
            if (io_threads_op == IO_THREADS_OP_WRITE) {
                // 将数据写回客户端
                writeToClient(c,0);
            } else if (io_threads_op == IO_THREADS_OP_READ) {
                // 从客户端读取数据
                readQueryFromClient(c->conn);
            } else {
                serverPanic("io_threads_op value is unknown");
            }
        }
        // 处理完所有客户端后，清空该线程的客户端列表
        listEmpty(io_threads_list[id]);
        // 将该线程的待处理任务数量设置为0
        io_threads_pending[id] = 0;

        if (tio_debug) printf("[%ld] Done\n", id);
    }
}
```

`io_threads_list`数组中，每个成员都是一个客户端队列，表示待处理的客户端。事件循环中会将延迟读（待读）和延迟写（待写）的客户端分配给上述IO线程，而后线程中进行处理。

待处理客户端分配给IO线程示意图：

![redis-event-loop](/images/2025-03-27-redis-loop.png)

## 3. RDB和AOF



## 4. 主从复制

## 5. 哨兵机制和Raft选举


## 6. 小结


## 7. 参考

* [Redis 核心技术与实战](https://time.geekbang.org/column/intro/100056701)
* [Redis 源码剖析与实战](https://time.geekbang.org/column/intro/100084301)
* [图解Redis](https://www.xiaolincoding.com/redis/)
* [Redis系列文章](https://mp.weixin.qq.com/mp/appmsgalbum?action=getalbum&__biz=MzIyOTYxNDI5OA==&scene=1&album_id=1699766580538032128&count=3&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=0&fontScale=100)
