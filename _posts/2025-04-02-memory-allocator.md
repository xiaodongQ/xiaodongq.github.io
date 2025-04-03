---
layout: post
title: CPU及内存调度（三） -- tcmalloc、jemalloc内存分配器
categories: CPU及内存调度
tags: 内存
---

* content
{:toc}

梳理 ptmalloc、tcmalloc 和 jemalloc 内存分配器，并进行内存相关实验，工具：Massif、AddressSanitizer、Memory Leak火焰图。



## 1. 背景

[CPU及内存调度（二） -- Linux内存管理](https://xiaodongq.github.io/2025/03/20/memory-management/) 中梳理学习了Linux的虚拟内存结构，以及进程、线程创建时的大致区别，本篇梳理 ptmalloc、tcmalloc和 jemalloc 几个业界常用的内存分配器。

并利用 [Valgrind Massif](https://valgrind.org/docs/manual/ms-manual.html)、[AddressSanitizer](https://github.com/google/sanitizers/wiki/AddressSanitizer) 进行内存相关实验，以及 [并发与异步编程（三） -- 性能分析工具：gperftools和火焰图](https://xiaodongq.github.io/2025/03/14/async-io-example-profile/) 中未展开的 [Memory Leak and Growth火焰图](https://www.brendangregg.com/FlameGraphs/memoryflamegraphs.html)。

几篇参考文章：

* [ptmalloc、tcmalloc与jemalloc对比分析](https://www.cyningsun.com/07-07-2018/memory-allocator-contrasts.html)
* [使用 jemalloc profile memory](https://www.jianshu.com/p/5fd2b42cbf3d)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 总体说明

### 2.1. 内存分配器

业界常见的库包括：ptmalloc、tcmalloc、jemalloc

* ptmalloc 是 GNU C库（glibc）的默认分配器
    * 多线程环境下的通用内存分配
    * 核心机制
        * 使用 `arena（分配区）`，每个线程优先使用独立 arena（数量有限，默认为核心数的 8 倍）
        * 小对象通过线程本地缓存分配，大对象直接从中央堆分配。
        * 通过锁保护 `arena`，当线程数超过 `arena` 数时，竞争导致性能下降
    * 优点：成熟稳定，与 glibc 深度集成；支持多线程，对小对象分配有一定优化
    * **缺点**：高并发场景下**锁竞争**明显，**内存碎片**较多（尤其是长周期服务）
    * 适用于通用场景，对性能要求不极端的中小型应用
* tcmalloc 全称是`Thread-Caching Malloc`，由Google开发。
    * 设计目标：优化多线程性能，减少内存分配延迟
    * 核心机制
        * **线程本地缓存**：每个线程独立缓存小对象（默认 ≤ 256KB），无需锁
        * 中央堆管理大对象，采用自旋锁减少竞争
        * 定期回收线程缓存中的空闲内存，平衡内存占用
    * 优点：高并发下性能优异（尤其小对象频繁分配）；内存碎片较少，提供内存分析工具（如 heap profiler）
    * 缺点：线程缓存可能占用较多内存（需权衡缓存大小与性能）
    * 适用场景：多线程服务、高频小对象分配（如 Web 服务器）
* jemalloc，Facebook开发，后成为 FreeBSD 默认分配器
    * 设计目标：降低内存碎片，提升多线程和长期运行服务的稳定性
    * 核心机制
        * 多 arena 分配：每个线程绑定特定 arena，动态扩展 arena 数量减少竞争
        * 精细化大小分类：将内存划分为多个 size class，减少内部碎片
        * 主动合并空闲内存：延迟重用策略降低外部碎片
    * 优点：内存碎片最少，长期运行服务内存利用率高；多线程性能接近 tcmalloc，扩展性强
    * 缺点：配置较复杂，默认策略可能不如 tcmalloc 激进
    * 适用场景：长期运行的高负载服务（如数据库、实时系统）
    * Rust 早期默认 jemalloc，后切换为系统默认的分配器（如 Unix 的 ptmalloc）

### 2.2. 工具说明

1、[Valgrind Massif](https://valgrind.org/docs/manual/ms-manual.html)

* Valgrind提供的堆分析器`Massif`，用于监控程序的堆内存使用情况，可辅助识别内存泄漏和不必要的内存使用
    * Valgrind的`Memcheck`工具（默认）用于识别明确的内存泄漏，不过有些内存申请了只是未被有效使用则识别不到，此时可利用`Massif`辅助分析
* 性能影响：程序变慢 `20` 倍左右（`10~30`）
* 使用方式：`-g`编译；`valgrind --tool=massif ./a.out`，会生成一个分析文件；`ms_print ./massif.out.18042`输出报告

2、 Google的`Sanitizer`系列工具，在gcc和clang中都集成了，通过`-fsanitize=`即可开启，还可以在程序运行时动态进行开关

* AddressSanitizer（`ASan`），检测内存访问错误，如越界访问、使用已释放的内存（悬空指针）、重复释放等
    * `-fsanitize=address`
    * 性能影响（仅作参考）：程序变慢约2倍（取决于代码复杂度）；内存占用增加约2倍
* LeakSanitizer（`LSan`），检测内存泄漏
    * `-fsanitize=leak`
    * 性能影响：运行时开销极低，与 ASan 结合时影响较小（约 1-2 倍）；内存轻微增加
* MemorySanitizer（`MSan`），检测程序中使用未初始化的内存
    * `-fsanitize=memory`
    * 性能影响：程序变慢约3倍；影子内存与程序内存1:1，内存占用显著增加
* ThreadSanitizer（`TSan`），检测多线程程序中的数据竞争和**死锁**
    * `-fsanitize=thread`
    * 性能影响：变慢约5-15倍；内存消耗增加5-10倍
* UndefinedBehavaiorSnitizer（`UBSan`），检测未定义行为，如整数溢出、空指针解引用、类型转换错误等
    * `-fsanitize=undefined`
    * 性能影响：开销通常小于10%

对比汇总：

| 工具               | 检测类型                  | 性能影响（时间） | 内存占用       |
|--------------------|--------------------------|------------------|----------------|
| **AddressSanitizer (ASan)** | 内存访问错误、泄漏       | 2×              | 高（虚拟内存） |
| **ThreadSanitizer (TSan)**  | 数据竞争、死锁           | 5-15×           | 极高           |
| **MemorySanitizer (MSan)**  | 未初始化内存使用         | 3×              | 高             |
| **UndefinedBehaviorSanitizer (UBSan)** | 未定义行为       | <10%            | 低             |
| **Valgrind**       | 综合检测（内存错误、性能） | 20×             | 极高           |

使用建议：

* 快速开发调试：优先使用 ASan 或 UBSan（性能影响小，覆盖常见问题）。
    * ASan（内存错误） + UBSan（未定义行为） + LSan（泄漏检测）覆盖大部分常见问题
* 多线程问题：使用 TSan。
* 未初始化内存：使用 MSan（需确保依赖库支持）。
* 全面检测：分阶段使用不同工具，避免同时启用多个工具（如 ASan + TSan 冲突）。
* 性能敏感场景：禁用 Sanitizer 或仅在关键模块启用。
* 遗留系统：Valgrind 仍为无源码调试的备选方案

Sanitizer工具使用时需要用系统默认的常规内存分配器，跟踪标准内存管理函数，比如RocksDB里使用时就禁用了jemalloc：

![sanitizer-jemalloc](/images/2025-04-03-sanitizer-jemalloc.png)

3、 [Memory Leak火焰图](https://www.brendangregg.com/FlameGraphs/memoryflamegraphs.html)

借助`perf`和`eBPF`来生成内存的火焰图，文章介绍了4种方法：

* 1、追踪用户态的 `malloc()`, `free()`
    * 使用bcc下的 stackcount 工具采集用户态的内存分配
        * `/usr/share/bcc/tools/stackcount -p $(pidof mysqld) -U c:malloc > out_mysqld.stack`
        * 生成火焰图：`stackcollapse.pl < out_mysqld.stack | flamegraph.pl --color=mem --title="malloc() Flame Graph" --countname="calls" > out_mysqld.svg`
    * **memleak**：但是要检查内存泄漏的话，需要同时追踪`malloc`、`realloc`、`calloc`、`posix_memalign`等等库函数调用，bcc里的memleak已经实现了，可以直接用
        * 采集：`/usr/share/bcc/tools/memleak -p $(pidof mysqld) > memleak_mysqld.stack`，并用客户端连接mysql触发一些查询操作
    * 性能对比：
        * 追踪`uprobes`使程序变慢 4 倍（4.15内核）
        * libtcmalloc 的堆采集，则变慢 6 倍
* 2、追踪系统调用：`brk()`
    * 比用户态的`malloc`频率低很多
    * 所以可以用`perf`来采集：`perf record -e syscalls:sys_enter_brk -a -g -- sleep 10`
        * `perf script |stackcollapse-perf.pl | flamegraph.pl --color=mem --title="Heap Expansion Flame Graph" --countname="calls" > brk.svg`
    * 也可以用bcc：`/usr/share/bcc/tools/stackcount SyS_brk`
        * **TODO**
* 3、追踪系统调用：`mmap()`
    * `perf record -e syscalls:sys_enter_mmap -a -g -- sleep 10`
    * `/usr/share/bcc/tools/stackcount SyS_mmap`
* 4、追踪缺页中断：`page-faults`
    * `perf record -e page-fault -a -g -- sleep 30`
    * `/usr/share/bcc/tools/stackcount 't:exceptions:page_fault_*'`

## 3. 小结



## 4. 参考

* [ptmalloc、tcmalloc与jemalloc对比分析](https://www.cyningsun.com/07-07-2018/memory-allocator-contrasts.html)
* [使用 jemalloc profile memory](https://www.jianshu.com/p/5fd2b42cbf3d)
* [Memory Leak and Growth火焰图](https://www.brendangregg.com/FlameGraphs/memoryflamegraphs.html)
* [Massif](https://valgrind.org/docs/manual/ms-manual.html)
* [AddressSanitizer](https://github.com/google/sanitizers/wiki/AddressSanitizer)