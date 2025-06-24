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
* C++20协程库
    * [从 C++20 协程，到 Asio 的协程适配](https://www.bluepuni.com/archives/cpp20-coroutine-and-asio-coroutine)
    * [实现一个简单的协程](https://www.bluepuni.com/archives/implements-coroutine/)
* boost.coroutine / boost.coroutine2
* [PhotonLibOS](https://github.com/alibaba/PhotonLibOS)
    * 阿里开源的LibOS库，里面的运行时基于协程实现，支持`io_uring`作为IO引擎
    * [文档](https://photonlibos.github.io/cn/docs/category/introduction)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. libco协程库简析

### 2.1. 项目文件结构

项目中的文件并不多，如下。

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


## 3. 小结


## 4. 参考

