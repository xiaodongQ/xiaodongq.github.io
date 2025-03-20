---
layout: post
title: CPU及内存调度（二） -- Linux内存管理
categories: CPU及内存调度
tags: 内存
---

* content
{:toc}

CPU和内存调度相关学习实践系列，本篇梳理Linux内存管理。



## 1. 背景

在[CPU及内存调度（一） -- 进程、线程、系统调用、协程上下文切换](https://xiaodongq.github.io/2025/03/09/context-switch)中已经介绍过Linux通过页表机制进行内存映射管理，涉及TLB、MMU、缺页中断等，并发与异步编程系列梳理学习中，也涉及内存序和CPU缓存等问题，本篇开始梳理学习Linux内存管理。

主要参考：

* [一步一图带你深入理解 Linux 虚拟内存管理](https://mp.weixin.qq.com/s/uWadcBxEgctnrgyu32T8sQ)
* [一步一图带你深入理解 Linux 物理内存管理](https://mp.weixin.qq.com/s/Cn-oX0W5DrI2PivaWLDpPw)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*


## 2. 小结



## 3. 参考

