---
layout: post
title: CPU及内存调度（四） -- tcmalloc、jemalloc内存分配器
categories: CPU及内存调度
tags: 内存
---

* content
{:toc}

梳理 ptmalloc、tcmalloc 和 jemalloc 内存分配器。



## 1. 背景

[CPU及内存调度（二） -- Linux内存管理](https://xiaodongq.github.io/2025/03/20/memory-management/) 中梳理学习了Linux的虚拟内存结构，以及进程、线程创建时的大致区别。内存布局和内存的分配、释放机制，跟程序的性能息息相关，比如内存分配器在多线程场景下的锁竞争、brk/mmap不同场景下的使用、什么场景会延迟升高、内存碎片等。

程序出现内存相关性能问题时，理解所用内存分配器的内在逻辑有助于问题理解和根因定位，并进行针对性的性能优化。本篇就来梳理下 ptmalloc、tcmalloc和 jemalloc 几个业界常用的内存分配器，了解其内部实现的主要机制。

## 2. 总体说明

常见的内存分配器：ptmalloc、tcmalloc、jemalloc

* **ptmalloc** 是 GNU C库（glibc）的默认分配器
    * 多线程环境下的通用内存分配
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
* **jemalloc**，Facebook（现Meta）开发，后成为 FreeBSD 默认分配器
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



## 4. tcmalloc

## 5. jemalloc


## 6. 小结


## 7. 参考

* [ptmalloc、tcmalloc与jemalloc对比分析](https://www.cyningsun.com/07-07-2018/memory-allocator-contrasts.html)
* [使用 jemalloc profile memory](https://www.jianshu.com/p/5fd2b42cbf3d)
* [百度工程师带你探秘C++内存管理（ptmalloc篇）](https://mp.weixin.qq.com/s/ObS65EKz1c3jooQx6KJ6uw)
