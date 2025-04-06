---
layout: post
title: CPU及内存调度（四） -- ptmalloc、tcmalloc、jemalloc内存分配器
categories: CPU及内存调度
tags: 内存
---

* content
{:toc}

梳理 ptmalloc、tcmalloc 和 jemalloc 内存分配器。



## 1. 背景

[CPU及内存调度（二） -- Linux内存管理](https://xiaodongq.github.io/2025/03/20/memory-management/) 中梳理学习了Linux的虚拟内存结构，以及进程、线程创建时的大致区别。内存的布局和分配、释放机制，跟程序的性能息息相关，比如内存分配器在多线程场景下的锁竞争、`brk`/`mmap`不同场景下的使用、什么场景会延迟升高、内存碎片等。

程序调用`malloc`/`free`函数申请和释放内存，内存分配器则提供对内存的集中管理。理解所用内存分配器的内在逻辑，在程序设计以及出现内存相关性能瓶颈时，有助于问题理解和根因定位，并进行针对性的性能优化。本篇就来梳理下 `ptmalloc`、`tcmalloc`和 `jemalloc` 几个业界常用的内存分配器，了解其内部实现的主要机制。

结合源码和几篇参考文章：

* [ptmalloc、tcmalloc与jemalloc对比分析](https://www.cyningsun.com/07-07-2018/memory-allocator-contrasts.html)
* [内存分配器ptmalloc,jemalloc,tcmalloc调研与对比](https://geekdaxue.co/read/ixxw@it/memory_allocators)
    * 原文是：[内存分配器ptmalloc,jemalloc,tcmalloc调研与对比](https://blog.csdn.net/Rong_Toa/article/details/110689404)，但CSDN阅读体验太差
* [使用 jemalloc profile memory](https://www.jianshu.com/p/5fd2b42cbf3d)
* [百度工程师带你探秘C++内存管理（ptmalloc篇）](https://mp.weixin.qq.com/s/ObS65EKz1c3jooQx6KJ6uw)

## 2. 总体说明

常见的内存分配器：ptmalloc、tcmalloc、jemalloc。

* **ptmalloc** 全称是`Per-Thread Malloc`，是 GNU C库（glibc）的默认分配器
    * 多线程环境下的通用内存分配器
    * 核心机制
        * 使用 `arena（分配区）`，每个线程优先使用独立 arena（数量有限，默认为核心数的 8 倍）
        * 小对象通过线程本地缓存分配，大对象直接从中央堆分配。
        * 通过锁保护 `arena`，当线程数超过 `arena` 数时，竞争导致性能下降
    * 优点：成熟稳定，与 glibc 深度集成；支持多线程，对小对象分配有一定优化
    * **缺点**：高并发场景下**锁竞争**明显，**内存碎片**较多（尤其是长周期服务）
    * 适用于通用场景，对性能要求不极端的中小型应用
* **tcmalloc** 全称是`Thread-Caching Malloc`，由Google开发。
    * 设计目标：优化多线程性能，减少内存分配延迟
    * 核心机制
        * **线程本地缓存**：每个线程独立缓存小对象（默认 ≤ 256KB），无需锁
        * 中央堆管理大对象，采用自旋锁减少竞争
        * 定期回收线程缓存中的空闲内存，平衡内存占用
    * 优点：高并发下性能优异（尤其小对象频繁分配）；内存碎片较少，提供内存分析工具（如 heap profiler）
    * 缺点：线程缓存可能占用较多内存（需权衡缓存大小与性能）
    * 适用场景：多线程服务、高频小对象分配（如 Web 服务器）
* **jemalloc**，命名以作者`Jason Evans`的名称作缩写，由Facebook（现Meta）开发，后成为 FreeBSD 默认分配器
    * 设计目标：降低内存碎片，提升多线程和长期运行服务的稳定性
    * 核心机制
        * 多 arena 分配：每个线程绑定特定 arena，动态扩展 arena 数量减少竞争
        * 精细化大小分类：将内存划分为多个 size class，减少内部碎片
        * 主动合并空闲内存：延迟重用策略降低外部碎片
    * 优点：内存碎片最少，长期运行服务内存利用率高；多线程性能接近 tcmalloc，扩展性强
    * 缺点：配置较复杂，默认策略可能不如 tcmalloc 激进
    * 适用场景：长期运行的高负载服务（如数据库、实时系统）
    * Rust 早期默认 jemalloc，后切换为系统默认的分配器（如 Unix 的 ptmalloc）

## 3. ptmalloc

### 3.1. 历史迭代说明

历史迭代：glibc的内存分配器ptmalloc，起源于`Doug Lea`的`malloc`，或者叫`dlmalloc`。由`Wolfram Gloger`改进得到可以支持多线程。（**说明：下面篇幅中分别称dlmalloc和ptmalloc，ptmalloc指代当前glibc的版本**）

两位大佬的介绍：

* `Doug Lea（道格.利）`是计算机科学领域的著名专家，尤其在Java并发编程方面贡献卓越。
    * 他是《Java并发编程实战》（Java Concurrency in Practice）的作者之一，该书被视为并发编程领域的经典
    * 他开发了早期的util.concurrent库，后被纳入JDK
    * JDK 1.2中的Collections概念部分源于他在1995年发布的早期集合库
    * 他曾作为JCP（Java Community Process）个人成员参与Java标准制定
    * Doug Lea 的 dlmalloc 是 C/C++ 内存管理领域的基石之一，尽管现在有更现代的内存分配器，但其设计思想仍被广泛借鉴
* `Wolfram Gloger` 是一位德国计算机科学家，以其在内存管理和动态内存分配器方面的贡献而闻名
    * 他对于 Doug Lea 的 dlmalloc 的改进版本：ptmalloc（Per-Thread Malloc），支持多线程环境下的高效内存分配，并被集成到 glibc（GNU C Library）中，成为 Linux 系统默认的 malloc 实现

dlmalloc介绍：[A Memory Allocator](https://gee.cs.oswego.edu/dl/html/malloc.html)，代码：[malloc.c](https://gee.cs.oswego.edu/pub/misc/malloc.c)。自己也归档了一份用于对比学习：[dlmalloc_src](https://github.com/xiaodongQ/prog-playground/tree/main/memory/dlmalloc_src)。

当前glibc（本地fork并切换了2.28版本）的代码注释中，也展示了上述迭代经过。并且说明了为什么用这个版本的malloc：

> 这并不是有史以来最快、最节省空间、最可移植或最可调优的 malloc 实现。然而，它在速度、空间节省、可移植性和可调优性之间达到了一致的平衡。正因如此，它成为了一个适用于大量使用 malloc 的程序的优秀通用分配器。

```c
// glibc/malloc/malloc.c
/*
  This is a version (aka ptmalloc2) of malloc/free/realloc written by
  Doug Lea and adapted to multiple threads/arenas by Wolfram Gloger.

  There have been substantial changes made after the integration into
  glibc in all parts of the code.  Do not look for much commonality
  with the ptmalloc2 version.

* Version ptmalloc2-20011215
  based on:
  VERSION 2.7.0 Sun Mar 11 14:14:06 2001  Doug Lea  (dl at gee)
...
* Why use this malloc?

  This is not the fastest, most space-conserving, most portable, or
  most tunable malloc ever written. However it is among the fastest
  while also being among the most space-conserving, portable and tunable.
  Consistent balance across these factors results in a good general-purpose
  allocator for malloc-intensive programs.
...
```

### 3.2. dlmalloc

先简单看一下基础版本的`dlmalloc`，有助于理解后续的ptmalloc版本的设计思路、解决了什么问题。

代码量也并不多，[tokei](https://github.com/XAMPPRocky/tokei) 统计有 3649 行，[calltree.pl](https://github.com/satanson/cpp_etudes) 统计只有 2593 行。

```sh
# tokei
[CentOS-root@xdlinux ➜ dlmalloc_src git:(main) ✗ ]$ tokei -f malloc.c 
===============================================================================================
 Language                            Files        Lines         Code     Comments       Blanks
===============================================================================================
 C                                       1         6291         3649         2149          493
-----------------------------------------------------------------------------------------------
 malloc.c                                          6291         3649         2149          493
===============================================================================================
 Total                                   1         6291         3649         2149          493
===============================================================================================

# calltree.pl
[CentOS-root@xdlinux ➜ dlmalloc_src git:(main) ]$ calltree.pl main '' 1 1 1
preprocess_all_cpp_files
...
extract lines: 2593
function definition after merge: 90
```

1、`Boundary Tags` 和 `Binning` 设计

* `Boundary Tags` 和 `Binning` 两个核心设计，从dlmalloc的早期版本就一直保留了下来
    * Boundary Tags：位于每个分配的内存块的头部和尾部，记录内存块的大小和状态（已分配或空闲），从而支持快速的内存合并操作、查找大小操作
    * Binning：用于分类管理不同大小的空闲内存块，根据其大小被放入不同的“bin”（桶）中，便于快速查找适合的内存块
* 参考：[A Memory Allocator](https://gee.cs.oswego.edu/dl/html/malloc.html)

![dlmalloc-core-design](/images/2025-04-06-dlmalloc-core.png)

2、线程安全性：启用加锁，需要编译时指定`USE_LOCKS`为非0（默认为0-不启用），`-DUSE_LOCKS=1`

* 另外几个锁相关的宏：`USE_SPIN_LOCKS`、`USE_RECURSIVE_LOCKS`

因为后续准备梳理下锁相关的内容，这里简要梳理学习下dlmalloc中的相关逻辑，其中的兼容性设计、自旋锁实现都值得学习。

锁相关的部分调整了一下缩进：

```c
// prog-playground/memory/dlmalloc_src/malloc.c
#if USE_LOCKS > 1
    // 用户自定义锁
#elif USE_SPIN_LOCKS // 使用自旋锁
    // gcc>=4.1版本，CAS锁，使用gcc提供的 __sync_lock_test_and_set，实现原子交换。常用于实现自旋锁（spinlock）或其他轻量级同步机制
    #if defined(__GNUC__)&& (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 1))
        #define CAS_LOCK(sl)     __sync_lock_test_and_set(sl, 1)
        #define CLEAR_LOCK(sl)   __sync_lock_release(sl)
    // 老版本的gcc，则其中自行实现了自旋锁函数
    #elif (defined(__GNUC__) && (defined(__i386__) || defined(__x86_64__)))
        static FORCEINLINE int x86_cas_lock(int *sl) {
            int ret;
            int val = 1;
            int cmp = 0;
            // GCC 的 __asm__ 语法编写的内联汇编代码，用于实现一个原子级的 比较并交换（Compare-And-Swap, CAS） 操作
            // 通常用于实现低级别的同步原语，比如锁或原子变量
            __asm__ __volatile__  ("lock; cmpxchgl %1, %2" // cmpxchgl：x86 架构中的指令，用于执行比较并交换操作
                                    : "=a" (ret)
                                    : "r" (val), "m" (*(sl)), "0"(cmp)
                                    : "memory", "cc");
            return ret;
        }
        // x86_clear_lock 解锁函数等的实现
        ...
        #define CAS_LOCK(sl)     x86_cas_lock(sl)
        #define CLEAR_LOCK(sl)   x86_clear_lock(sl)
        ...
    // Windows平台的锁（用的是临界区，critical sections）
    #else /* Win32 MSC */
        ...
    #endif /* ... gcc spins locks ... */

    /* How to yield for a spin lock */
    // 定义不同平台使用的 yield 函数（出让时间片）
    // 这里只看下非solaris的linux平台，用的是 sched_yield()
    #define SPIN_LOCK_YIELD   sched_yield();
    
    // 递归锁
    // 不使用递归锁的情况
    #if !defined(USE_RECURSIVE_LOCKS) || USE_RECURSIVE_LOCKS == 0
        ...
    // 使用递归锁的情况
    #else /* USE_RECURSIVE_LOCKS */
        // 里面也做了Linux和Windows平台的兼容，还用上述的 自旋锁 来实现递归锁
        ...
    #endif /* USE_RECURSIVE_LOCKS */
// Windows临界区
#elif defined(WIN32) /* Win32 critical sections */
    ...
// pthread锁
#else /* pthreads-based locks */
    // 这里就是常规 pthread_mutex 相关定义和操作了
    #define MLOCK_T               pthread_mutex_t
    #define ACQUIRE_LOCK(lk)      pthread_mutex_lock(lk)
    #define RELEASE_LOCK(lk)      pthread_mutex_unlock(lk)
    ...
#endif /* ... lock types ... */
```

接口定义：

```c
// prog-playground/memory/dlmalloc_src/malloc.c
...
#define dlfree                 free
#define dlmalloc               malloc
#define dlmemalign             memalign
#define dlposix_memalign       posix_memalign
#define dlrealloc              realloc
...
DLMALLOC_EXPORT void* dlmalloc(size_t);
DLMALLOC_EXPORT void  dlfree(void*);
...
```

dlmalloc逻辑，可以看到锁范围还是很大的：

```c
void* dlmalloc(size_t bytes) {
#if USE_LOCKS
    // 里面会初始化锁
    ensure_initialization(); /* initialize in sys_alloc if not using locks */
#endif
    // 若启用锁则其中会先加锁
    if (!PREACTION(gm)) {
        // 具体malloc算法逻辑，此处略
        ...
    postaction:
        // 若启用锁，则其中会解锁
        POSTACTION(gm);
        return mem;
    }
}
```

### 3.3. ptmalloc

从代码注释里看简要设计：

```c
// glibc/malloc/malloc.c
/*
...
  The main properties of the algorithms are:
  * For large (>= 512 bytes) requests, it is a pure best-fit allocator,
    with ties normally decided via FIFO (i.e. least recently used).
  * For small (<= 64 bytes by default) requests, it is a caching
    allocator, that maintains pools of quickly recycled chunks.
  * In between, and for combinations of large and small requests, it does
    the best it can trying to meet both goals at once.
  * For very large requests (>= 128KB by default), it relies on system
    memory mapping facilities, if supported.
...
*/
```

malloc_chunk 分配结构：

```c
// glibc/malloc/malloc.c
struct malloc_chunk {

  INTERNAL_SIZE_T      mchunk_prev_size;  /* Size of previous chunk (if free).  */
  INTERNAL_SIZE_T      mchunk_size;       /* Size in bytes, including overhead. */

  struct malloc_chunk* fd;         /* double links -- used only if free. */
  struct malloc_chunk* bk;

  /* Only used for large blocks: pointer to next larger size.  */
  struct malloc_chunk* fd_nextsize; /* double links -- used only if free. */
  struct malloc_chunk* bk_nextsize;
};
```

## 4. tcmalloc

## 5. jemalloc


## 6. 小结


## 7. 参考

* [ptmalloc、tcmalloc与jemalloc对比分析](https://www.cyningsun.com/07-07-2018/memory-allocator-contrasts.html)
* [内存分配器ptmalloc,jemalloc,tcmalloc调研与对比](https://geekdaxue.co/read/ixxw@it/memory_allocators)
* [使用 jemalloc profile memory](https://www.jianshu.com/p/5fd2b42cbf3d)
* [百度工程师带你探秘C++内存管理（ptmalloc篇）](https://mp.weixin.qq.com/s/ObS65EKz1c3jooQx6KJ6uw)
