---
title: CPU及内存调度（五） -- ptmalloc、tcmalloc、jemalloc、mimalloc内存分配器（下）
description: 继续梳理 tcmalloc、jemalloc 和 mimalloc 内存分配器。
categories: [CPU及内存调度]
tags: [内存]
---

继续梳理 ptmalloc、tcmalloc、jemalloc 和 mimalloc 内存分配器。

## 1. 背景

上篇梳理了dlmalloc和ptmalloc，继续来看tcmalloc、jemalloc 和 mimalloc 几个分配器。

结合源码和几篇参考文章：

* tcmalloc
    * 仓库基于2.7.90分支：[gperftools-2.7.90](https://github.com/gperftools/gperftools/tree/gperftools-2.7.90)
        * 本篇分析的代码分支和自己本地的CentOS8对应版本保持一致：gperftools-devel-2.7-9.el8.x86_64
    * [TCMalloc Overview](https://google.github.io/tcmalloc/overview.html)
    * [TCMalloc Design](https://google.github.io/tcmalloc/design.html)
    * [记一次 TCMalloc Debug 经历 #2](https://zhuanlan.zhihu.com/p/81683409)，其中的定位思路值得学习
        * 其中`dlopen`和`tcmalloc`使用时的死锁问题，在2.7.90分支已经修复了
* jemalloc
    * 仓库：[jemalloc](https://github.com/jemalloc/jemalloc)
    * [网站](https://jemalloc.net/)
    * [Jemalloc内存分配与优化实践](https://mp.weixin.qq.com/s/U3uylVKZ-FsMjdeX3lymog)
* mimalloc
    * 仓库：[mimalloc](https://github.com/microsoft/mimalloc)
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
    * 依赖 `RSEQ（Restartable Sequences）`可重启序列特性

缓存对于申请和释放同等重要，若没有缓存，则释放内存时需要频繁移动内存到`中间层`的`Central Free List`，会严重影响性能。

如果`Front-end`的内存不足，会向中间层`Middle-end`申请一批内存，而后填充到`Front-end`。

对象申请和释放：

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

`RSEQ`机制（可重启序列）：

* Linux 内核提供的一种机制，允许用户空间代码定义一个“可重启序列”（restartable sequence），即一段关键代码区域
* 如果这段代码在执行过程中被 *中断*（例如由于线程被重新调度到另一个 CPU 核心），内核会确保该代码可以**安全地重新执行**，而不会导致数据损坏或不一致。
* 适用于实现 `无锁（lock-free）数据结构` 和 `高效线程本地操作`，比如 线程本地计数器、分配器等。
* RSEQ 的无锁性质使得 TCMalloc 能够减少锁争用，从而提升多线程程序的性能

进一步内容，详见：[TCMalloc Design](https://google.github.io/tcmalloc/design.html)。

### 2.2. 中间层（Middle-end）

`中间层（Middle-end）`：负责提供内存给 `前端（Front-end）`，以及归还内存给 `后端（Back-end）`。

中间层由 **Transfer Cache** 和 **Central Free List** 组成。每个`size-class`里面包含一个`transfer cache`和一个`central free list`，并通过一个`mutex`进行cache的保护。

* `Transfer Cache`
    * 其中持有 空闲内存指针 组成的数组，向其中新增和获取对象都很快
    * 当前端申请和归还内存时，都是先到`Transfer Cache`，申请内存时如果`Transfer Cache`满足不了要求，则会访问`Central Free List`。
* `Central Free List`
    * `Central Free List`用来管理`span`中的空闲内存，`span`是`TCMalloc pages`的一个集合。
    * 内存申请时，向`span`里面获取内存对象（object），直到满足需要的内存大小，如果没有足够的对象，则从后端`Back-end`申请更多的`span`
    * 当内存对象释放时，对象会还给`Central Free List`，`对象（object）`会和它所属的`span`映射起来，通过 **`pagemap`** 来维护这个映射关系。当一个span里面的所有object内存都归还了，则这个`span`的内存会归还给后端（`Back-end`）。

#### 2.2.1. Page、Pagemap 和 Spans

TCMalloc管理的`堆内存（heap）`被划分成编译期确定大小的`page`页，一连串连续的`page`页由`span`对象表示。

注意这里的`page`和内核`TLB`中的`page`不是一回事，TCMalloc的page大小（`page size`）目前有4KiB, 8KiB, 32KiB 和 256KiB。

`pagemap`用来查找`object`属于哪个`span`。TCMalloc使用一个2层或者3层的 **`radix树（radix tree）`** 来映射`span`中所有的内存位置，radix是一种紧凑型的前缀树（`Compact Prefix Tree`）。

下图是`pagemap`的`radix树`管理结构：

![tcmalloc-pagemap](/images/tcmalloc-pagemap.png)

span在中间层用于决定从哪个位置返回对象，在后端则用于处理page的范围。

### 2.3. 后端（Back-end）

TCMalloc的后端有3个作用：

* 管理未使用的大内存块（`large chunks`）
* 当没有合适大小的内存提供给内存申请请求时，负责从操作系统（`OS`）获取内存
* 归还不需要的内存给操作系统

TCMalloc中有2种后端：

* 传统的`pageheap`，用于管理`page size`大小的内存块（上述提到的4KB、8KB、32KB和256KB）
* 感知`hugepage`的`pageheap`，管理大页内存，用于提升`TLB`的命中率

### 2.4. 提供的API说明

TCMalloc实现了 C 和 C++ 的动态内存操作API，支持C11, C++11, C++14 和 C++17。

1、C++接口

* 基本的 `new`、`delete`，以及对应的数组变体：`new []`、`delete []`
* C++14的delete：`void operator delete[](void* ptr, std::size_t sz) noexcept;`
* C++17的各类对齐（`overaligned`）操作API

2、C接口

* malloc, calloc, realloc, 和 free

具体接口和说明可见：[TCMalloc Basic Reference](https://google.github.io/tcmalloc/reference.html)。

### 2.5. 代码分析

TODO

## 3. jemalloc

TODO

## 4. mimalloc

TODO

## 5. 小结

梳理学习了TCMalloc的基本框架，代码暂时没看。另外jemalloc、mimalloc两个内存分配器暂留坑，后续分析。

## 6. 参考

* [gperftools-2.7.90](https://github.com/gperftools/gperftools/tree/gperftools-2.7.90)
* [TCMalloc Overview](https://google.github.io/tcmalloc/overview.html)
* [TCMalloc Design](https://google.github.io/tcmalloc/design.html)
* [记一次 TCMalloc Debug 经历 #2](https://zhuanlan.zhihu.com/p/81683409)
* LLM
