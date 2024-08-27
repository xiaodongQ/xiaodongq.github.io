---
layout: post
title: 学习Linux存储IO栈（四） -- 通用块层
categories: 存储
tags: 存储 IO
---

* content
{:toc}

学习Linux内核存储栈中的通用块层（block layer）。



## 1. 背景

[学习Linux存储IO栈（二） -- Linux内核存储栈流程和接口](https://xiaodongq.github.io/2024/08/13/linux-kernel-fs/) 中简单带过了一下通用块层，并在 [学习Linux存储IO栈（三） -- eBPF和ftrace跟踪IO写流程](https://xiaodongq.github.io/2024/08/15/linux-write-io-stack) 中追踪IO写流程时追踪到对应的io调度处理相关堆栈，本篇来具体看下通用块层的对应流程。

另外，想起来之前看过的极客时间课程，回头看了下存储模块相关的文章：[24 | 基础篇：Linux 磁盘I/O是怎么工作的（上）](https://time.geekbang.org/column/article/77010)，发现作为概述和索引用来查漏补缺挺好的。之前更多的是对CPU/内存/存储/网络等对应有哪些观测工具和指标有个总览的了解，浮于“知道”（且容易忘）的层面，深入去看则发现有很多东西需要自己另外花心思去啃。这时再看文章有了不同的角度，收获到一些新的东西。

前段时间看别人说《代码整洁之道》常看常有新收获，还有[木鸟杂记](https://www.qtmuniao.com/)大佬对DDIA的重读分享([《DDIA 逐章精读》](https://ddia.qtmuniao.com/#/preface))，都是人在不同认知阶段看到不同的东西。最近在看CSAPP，回想~~早年~~大学时上课，大多都是浮于表面的被动接收，现在趁机会夯实基础，倒可以多动手、多嚼一嚼经典著作。

## 再看下IO栈全貌图

存储IO栈出现很多次了，贯穿整个系列学习：

![linux存储栈_4.10内核](/images/linux-storage-stack-diagram_v4.10.svg)  
[出处](https://www.thomas-krenn.com/en/wiki/Linux_Storage_Stack_Diagram)

此处还是放这张基于4.10内核，更高内核版本也可从上面的出处中获取。

和`VFS`类似，为了减小不同`块设备`的差异带来的影响，Linux用一个统一的`通用块层`来管理各种块设备。



## 6. 小结


## 7. 参考

1、[24 | 基础篇：Linux 磁盘I/O是怎么工作的（上）](https://time.geekbang.org/column/article/77010)

