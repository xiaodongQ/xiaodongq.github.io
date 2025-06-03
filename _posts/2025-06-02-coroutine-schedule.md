---
title: 协程梳理实践（二） -- 多线程下的协程调度
description: 梳理多线程下的协程调度
categories: [并发与异步编程]
tags: [协程, 异步编程]
---


## 1. 引言

上一篇梳理了sylar中如何实现一个基本协程，本篇对多线程下的协程调度进行跟踪说明。

## 2. 多线程+协程调度

> 详情可见：[协程调度模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10060963)

从上篇基本协程实现可知，一个线程中可以创建多个协程，协程间会进行挂起和恢复切换，但 **⼀个线程同⼀时刻只能运⾏⼀个协程**。所以一般需要**多线程**来提高协程的效率，这样同时可以有多个协程在运行。

继续学习梳理下sylar里面的协程调度。
* demo代码则可见：`coroutine-lib`中的[3scheduler](https://github.com/xiaodongQ/coroutine-lib/tree/main/fiber_lib/3scheduler)，其中的`fiber.h/fiber.cpp`协程类代码和`2fiber`里是一样的，独立目录只是便于单独测试。




## 3. 小结



## 4. 参考

* [coroutine-lib](https://github.com/youngyangyang04/coroutine-lib)
* [sylar -- 协程调度模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10060963)
* [sylar -- IO协程调度模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10061031)
* LLM
