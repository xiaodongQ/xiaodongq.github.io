---
layout: post
title: Redis学习实践（二） -- 多线程、RDB和AOF
categories: Redis
tags: Redis 存储
---

* content
{:toc}

Redis学习实践系列，本篇梳理支持的关键特性和机制：多线程、RDB、AOF。



## 1. 背景

继续梳理Redis支持的关键特性和相关机制，多线程、RDB、AOF。

除了上篇提到的数据类型和结构，Redis的其他知识点可以以下面的全景图串起来：

![redis-knowledge-overview](/images/redis-knowledge-overview.jpg)  
[出处](https://time.geekbang.org/column/intro/100056701)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 事件循环和多线程

主线程基于epoll进行IO多路复用判断处理，前面 [梳理Redis中的epoll机制](https://xiaodongq.github.io/2025/02/28/epoll-redis-nginx/) 中已经梳理过，此处不做展开。

线程初始化调用栈：`main` -> `initServer` -> `InitServerLast`

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

## 3. RDB和AOF简要说明

`RDB（Redis Database）`和 `AOF（Append Only File）`是 Redis 中两种用于持久化数据的机制，通常会**将两者结合使用**：全量备份+实时记录写操作。

* `RDB`是通过将 Redis 在内存中的数据库状态保存到磁盘上的一个 `.rdb` 文件来实现持久化的，是一个经过压缩的**二进制文件**，占用**磁盘空间小**，加载时**恢复速度快**
    * 可手动触发RDB生成：`save`（阻塞线程） 和 `bgsave`（fork子进程写，不阻塞线程，实时数据 **`COW`写时复制**）
    * 也可自动触发：指定在多长时间内有多少次写操作，如 `save 900 1`，900s内至少有1个key被修改则触发RDB生成
* `AOF`是将 Redis 执行的写命令（修改类命令）以**追加**的方式记录到一个文件中，默认文件名为 `appendonly.aof`，是一个**文本文件**，恢复时需要重新执行所有命令
    * 配置文件中AOF生成默认是关闭的，可设置`appendonly yes`开启，默认文件名配置项为`appendfilename`
    * `appendfsync`设置sync到磁盘的触发策略，默认是`everysec`，即每秒进行fsync同步（而此前可能只是在page cache里，宕机会丢失）
        * 此外还有`always`、`no`选项

相关命令和对应接口：

```c
// redis/src/server.c
struct redisCommand redisCommandTable[] = {
    ...
    // 保存RDB
    {"save",saveCommand,1,
     "admin no-script",
     0,NULL,0,0,0,0,0,0},

    // 后台保存RDB
    {"bgsave",bgsaveCommand,-1,
     "admin no-script",
     0,NULL,0,0,0,0,0,0},

    // 重写AOF
    {"bgrewriteaof",bgrewriteaofCommand,1,
     "admin no-script",
     0,NULL,0,0,0,0,0,0},
    ...
};
```

## 4. RDB文件

### 4.1. save写RDB文件流程

触发时机和对应的实现：`save`命令对应`saveCommand`函数实现、`bgsave`命令对应`bgsaveCommand`函数实现。

先来看下 `saveCommand`：

```c
// redis/src/rdb.c
void saveCommand(client *c) {
    if (server.rdb_child_pid != -1) {
        addReplyError(c,"Background save already in progress");
        return;
    }
    rdbSaveInfo rsi, *rsiptr;
    rsiptr = rdbPopulateSaveInfo(&rsi);
    // 写RDB文件
    if (rdbSave(server.rdb_filename,rsiptr) == C_OK) {
        addReply(c,shared.ok);
    } else {
        addReply(c,shared.err);
    }
}

int rdbSave(char *filename, rdbSaveInfo *rsi) {
    ...
    // 先写临时文件
    snprintf(tmpfile,256,"temp-%d.rdb", (int) getpid());
    fp = fopen(tmpfile,"w");
    // rdb 和 fp文件句柄 绑定
    rioInitWithFile(&rdb,fp);
    startSaving(RDBFLAGS_NONE);
    ...
    // 实际创建 RDB 文件并写内容
    if (rdbSaveRio(&rdb,&error,RDBFLAGS_NONE,rsi) == C_ERR) {
        ...
    }

    // 保证落盘
    // fflush 是标准 C 库中的函数，其主要作用是刷新流（stream）的缓冲区
    if (fflush(fp)) goto werr;
    // fsync 是系统调用，用强制将内核缓冲区中的数据立即写入磁盘
    if (fsync(fileno(fp))) goto werr;
    if (fclose(fp)) { fp = NULL; goto werr; }
    fp = NULL;

    // 写完的临时RDB文件，rename替换配置项 dbfilename 指定的RDB文件名称
    if (rename(tmpfile,filename) == -1) {
        ...
    }
    ...
    // 信号通知结束
    stopSaving(1);
    return C_OK;
}
```

### 4.2. RDB文件格式

`rdbSaveRio`中负责RDB文件组织格式的写入，RDB文件是一个二进制文件，来看下其基本组成部分，再看代码就会比较清晰了。

RDB 文件主要包含3个部分：

* 文件头：这部分内容保存了 Redis 的魔数、RDB 版本、Redis 版本、RDB 文件创建时间、键值对占用的内存大小等信息。
* 文件数据部分：这部分保存了 Redis 数据库实际的所有键值对。
* 文件尾：这部分保存了 RDB 文件的结束标识符，以及整个文件的校验值。

`rdbSaveRio`的简要代码如下：

```c
// redis/src/rdb.c
int rdbSaveRio(rio *rdb, int *error, int rdbflags, rdbSaveInfo *rsi) {
    ...
    // 魔数：RDDIS + RDB版本 进行拼接
    snprintf(magic,sizeof(magic),"REDIS%04d",RDB_VERSION);
    // 写上述拼接内容到RDB文件中
    if (rdbWriteRaw(rdb,magic,9) == -1) goto werr;
    // 保存一些RDB辅助信息到RDB文件，比如redis版本、时间戳、使用的内存量等等
    if (rdbSaveInfoAuxFields(rdb,rdbflags,rsi) == -1) goto werr;
    // 保存 Redis 模块（Module）的辅助数据
    // Redis 模块允许用户扩展 Redis 的功能，这些模块可能会有自己的内部状态或者需要持久化的数据
    if (rdbSaveModulesAux(rdb, REDISMODULE_AUX_BEFORE_RDB) == -1) goto werr;
    // 每个数据库的数据进行保存
    for (j = 0; j < server.dbnum; j++) {
        redisDb *db = server.db+j;
        dict *d = db->dict;
        if (dictSize(d) == 0) continue;
        di = dictGetSafeIterator(d);
        ...
    }
    ...
}
```

### 4.3. RDB文件查看

可以用`od`命令（od - dump files in octal and other formats）查看RDB文件，也可以用 [之前](https://xiaodongq.github.io/2023/06/30/linux-directory-struct/) 看xfs超级块信息时用的`xxd`命令工具。

xxd查看：跟上述`rdbSaveRio`中写的魔数可对比印证

```sh
[CentOS-root@xdlinux ➜ src git:(6.0) ✗ ]$ xxd dump.rdb 
00000000: 5245 4449 5330 3030 39fa 0972 6564 6973  REDIS0009..redis
00000010: 2d76 6572 0636 2e30 2e32 30fa 0a72 6564  -ver.6.0.20..red
00000020: 6973 2d62 6974 73c0 40fa 0563 7469 6d65  is-bits.@..ctime
00000030: c288 a4e6 67fa 0875 7365 642d 6d65 6dc2  ....g..used-mem.
00000040: 7894 0c00 fa0c 616f 662d 7072 6561 6d62  x.....aof-preamb
00000050: 6c65 c000 fe00 fb02 0000 0278 64c1 5704  le.........xd.W.
00000060: 0003 7864 32c1 ae08 ffcd 41ba be9f 4df4  ..xd2.....A...M.
00000070: 1d 
```

`od`查看：

```sh
[CentOS-root@xdlinux ➜ src git:(6.0) ✗ ]$ od -A x -t x1c -v dump.rdb
000000  52  45  44  49  53  30  30  30  39  fa  09  72  65  64  69  73
         R   E   D   I   S   0   0   0   9 372  \t   r   e   d   i   s
000010  2d  76  65  72  06  36  2e  30  2e  32  30  fa  0a  72  65  64
         -   v   e   r 006   6   .   0   .   2   0 372  \n   r   e   d
000020  69  73  2d  62  69  74  73  c0  40  fa  05  63  74  69  6d  65
         i   s   -   b   i   t   s 300   @ 372 005   c   t   i   m   e
000030  c2  88  a4  e6  67  fa  08  75  73  65  64  2d  6d  65  6d  c2
       302 210 244 346   g 372  \b   u   s   e   d   -   m   e   m 302
000040  78  94  0c  00  fa  0c  61  6f  66  2d  70  72  65  61  6d  62
         x 224  \f  \0 372  \f   a   o   f   -   p   r   e   a   m   b
000050  6c  65  c0  00  fe  00  fb  02  00  00  02  78  64  c1  57  04
         l   e 300  \0 376  \0 373 002  \0  \0 002   x   d 301   W 004
000060  00  03  78  64  32  c1  ae  08  ff  cd  41  ba  be  9f  4d  f4
        \0 003   x   d   2 301 256  \b 377 315   A 272 276 237   M 364
000070  1d
       035
000071
```

### 4.4. bgsave流程

`bgsave`命令后台写RDB的调用链则是：`bgsaveCommand` -> `rdbSaveBackground`，其中进行`redisFork`（其中进行`fork`），并将子进程id设置到`server.rdb_child_pid`中。并且在子进程中进行 `rdbSave` 写RDB处理，和上述`save`中流程一样。

但不同的一点是，为了同步实时数据，通过 `sendChildCOWInfo` 进行写时复制处理（Copy On Write），其中基于管道通信。

```c
// redis/src/rdb.c
int rdbSaveBackground(char *filename, rdbSaveInfo *rsi) {
    pid_t childpid;
    ...
    // pipe初始化管道，`server.child_info_pipe`，用于下面的写时复制
    openChildInfoPipe();

    // fork
    if ((childpid = redisFork(CHILD_TYPE_RDB)) == 0) {
        int retval;

        /* Child */
        redisSetProcTitle("redis-rdb-bgsave");
        // 绑定CPU，bgsave_cpulist配置项默认未设置
        redisSetCpuAffinity(server.bgsave_cpulist);
        // 子进程写RDB文件
        retval = rdbSave(filename,rsi);
        if (retval == C_OK) {
            // fork后子进程和父进程会共享内存页，通过管道通信进行写时复制
            sendChildCOWInfo(CHILD_TYPE_RDB, "RDB");
        }
        exitFromChild((retval == C_OK) ? 0 : 1);
    } else {
        /* Parent */
        ...
        serverLog(LL_NOTICE,"Background saving started by pid %d",childpid);
        server.rdb_save_time_start = time(NULL);
        // 记录写RDB文件的子进程id
        server.rdb_child_pid = childpid;
        server.rdb_child_type = RDB_CHILD_TYPE_DISK;
        updateDictResizePolicy();
        return C_OK;
    }
    return C_OK; /* unreached */
}
```

## 5. AOF文件

### 5.1. AOF文件格式

1、可以看下 appendonly.aof 文件的内容形式：

* `*2`表示当前命令有2部分，每个部分格式都是`$数字`+具体命令，表示这部分中的命令、键或值一共有多少字节
    * `$6`表示后面内容有`6`字节，此处即`SELECT`；`$1`则表示后面内容1字节，即一字节长度的`0`
    * 完整命令：`SELECT 0`，**Redis支持多个逻辑数据库，配置文件中可看到`databases 16`，即0~15**，客户端可以用`SELECT`来选择使用不同数据库
    * 可以用`INFO`命令来查看当前使用的数据库，内容形式：`db0:keys=1,expires=0,avg_ttl=0`
* `*3`表示有3部分：3字节的`set`命令 + 2字节的`xd` + 3字节的`111`，完整命令为 `set xd 111`

```sh
[CentOS-root@xdlinux ➜ src git:(6.0) ✗ ]$ cat appendonly.aof 
*2
$6
SELECT
$1
0
*3
$3
set
$2
xd
$3
111
```

2、随着接收的写命令越来越多，AOF文件会越来越大，**AOF重写（rewrite）机制**会根据数据库现状创建一个新的AOF文件。

* AOF重写过程可由`bgrewriteaof`命令触发，会创建`redis-aof-rewrite`子进程完成，避免线程阻塞

在客户端通过`bgrewriteaof`触发AOF重写，会将RDB的内容也写入AOF文件里，内容如下：

```sh
[CentOS-root@xdlinux ➜ src git:(6.0) ✗ ]$ cat appendonly.aof
REDIS0009?	redis-ver6.0.20?
?edis-bits?@?ctime???gused-mem?`4
 aof-preamble???xd?o?K???_ G# 
```

### 5.2. AOF重写触发时机和流程

`bgrewriteaof` 命令对应的实现为：`bgrewriteaofCommand`，其中 `rewriteAppendOnlyFileBackground` 负责AOF重写。

除了`bgrewriteaof`（1、）手动触发，`rewriteAppendOnlyFileBackground`还有**另外几个触发调用时机**：

* 2、`startAppendOnly` 函数，会被下面两个场景调用
    * 1）`configSetCommand`，对应了在Redis中执行 `config` 命令启用AOF功能：`config set appendonly yes`，启用时调一次
    * 2）`restartAOFAfterSYNC`，在**主从节点的复制过程**中被调用
* 3、`serverCron` 函数，周期性执行
    * 为了避免 AOF 文件过大导致占用过多的磁盘空间，可通过下述参数控制自动rewrite AOF的触发条件：
    * `auto-aof-rewrite-percentage`（大小比例，默认100） 和 `auto-aof-rewrite-min-size`（大小绝对值，默认64MB）

```c
// redis/src/aof.c
void bgrewriteaofCommand(client *c) {
    if (server.aof_child_pid != -1) {
        addReplyError(c,"Background append only file rewriting already in progress");
    } else if (hasActiveChildProcess()) {
        server.aof_rewrite_scheduled = 1;
        addReplyStatus(c,"Background append only file rewriting scheduled");
    } else if (rewriteAppendOnlyFileBackground() == C_OK) {
        addReplyStatus(c,"Background append only file rewriting started");
    } else {
        addReplyError(c,"Can't execute an AOF background rewriting. "
                        "Please check the server logs for more information.");
    }
}
```

rewriteAppendOnlyFileBackground逻辑：

```c
// redis/src/aof.c
int rewriteAppendOnlyFileBackground(void) {
    pid_t childpid;

    if (hasActiveChildProcess()) return C_ERR;
    // 创建管道
    if (aofCreatePipes() != C_OK) return C_ERR;
    openChildInfoPipe();
    // fork
    if ((childpid = redisFork(CHILD_TYPE_AOF)) == 0) {
        ...
        /* Child */
        redisSetProcTitle("redis-aof-rewrite");
        // 绑定CPU，aof_rewrite_cpulist配置项默认未设置
        redisSetCpuAffinity(server.aof_rewrite_cpulist);
        snprintf(tmpfile,256,"temp-rewriteaof-bg-%d.aof", (int) getpid());
        // 重写AOF
        if (rewriteAppendOnlyFile(tmpfile) == C_OK) {
            // 写时复制
            sendChildCOWInfo(CHILD_TYPE_AOF, "AOF rewrite");
            exitFromChild(0);
        } else {
            exitFromChild(1);
        }
    } else {
        /* Parent */
        ...
        // 记录子进程id
        server.aof_child_pid = childpid;
        ...
        return C_OK;
    }
    return C_OK; /* unreached */
}
```

## 6. 小结

梳理Redis中的多线程、RDB、AOF等特性。

## 7. 参考

* [Redis 核心技术与实战](https://time.geekbang.org/column/intro/100056701)
* [Redis 源码剖析与实战](https://time.geekbang.org/column/intro/100084301)
* [图解Redis](https://www.xiaolincoding.com/redis/)
* [Redis系列文章](https://mp.weixin.qq.com/mp/appmsgalbum?action=getalbum&__biz=MzIyOTYxNDI5OA==&scene=1&album_id=1699766580538032128&count=3&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=0&fontScale=100)
