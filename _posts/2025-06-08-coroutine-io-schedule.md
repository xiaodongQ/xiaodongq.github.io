---
title: 协程梳理实践（三） -- 协程IO事件调度和系统接口封装
description: 梳理sylar协程中的IO事件调度，以及对系统IO的hook封装
categories: [并发与异步编程]
tags: [协程, 异步编程]
---


## 1. 引言

前文梳理了协程的基本实现 和 协程在多线程情况下的调度，只是搭起了一个架子，协程任务也比较简单，并未涉及到网络、硬盘IO等跟业务关联紧密的操作。

本篇梳理的内容比较实用，通过协程中结合网络IO事件、系统调用封装（hook），能更高效利用系统资源，较大提升应用程序的性能。也是对`sylar`协程梳理的最后一篇，后续针对其他协程库以及项目中的应用进行展开和实践，并回到`Ceph`项目的梳理支线当中。



## 2. 小结


## 3. 参考

* [coroutine-lib](https://github.com/youngyangyang04/coroutine-lib)
* [sylar -- IO协程调度模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10061031)
* LLM
