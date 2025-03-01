---
layout: post
title: 梳理Redis和Nginx中的epoll机制
categories: 网络
tags: 网络 epoll Redis Nginx
---

* content
{:toc}

梳理学习 Redis 和 Nginx 中的epoll机制。



## 1. 背景

[前面](https://xiaodongq.github.io/2025/02/25/ioserver2-epoll-dive/)的ioserver demo中进行了基本的epoll机制使用和学习，并梳理了开源网络库 muduo 的epoll使用和线程池实现。

本篇继续学习epoll在Redis和Nginx中的使用，进一步加深理解。跟踪的源码分支保持和本地CentOS8环境安装的服务版本一致：Redis版本：`5.0.3`（单线程版本）、Nginx版本：`1.14`。

参考：

* [深度解析单线程的 Redis 如何做到每秒数万 QPS 的超高处理能力！](https://mp.weixin.qq.com/s/2y60cxUjaaE2pWSdCBX1lA)
    * 说明：redis 6.0后支持了多线程，可参考学习：[Redis 6 中的多线程是如何实现的！？](https://mp.weixin.qq.com/s/MU8cxoKS3rU9mN_CY3WxWQ)
* [万字多图，搞懂 Nginx 高性能网络工作原理！](https://mp.weixin.qq.com/s/AX6Fval8RwkgzptdjlU5kg)
* [Redis 5.0.3 源码](https://github.com/redis/redis/tree/5.0.3)
* [Nginx 1.14 源码](https://github.com/nginx/nginx/tree/stable-1.14)

## 2. Redis中的epoll流程

### 2.1. Redis服务入口

整个redis的服务入口在：src/server.c，通过理解其中epoll的工作流程，有助于梳理Redis整体功能和代码。简化如下：

```c
// redis-5.0.3/src/server.c
int main(int argc, char **argv) {
    ...
    // 启动初始化
    initServer();
    ...
    // 运行事件处理循环，一直到服务器关闭为止
    // 其中server是全局类，定义：`struct redisServer server;`
    aeMain(server.el);
    ...
}
```

`initServer()`逻辑：

```c
void initServer(void) {
    ...
    // 创建事件循环 （`struct aeEventLoop`结构）
    server.el = aeCreateEventLoop(server.maxclients+CONFIG_FDSET_INCR);
    ...
    // 监听端口
    if (server.port != 0 &&
        listenToPort(server.port,server.ipfd,&server.ipfd_count) == C_ERR)
        exit(1);
    ...
    // 注册 accept事件处理器 到epoll事件循环中
    for (j = 0; j < server.ipfd_count; j++) {
        if (aeCreateFileEvent(server.el, server.ipfd[j], AE_READABLE,
            acceptTcpHandler,NULL) == AE_ERR)
            {
                serverPanic("Unrecoverable error creating server.ipfd file event.");
            }
    }
    ...
}
```

`aeMain(server.el)`对应函数：

```cpp
void aeMain(aeEventLoop *eventLoop) {
    eventLoop->stop = 0;
    while (!eventLoop->stop) {
        if (eventLoop->beforesleep != NULL)
            eventLoop->beforesleep(eventLoop);
        // 事件处理
        aeProcessEvents(eventLoop, AE_ALL_EVENTS|AE_CALL_AFTER_SLEEP);
    }
}
```

### 2.2. epoll初始化创建

来看一下上面 `aeCreateEventLoop` 的实现流程。

先看下核心数据结构：`aeEventLoop`，里面封装了具体io多路复用事件机制，事件机制对应的结构在 `void *apidata;` 中。

代码里很多字段或者文件名都有 `ae`、`ae_` 前缀，可从注释里看出来。下面代码段中保留了头文件的注释，其中的 `A simple event-driven programming library` 说明，就是这个前缀的来源。

```c
// redis-5.0.3/src/ae.h
/* A simple event-driven programming library. Originally I wrote this code
 * for the Jim's event-loop (Jim is a Tcl interpreter) but later translated
 * it in form of a library for easy reuse.
 * xxxxx
 */
typedef struct aeEventLoop {
    int maxfd;   /* highest file descriptor currently registered */
    int setsize; /* max number of file descriptors tracked */
    long long timeEventNextId;
    time_t lastTime;     /* Used to detect system clock skew */
    aeFileEvent *events; /* Registered events */
    aeFiredEvent *fired; /* Fired events */
    aeTimeEvent *timeEventHead;
    int stop;
    // 指向具体io多路复用机制的数据结构，如 使用epoll时，使用的aeApiState结构里就包含epoll_event
    void *apidata; /* This is used for polling API specific data */
    aeBeforeSleepProc *beforesleep;
    aeBeforeSleepProc *aftersleep;
} aeEventLoop;
```

`aeCreateEventLoop`函数：

```c
// redis-5.0.3/src/ae.c
aeEventLoop *aeCreateEventLoop(int setsize) {
    aeEventLoop *eventLoop;
    int i;

    // 申请空间创建 aeEventLoop
    if ((eventLoop = zmalloc(sizeof(*eventLoop))) == NULL) goto err;
    eventLoop->events = zmalloc(sizeof(aeFileEvent)*setsize);
    eventLoop->fired = zmalloc(sizeof(aeFiredEvent)*setsize);
    if (eventLoop->events == NULL || eventLoop->fired == NULL) goto err;
    eventLoop->setsize = setsize;
    ...
    eventLoop->aftersleep = NULL;
    // 创建具体io多路复用机制用到的数据结构
    // 根据上面的 #ifdef 条件编译判断，选择对应的实现，比如：HAVE_EVPORT、HAVE_EPOLL、HAVE_KQUEUE，对应不同的操作系统
    if (aeApiCreate(eventLoop) == -1) goto err;
    ...
}
```

代码中，基于条件编译来确认不同操作系统上的io多路复用机制，各机制实现里都包含`aeApiCreate`接口和对应的数据结构，其中：

* `ae_evport.c` 使用`Illumos event ports`事件机制，来自`Illumos` 操作系统（基于 OpenSolaris 的开源操作系统）
* `ae_epoll.c` 使用`epoll`事件机制，来自`Linux`操作系统
* `ae_kqueue.c` 使用`kqueue`事件机制，来自`BSD`操作系统
* `ae_select.c` 使用`select`事件机制，来自`Unix`操作系统，上面那些机制都没有则使用`select`机制

如下图所示：

![io事件机制选择](/images/2025-03-01-redis-io-events.png)

## 3. nginx中的epoll流程

## 4. 小结


## 5. 参考

* [深度解析单线程的 Redis 如何做到每秒数万 QPS 的超高处理能力！](https://mp.weixin.qq.com/s/2y60cxUjaaE2pWSdCBX1lA)
* [万字多图，搞懂 Nginx 高性能网络工作原理！](https://mp.weixin.qq.com/s/AX6Fval8RwkgzptdjlU5kg)
* [redis 5.0.3 源码](https://github.com/redis/redis/tree/5.0.3)
* [nginx 1.14 源码](https://github.com/nginx/nginx/tree/stable-1.14)
