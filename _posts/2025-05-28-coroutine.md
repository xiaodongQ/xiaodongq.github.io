---
title: 实现一个简易协程
description: 梳理协程相关机制，并实践实现一个简易协程。
categories: [并发与异步编程]
tags: [协程, 异步编程]
---


## 1. 引言

[Ceph学习笔记（三） -- 对象存储](https://xiaodongq.github.io/2025/05/16/ceph-object-storage/) 中梳理`rgw`的`main`启动流程时，提到客户端请求管理类`RGWCompletionManager`基于**协程**实现。以及之前的多篇博客中留下了梳理协程的TODO项，本篇就来梳理下协程的机制原理，并基于开源项目进行实践。

相关参考：

* 代码随想录的协程库项目：[coroutine-lib](https://github.com/youngyangyang04/coroutine-lib)
* [协程Part1-boost.Coroutine.md](https://www.cnblogs.com/pokpok/p/16932735.html)
    * 说明：[boost.coroutine](https://www.boost.org/doc/libs/latest/libs/coroutine/doc/html/coroutine/overview.html)已经被标记为`已过时（deprecated）`了，不过可以从中学习理解协程的基本原理，新的协程实现为 [boost.coroutine2](https://www.boost.org/doc/libs/latest/libs/coroutine2/doc/html/index.html)。
* [sylar开源项目 -- 协程模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10060957)
* 以及在[RocksDB学习笔记（三） -- RocksDB中的一些特性设计和高性能相关机制](https://xiaodongq.github.io/2025/04/30/rocksdb-performance-mechanism/)中未展开的几篇协程相关参考文章
    * [实现一个简单的协程](https://www.bluepuni.com/archives/implements-coroutine/)
    * [从无栈协程，到 Asio 的协程实现](https://www.bluepuni.com/archives/stackless-coroutine-and-asio-coroutine/)
    * [从 C++20 协程，到 Asio 的协程适配](https://www.bluepuni.com/archives/cpp20-coroutine-and-asio-coroutine/)
* 协程库：
    * [boost.coroutine2](https://www.boost.org/doc/libs/latest/libs/coroutine2/doc/html/index.html)
    * [libco](https://github.com/Tencent/libco)，腾讯开源的协程栈，广泛用于微信中
    * [libgo](https://github.com/yyzybb537/libgo)，C++实现的Go风格协程库

## 2. 协程基础

`协程`是支持对执行进行`挂起（suspend，也称yield）`和`恢复（resume）`的程序。（[维基百科 -- Coroutine](https://en.wikipedia.org/wiki/Coroutine)）

也可称`协程`为 **轻量级线程** 或 **用户态线程**，协程的本质就是`函数`和`函数运⾏状态`的组合，**相对于函数**一旦调用就要从头执行直到退出，协程可以多次挂起和恢复。

* 协程退出/挂起的操作一般称为`yield`，此时的执行状态会被存储起来，称为**协程上下文**，协程上下文包括CPU寄存器状态、局部变量和栈帧状态等。
* 协程创建后，其运行和`yield`、`resume`完全**由应用程序控制**，不经过内核调度。相对而言，线程的`运行和调度`则需要内核进行控制。
* 协程的上下文切换开销
    * 在之前的 [CPU及内存调度（一） -- 进程、线程、系统调用、协程上下文切换](https://xiaodongq.github.io/2025/03/09/context-switch) 中对比过几种上下文切换的时机和开销，此处贴一下作为参考。依赖不同硬件，参考数量级即可。
    * 进程上下文切换：`2.7us到5.48us之间`
    * 线程上下文切换：`3.8us`左右
    * 系统调用：`200ns`
    * 协程切换：`120ns`（用户态）

**协程分类：**

* `对称协程（symmetric coroutine）` 和 `非对称协程（asymmetric coroutine）`
    * 对称协程：协程可以通过**协程调度器**不受限制地将**控制权/调度权**转移给任何其他协程
    * 非对称协程：协程间存在**调用方->被调用方**的关系，协程出让调度权的目标只能是它的调用者。
    * 在对称协程中，每个子协程除了运行自身逻辑，还要负责选出下一个合适的协程进行切换，即还要充当调度器的角色，所以**对称协程更灵活，但实现更为复杂**；非对称协程中则可借助专门的调度器来调度协程，只运行自己的入口函数。
* `有栈协程` 和 `无栈协程`
    * 有栈协程：用**独立的执行栈**保存上下文信息。
        * 有栈协程又区分`独立栈`和`共享栈`
        * 独立栈时协程的栈空间都是独立的，且大小固定；
        * 共享栈则是所有协程在`运行`时使用同一个栈空间，`resume`切换时需要将`yield`时保存的栈内容**拷贝**到运行时的栈空间。
    * 无栈协程：不需独立的执行栈，上下文信息放在公共内存
    * 调用栈示意，可了解：[有栈协程与无栈协程](https://mthli.xyz/stackful-stackless/)

## 3. 协程库实现结构

基于`sylar`中的协程库实现来学习协程栈的结构原理。



## 4. 小结


## 5. 参考


