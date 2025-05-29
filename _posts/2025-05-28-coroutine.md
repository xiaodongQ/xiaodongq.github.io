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
* 腾讯开源的协程库：[libco](https://github.com/Tencent/libco)
* 以及在[RocksDB学习笔记（三） -- RocksDB中的一些特性设计和高性能相关机制](https://xiaodongq.github.io/2025/04/30/rocksdb-performance-mechanism/)中未展开的几篇协程相关参考文章
    * [实现一个简单的协程](https://www.bluepuni.com/archives/implements-coroutine/)
    * [从无栈协程，到 Asio 的协程实现](https://www.bluepuni.com/archives/stackless-coroutine-and-asio-coroutine/)
    * [从 C++20 协程，到 Asio 的协程适配](https://www.bluepuni.com/archives/cpp20-coroutine-and-asio-coroutine/)

## 2. 协程基础

`协程`是支持对执行进行`挂起（suspend，也称yield）`和`恢复（resume）`的程序。（[维基百科 -- Coroutine](https://en.wikipedia.org/wiki/Coroutine)）

也可称`协程`为 **轻量级线程** 或 **用户态线程**，协程的本质就是`函数`和`函数运⾏状态`的组合，相对于函数，协程可以多次挂起和恢复。

* 


## 3. 小结


## 4. 参考


