---
title: CPU及内存调度（五） -- ptmalloc、tcmalloc、jemalloc、mimalloc内存分配器（下）
description: 继续梳理 ptmalloc、tcmalloc、jemalloc 和 mimalloc 内存分配器。
categories: [CPU及内存调度]
tags: [内存]
---

继续梳理 ptmalloc、tcmalloc、jemalloc 和 mimalloc 内存分配器。

## 1. 背景

上篇梳理了dlmalloc和ptmalloc，继续来看tcmalloc、jemalloc 和 mimalloc几个分配器。

结合源码和几篇参考文章：

* tcmalloc
    * 基于2.7.90分支：[gperftools-2.7.90](https://github.com/gperftools/gperftools/tree/gperftools-2.7.90)
        * 本篇分析的代码分支和自己本地的CentOS8对应版本保持一致：gperftools-devel-2.7-9.el8.x86_64
    * [TCMalloc Overview](https://google.github.io/tcmalloc/overview.html)
    * [TCMalloc Design](https://google.github.io/tcmalloc/design.html)
    * [记一次 TCMalloc Debug 经历 #2](https://zhuanlan.zhihu.com/p/81683409)，其中的定位思路值得学习
        * 其中`dlopen`和`tcmalloc`使用时的死锁问题，在2.7.90分支已经修复了
* jemalloc
    * [Jemalloc内存分配与优化实践](https://mp.weixin.qq.com/s/U3uylVKZ-FsMjdeX3lymog)
* [ptmalloc、tcmalloc与jemalloc对比分析](https://www.cyningsun.com/07-07-2018/memory-allocator-contrasts.html)
* [内存分配器ptmalloc,jemalloc,tcmalloc调研与对比](https://geekdaxue.co/read/ixxw@it/memory_allocators)
    * 原文是：[内存分配器ptmalloc,jemalloc,tcmalloc调研与对比](https://blog.csdn.net/Rong_Toa/article/details/110689404)

## 2. TCMalloc

TCMalloc 最初由 `Sanjay Ghemawat` 和 `Paul Menage` 共同开发，作为 Google 性能工具库（Google Performance Tools，后更名为 gperftools）的一部分。关于`Sanjay Ghemawat`大佬，之前在 [leveldb学习笔记（一） -- 整体架构和基本操作](https://xiaodongq.github.io/2024/07/10/leveldb-learn-first/)）梳理学习时也介绍过，他和 `Jeff Dean` 合作开发了许多分布式系统基础架构（如 **MapReduce**、**Bigtable**、**Spanner** 等）。

说明：[google/tcmalloc](https://github.com/google/tcmalloc) 和 [gperftools](https://github.com/gperftools/gperftools) 两个仓库中都有TCMalloc的实现。为了便于扩展和适应Google的内部使用，单独分离出来了`google/tcmalloc`仓库；`gperftools`仓库里除了TCMalloc内存分配器，还有其他几个分析工具。具体可见：[TCMalloc and gperftools](https://google.github.io/tcmalloc/gperftools.html)。

## 3. jemalloc


## 4. 小结


## 5. 参考

* [gperftools-2.7.90](https://github.com/gperftools/gperftools/tree/gperftools-2.7.90)
* [TCMalloc Overview](https://google.github.io/tcmalloc/overview.html)
* [TCMalloc Design](https://google.github.io/tcmalloc/design.html)
* [记一次 TCMalloc Debug 经历 #2](https://zhuanlan.zhihu.com/p/81683409)
* LLM
