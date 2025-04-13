---
title: CPU及内存调度（五） -- ptmalloc、tcmalloc、jemalloc、mimalloc内存分配器（下）
description: 继续梳理 tcmalloc、jemalloc 和 mimalloc 内存分配器。
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

总体架构如下图所示：

![tcmalloc_internals](/images/tcmalloc_internals.png)  
[出处](https://google.github.io/tcmalloc/design.html)

分为3部分：

* 1、`前端（Front-end）`：为应用程序提供快速分配和释放的缓存
* 2、`中间层（Middle-end）`：负责填充前端的缓存
* 3、`后端（Back-end）`：负责从操作系统获取内存

### 2.1. 前端（Front-end）

`前端（Front-end）`：提供快速分配和释放的缓存，有两种形式： **Per-thread Cache** 和 **Per-CPU Cache**
    
前端中的内存缓存同一时刻只服务单一线程，**不需要加锁**，因此分配和释放都很快。

* `Per-thread Cache`：是最开始支持的缓存形式，也是TCMalloc命名的由来（Thread Caching Malloc），但是随着现代应用的线程数规模越来越大，会导致总的线程缓存特别大，或者平均到每个线程的缓存都很小
* `Per-CPU Cache`：更为现代的缓存方式，每个**逻辑核**拥有独自的缓存（每个超线程也是一个逻辑核）

缓存对于申请和释放同等重要，若没有缓存，则释放内存时需要频繁移动内存到`中间层`的`Central Free List`，会严重影响性能。

如果`Front-end`的内存不足，会向中间层`Middle-end`申请一批内存，而后填充到`Front-end`。

1）小对象（small object）的内存申请，映射到`size class数组`进行负责，数组有`60~80`个`size class`成员，分别负责不同大小的小对象，申请的对象大小会取`>=`它的`size class`成员对应的大小。其定义如下：

```c
// tcmalloc/size_classes.cc
static constexpr SizeClassInfo List[] = {
//                                         |    waste     |
//  bytes pages batch   class  objs |fixed sampling|    inc
  {     0,    0,    0},  //  0     0  0.00%    0.00%   0.00%
  {     8,    1,   32},  //  0  1024  0.58%    0.42%   0.00%
  {    16,    1,   32},  //  1   512  0.58%    0.42% 100.00%
  {    32,    1,   32},  //  2   256  0.58%    0.42% 100.00%
  {    64,    1,   32},  //  3   128  0.58%    0.42% 100.00%
  {    72,    1,   32},  //  4   113  1.26%    0.42%  12.50%
  ...
  {204800,   25,    2},  // 78     1  0.02%    0.03%  13.64%
  {229376,   28,    2},  // 79     1  0.02%    0.03%  12.00%
  {262144,   32,    2},  // 80     1  0.02%    0.03%  14.29%
};
```

2）若申请的大小超出一定大小（`kMaxSize`），则直接从`后端（Back-end）`申请，不经过前端和中间层的缓存。

3）内存释放时，小对象内存归还到前端缓存，大对象则直接归还给`pageheap`（后端也称为 PageHeap）

进一步内容，详见：[TCMalloc Design](https://google.github.io/tcmalloc/design.html) 

* 里面具体介绍了大小对象分配、释放
* 以及`Per-CPU`和传统`Per-thread`模式
* `rseq（Restartable Sequence Mechanism）`机制

### 2.2. 中间层（Middle-end）

`中间层（Middle-end）`：负责提供内存给`前端（Front-end）`，以及归还内存给`后端（Back-end）`。

中间层由 **Transfer Cache** 和 **Central Free List** 组成。

* 当前端申请和归还内存时，都是先到`Transfer Cache`

## 3. jemalloc


## 4. 小结


## 5. 参考

* [gperftools-2.7.90](https://github.com/gperftools/gperftools/tree/gperftools-2.7.90)
* [TCMalloc Overview](https://google.github.io/tcmalloc/overview.html)
* [TCMalloc Design](https://google.github.io/tcmalloc/design.html)
* [记一次 TCMalloc Debug 经历 #2](https://zhuanlan.zhihu.com/p/81683409)
* LLM
