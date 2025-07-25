---
title: 协程梳理实践（五） -- libco、boost.coroutine等协程库简析
description: 简要梳理libco、boost.coroutine2等开源协程库实现逻辑
categories: [并发与异步编程, 协程]
tags: [协程, 异步编程]
---


## 1. 引言

前几篇了解了协程的基本概念和模块，并梳理学习了sylar中的协程实现，本篇中对几个知名协程库的流程进行梳理说明。

协程库和相关链接：

* libco
    * [libco](https://github.com/Tencent/libco)，并进行[fork](https://github.com/xiaodongQ/libco)
    * [漫谈微信libco协程设计及实现（万字长文）](https://runzhiwang.github.io/2019/06/21/libco/)
    * [微信 libco 协程库源码分析](https://www.cyhone.com/articles/analysis-of-libco/)
    * [C++20 Coroutine 性能测试 (附带和libcopp/libco/libgo/goroutine/linux ucontext对比)](https://cloud.tencent.com/developer/article/1563255)
* boost asio中的coroutine
    * 有栈协程：使用`boost::asio::spawn()`接口
    * 可查看 [boost_asio overview](https://www.boost.org/doc/libs/latest/doc/html/boost_asio/overview.html)
* C++20协程库
    * [从 C++20 协程，到 Asio 的协程适配](https://www.bluepuni.com/archives/cpp20-coroutine-and-asio-coroutine)
    * 了解：[实现一个简单的协程](https://www.bluepuni.com/archives/implements-coroutine/)
* boost.coroutine / boost.coroutine2
    * [boost.coroutine](https://www.boost.org/doc/libs/latest/libs/coroutine/doc/html/coroutine/overview.html)已经被标记为`已过时（deprecated）`
    * 新的协程实现为 [boost.coroutine2](https://www.boost.org/doc/libs/latest/libs/coroutine2/doc/html/index.html)
    * [协程Part1-boost.Coroutine.md](https://www.cnblogs.com/pokpok/p/16932735.html)
* [PhotonLibOS](https://github.com/alibaba/PhotonLibOS)
    * 阿里开源的LibOS库，里面的运行时基于协程实现，支持`io_uring`作为IO引擎
    * [文档](https://photonlibos.github.io/cn/docs/category/introduction)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. libco协程库简析

libco中实现了有栈协程。相关核心机制，和之前 [协程梳理实践](https://xiaodongq.github.io/categories/%E5%8D%8F%E7%A8%8B/) 中梳理`sylar`协程时基本类似，不过libco更为完善，**支持共享栈**、**协程间可嵌套调用**。核心机制，如：协程`yield`/`resume`操作、协程调度、系统调用hook等。

### 2.1. 项目文件结构

项目中的文件并不多：

```sh
[MacOS-xd@qxd ➜ libco git:(master) ]$ ll
total 344
-rw-r--r--  1 xd  staff   1.7K  6 17 22:24 CMakeLists.txt
-rw-r--r--  1 xd  staff    19K  6 17 22:24 LICENSE.txt
-rw-r--r--  1 xd  staff   2.3K  6 17 22:24 Makefile
-rw-r--r--  1 xd  staff   2.2K  6 17 22:24 README.md
-rw-r--r--  1 xd  staff   2.2K  6 17 22:24 co.mk
-rw-r--r--  1 xd  staff   3.0K  6 17 22:24 co_closure.h
-rw-r--r--  1 xd  staff   6.5K  6 17 22:24 co_epoll.cpp
-rw-r--r--  1 xd  staff   2.1K  6 17 22:24 co_epoll.h
-rw-r--r--  1 xd  staff    23K  6 17 22:24 co_hook_sys_call.cpp

# 协程实现
-rw-r--r--  1 xd  staff    24K  6 17 22:24 co_routine.cpp
-rw-r--r--  1 xd  staff   2.4K  6 17 22:24 co_routine.h
# 定义协程结构体：stCoRoutine_t
-rw-r--r--  1 xd  staff   2.2K  6 17 22:24 co_routine_inner.h

-rw-r--r--  1 xd  staff   2.2K  6 17 22:24 co_routine_specific.h
# 协程上下文结构定义
-rw-r--r--  1 xd  staff   2.9K  6 17 22:24 coctx.cpp
-rw-r--r--  1 xd  staff   1.1K  6 17 22:24 coctx.h
-rw-r--r--  1 xd  staff   2.0K  6 17 22:24 coctx_swap.S
# 几个
-rw-r--r--  1 xd  staff   1.9K  6 17 22:24 example_xxx.cpp
...
```

其中：
* `co_routine.h/cpp` 中为协程API实现
* `co_routine_inner.h`中定义 `stCoRoutine_t` 协程结构体
* `libco/coctx.h`中定义 `coctx_t` 协程上下文结构
    * `coctx_swap.S`里基于汇编实现了协程的上下文切换函数
* `co_epoll.h/cpp` 封装了`epoll`和`kqueue`
* `co_hook_sys_call.cpp` 对系统api的hook封装，使用`dlsym`函数获取原始系统调用的地址

`stCoRoutine_t`协程结构定义如下：

```cpp
// libco/co_routine_inner.h
// 协程结构定义
struct stCoRoutine_t
{
    stCoRoutineEnv_t *env;  // 协程所在的运行环境，可以理解为，该协程所属的协程管理器
    
    pfn_co_routine_t pfn; // 协程所对应的函数
    void *arg; // 函数参数
    coctx_t ctx; // 协程上下文，包括寄存器和栈
 
    // 以下用char表示了bool语义，节省空间
    char cStart;          // 是否已经开始运行了
    char cEnd;            // 是否已经结束
    char cIsMain;         // 是否是主协程
    char cEnableSysHook;  // 是否要打开钩子标识，默认是关闭的
    char cIsShareStack;   // 是否要采用共享栈

    void *pvEnv;

    //char sRunStack[ 1024 * 128 ];
    stStackMem_t* stack_mem; // 栈内存

    //save satck buffer while confilct on same stack_buffer;
    char* stack_sp; 
    unsigned int save_size; // save_buffer的长度
    char* save_buffer; // 当协程挂起时，栈的内容会栈暂存到save_buffer中

    stCoSpec_t aSpec[1024];
};
```

### 2.2. 使用方式

先说明下部分核心API：

```cpp
// libco/co_routine.h
/**
* 创建一个协程对象
* 
* @param ppco - (output) 创建的协程对象。传入指针（stCoRoutine_t *）的地址，该指针会指向本函数中创建的协程对象
* @param attr - (input) 协程属性，目前主要是共享栈 
* @param pfn - (input) 协程所运行的函数
* @param arg - (input) 协程运行函数的参数
*/
int     co_create( stCoRoutine_t **co,const stCoRoutineAttr_t *attr,void *(*routine)(void*),void *arg );
// 恢复协程co，即切换到co协程
void    co_resume( stCoRoutine_t *co );
// 挂起
void    co_yield( stCoRoutine_t *co );
...

// 获取当前协程
stCoRoutine_t *co_self();

/**
* 大部分的sys_hook都需要用到这个函数来把事件注册到epoll中。具体实现在`co_poll_inner`函数中。
* 
* @param ctx epoll上下文
* @param fds[] fds 要监听的文件描述符 原始poll函数的参数，
* @param nfds  nfds fds的数组长度 原始poll函数的参数
* @param timeout_ms timeout 等待的毫秒数 原始poll函数的参数
*/
int     co_poll( stCoEpoll_t *ctx,struct pollfd fds[], nfds_t nfds, int timeout_ms );
/*
* libco的核心调度
* 在此处调度三种事件：
* 1. 被hook的io事件，该io事件是通过co_poll_inner注册进来的
* 2. 超时事件
* 3. 用户主动使用poll的事件
* 所以，如果用户用到了三种事件，必须得配合使用co_eventloop
*
* @param ctx epoll管理器
* @param pfn 每轮事件循环的最后会调用该函数
* @param arg pfn的参数
*/
void    co_eventloop( stCoEpoll_t *ctx,pfn_co_eventloop_t pfn,void *arg );
```

使用方式，步骤如下：
* 1、`co_create`创建协程。其声明如上所述，创建时指定协程处理函数。
    * 比如：`co_create( &co,NULL,readwrite_routine, &endpoint);`
* 2、协程切换，调用`co_resume`
* 3、调用`co_eventloop`，开始协程调度
    * 其中系统调用被hook为通过epoll事件驱动，流程类似：[协程梳理实践（四） -- sylar协程API hook封装](https://xiaodongq.github.io/2025/06/10ocoroutine-api-hook/)。

示例：以libco里的`example_echocli.cpp`做说明。
* 使用方式 `./example_echosvr 127.0.0.1 10000 100 50`，各参数为：服务端ip、端口、协程数（每个子进程都创建该数量的协程）、子进程数
* 创建50个子进程，每个子进程里创建100个协程，而后每个子进程开始协程调度（各自包含一个协程调度器）

```cpp
// libco/example_echocli.cpp
int main(int argc, char *argv[])
{
    stEndPoint endpoint;
    endpoint.ip = argv[1];
    endpoint.port = atoi(argv[2]);
    int cnt = atoi( argv[3] );
    int proccnt = atoi( argv[4] );
    ...
    for(int k=0; k<proccnt; k++) {
        pid_t pid = fork();
        if(pid > 0) {
            // 父进程
            continue;
        }
        else if(pid < 0) {
            break;
        }
        // 下面是每个子进程都会进行的操作
        for(int i=0; i<cnt; i++) {
            stCoRoutine_t *co = 0;
            // 创建协程
            co_create( &co, NULL, readwrite_routine, &endpoint);
            co_resume( co );
        }
        // 开始协程调度，每个子进程都有一个协程调度器
        co_eventloop( co_get_epoll_ct(),0,0 );

        exit(0);
    }
    return 0;
}
```

协程处理函数如下：
* 其中`socket`、`connect`、`close`、`write`、`read`等网络api接口都进行了hook封装，相关同步接口hook成了基于`epoll`的异步事件处理
    * 并使用`dlsym`函数获取原始函数地址。具体可见`co_hook_sys_call.cpp`的实现。
* `connect`连接服务端，连接成功后`write`发送8字节数据，而后进行`read`接收，这3个接口都在epoll事件循环中进行处理

```cpp
// libco/co_hook_sys_call.cpp
static void *readwrite_routine( void *arg ) {
    co_enable_hook_sys();
    stEndPoint *endpoint = (stEndPoint *)arg;
    ...
    int fd = -1;
    for(;;) {
        // 若连接返回`EALREADY`或`EINPROGRESS`，则继续重连
        if ( fd < 0 ) {
            // 里面对原生socket做了hook，使用dlsym获取原有函数地址
            fd = socket(PF_INET, SOCK_STREAM, 0);
            struct sockaddr_in addr;
            SetAddr(endpoint->ip, endpoint->port, addr);
            // 句柄注册到epoll中（其中调用`co_poll_inner`），注册POLLOUT事件
            ret = connect(fd,(struct sockaddr*)&addr,sizeof(addr));
            if ( errno == EALREADY || errno == EINPROGRESS ) {
                struct pollfd pf = { 0 };
                pf.fd = fd;
                pf.events = (POLLOUT|POLLERR|POLLHUP);
                // 其中调用`co_poll_inner`，注册POLLOUT事件
                co_poll( co_get_epoll_ct(),&pf,1,200);
                //check connect
                int error = 0;
                uint32_t socklen = sizeof(error);
                errno = 0;
                ret = getsockopt(fd, SOL_SOCKET, SO_ERROR,(void *)&error,  &socklen);
                if ( ret == -1 || error) {
                    ...
                    continue;
                }
            } 
        }
        
        // hook写，其中会注册POLLOUT事件
        ret = write( fd,str, 8);
        if ( ret > 0 ) {
            // hook读，其中注册POLLIN事件
            ret = read( fd, buf, sizeof(buf) );
            ...
        }
        ...
    }
    return 0;
}
```

## 3. boost.coroutine

TODO

## 4. 小结


## 5. 参考

