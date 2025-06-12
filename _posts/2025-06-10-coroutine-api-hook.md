---
title: 协程梳理实践（四） -- sylar协程API hook封装
description: 梳理sylar协程对标准库和系统API的hook封装
categories: [并发与异步编程]
tags: [协程, 异步编程]
---


## 1. 引言

梳理sylar协程对标准库和系统API的hook封装。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. hook介绍和示例

**hook**实际上就是对系统接口的封装，提供和原始接口一样的函数签名，让使用者在调用时跟调用原始系统接口没有什么差别，但实际上是执行hook接口中的逻辑，可以实现自定义操作+原始接口操作。

sylar中的hook，就是为了在**不重写**代码的情况下，把原有代码中的同步socket操作api都转换为**异步操作**，以提升性能。

hook使用场景示例：**单个线程中**，3个协程分别在默认情况和hook系统api情况下的表现
* 协程1：`sleep(2)`；
* 协程2：在socket fd1 上`send` 100k数据；
* 协程3：在socket fd2 上`recv`数据直到成功

![sylar_coroutine_hook](/images/sylar_coroutine_hook.svg)

* 1、默认情况下，单个线程中的3个协程需要串行。`sleep`期间其他协程无法`resume`运行，`recv`阻塞等待数据发送期间，其他协程也无法运行
* 2、hook情况下，对`sleep`、`send`、`recv`接口进行hook，分别用上节中的**定时器**和**IOManager epoll**，可以避免无意义的阻塞

## 3. 小结


## 4. 参考

* [coroutine-lib](https://github.com/youngyangyang04/coroutine-lib)
* [sylar -- hook模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=16417219)
