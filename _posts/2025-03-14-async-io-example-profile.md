---
layout: post
title: 并发与异步编程（三） -- 性能分析工具：gperftools和火焰图
categories: 并发与异步编程
tags: CPU 存储 异步编程
---

* content
{:toc}

异步编程学习实践系列，demo实验，使用 gperftools 和 火焰图 进行性能分析。本篇先介绍工具。



## 1. 背景

[上一篇](https://xiaodongq.github.io/2025/03/11/async-io/) 介绍了几种异步编程框架，现在来完成 [并发与异步编程（一） -- 实现一个简单线程池](https://xiaodongq.github.io/2025/03/08/threadpool/) 中的TODO，进行异步编程实验，并简单进行分析性能。

* 1、通过 [gperftools](https://github.com/gperftools/gperftools) 采集分析资源消耗情况
* 2、基于 [Brendan Gregg](https://www.brendangregg.com/index.html) 大佬的火焰图（[Flame Graphs](https://www.brendangregg.com/flamegraphs.html)）采集信息进行可视化展示，包括 On-CPU火焰图、Off-CPU火焰图

本篇先介绍工具。

## 2. gperftools工具

gperftools 由 Google 开源，来源于 Google Performance Tools。gperftools集合中包含一个高性能多线程的内存分配器实现，并提供了多种性能分析工具。支持侵入式和非侵入式进行性能采集。

这里是项目地址：[gperftools](https://github.com/gperftools/gperftools)。

安装：除了源码编译，在CentOS上可以直接`yum install gperftools`（会同时安装好`pprof`和其他依赖，如libunwind）

本篇就主要使用其中的工具：

1、 [CPU分析用法](https://github.com/gperftools/gperftools/blob/master/docs/cpuprofile.adoc)

* 生成函数调用图，统计 CPU 时间消耗，定位热点代码
* 支持按函数、模块或地址分析，输出文本或可视化报告（需配合pprof工具）

```sh
1) Link your executable with -lprofiler
2) Run your executable with the CPUPROFILE environment var set:
     $ CPUPROFILE=/tmp/prof.out <path/to/binary> [binary args]
3) Run pprof to analyze the CPU usage
     $ pprof <path/to/binary> /tmp/prof.out      # -pg-like text output
     $ pprof --gv <path/to/binary> /tmp/prof.out # really cool graphical output
```

项目里的CPU分析示例：  
![示例](/images/pprof-test.gif)

2、 [内存分析用法](https://github.com/gperftools/gperftools/blob/master/docs/heapprofile.adoc)

* 跟踪内存分配和释放，检测内存泄漏或过度分配问题
* 可按时间戳或调用栈统计内存使用情况

```sh
1) Link your executable with -ltcmalloc
    # 如果编译时没有-l链接，也可以在执行时使用 LD_PRELOAD
2) Run your executable with the HEAPPROFILE environment var set:
     $ HEAPPROFILE=/tmp/heapprof <path/to/binary> [binary args]
3) Run pprof to analyze the heap usage
     $ pprof <path/to/binary> /tmp/heapprof.0045.heap  # run 'ls' to see options
     $ pprof --gv <path/to/binary> /tmp/heapprof.0045.heap
```

## 3. On-CPU火焰图和技巧

### 3.1. 简要介绍

项目地址：[FlameGraph GitHub](https://github.com/brendangregg/FlameGraph)

Brendan Gregg大佬的火焰图文章合集，都很值得一读：[Flame Graphs](https://www.brendangregg.com/flamegraphs.html)，包含

* [CPU Flame Graphs](https://www.brendangregg.com/FlameGraphs/cpuflamegraphs.html)
* [Off-CPU Flame Graphs](https://www.brendangregg.com/FlameGraphs/offcpuflamegraphs.html)
* 内存泄漏和增长图：[Memory Leak (and Growth) Flame Graphs](https://www.brendangregg.com/FlameGraphs/memoryflamegraphs.html)
* 冷热图集成（即CPU和Off-CPU）：[Hot/Cold Flame Graphs](https://www.brendangregg.com/FlameGraphs/hotcoldflamegraphs.html)
* 红/蓝差分火焰图（即前后对比）：[Differential Flame Graphs](https://www.brendangregg.com/blog/2014-11-09/differential-flame-graphs.html)
* 以及AI相关火焰图介绍：[AI Flame Graphs](https://www.brendangregg.com/blog/2024-10-29/ai-flame-graphs.html)
    * PS：大佬22年去Intel搞云计算和AI了

### 3.2. On-CPU火焰图技巧

On-CPU火焰图使用场景最常见，就不多说了，关注大平顶（即采样数，注意颜色只是用暖色调没其他特别含义）。

如果堆栈比较深，影响查找平顶，有个**小技巧**：使用`--inverted`查看冰柱型火焰图，并结合`--reverse`反转堆栈，有时更直接找到最热的调用。

```sh
[CentOS-root@xdlinux ➜ FlameGraph git:(master) ]$ ./flamegraph.pl -h
Option h is ambiguous (hash, height, help)
USAGE: ./flamegraph.pl [options] infile > outfile.svg

	--title TEXT     # change title text
	--subtitle TEXT  # second level title (optional)
	--width NUM      # width of image (default 1200)
	--height NUM     # height of each frame (default 16)
	--minwidth NUM   # omit smaller functions. In pixels or use "%" for
	                 # percentage of time (default 0.1 pixels)
	--fonttype FONT  # font type (default "Verdana")
	--fontsize NUM   # font size (default 12)
	--countname TEXT # count type label (default "samples")
	--nametype TEXT  # name type label (default "Function:")
	--colors PALETTE # set color palette. choices are: hot (default), mem,
	                 # io, wakeup, chain, java, js, perl, red, green, blue,
	                 # aqua, yellow, purple, orange
	--bgcolors COLOR # set background colors. gradient choices are yellow
	                 # (default), blue, green, grey; flat colors use "#rrggbb"
	--hash           # colors are keyed by function name hash
	--random         # colors are randomly generated
	--cp             # use consistent palette (palette.map)
	--reverse        # generate stack-reversed flame graph
	--inverted       # icicle graph
	--flamechart     # produce a flame chart (sort by time, do not merge stacks)
	--negate         # switch differential hues (blue<->red)
	--notes TEXT     # add notes comment in SVG (for debugging)
	--help           # this message
```

用stress模拟CPU、sync落盘、内存、write磁盘的压力：

```sh
[CentOS-root@xdlinux ➜ flamegraph_sample git:(main) ✗ ]$ stress --cpu 2 --io 2 --vm 2 --hdd 2 --timeout 5s
stress: info: [33388] dispatching hogs: 2 cpu, 2 io, 2 vm, 2 hdd
stress: info: [33388] successful run completed in 6s

# 另一个终端进行perf采集：
perf record -a -g
# 生成火焰图
perf script -i perf.data| stackcollapse-perf.pl | flamegraph.pl --reverse --inverted > stress_2cpu_2io_2vm_2hdd_icicle.svg
```

1）默认火焰图：

[default](/images/stress_2cpu_2io_2vm_2hdd.svg)

2）冰柱型且反转堆栈，有时尖刺太多的话会比较有效：

[reverse_inverted](/images/stress_2cpu_2io_2vm_2hdd_icicle.svg)

## 4. Off-CPU火焰图

这里重点说下**Off-CPU火焰图**，对于非CPU操作，提供了很实用的采集观测工具，比如`Off-CPU`、`文件IO`、`block IO`、还有`线程唤醒`的链路追踪。具体见：[Off-CPU Flame Graphs](https://www.brendangregg.com/FlameGraphs/offcpuflamegraphs.html)。

### 4.1. bcc eBPF工具集

由于Off-CPU相关指标很多都涉及内核层面，perf采样比较耗性能，且perf自身造成的上下文切换会比较影响结果，上面几个指标一般都是基于`eBPF`采集。

之前 [eBPF学习实践系列](https://xiaodongq.github.io/2024/06/06/ebpf_learn) 中，学习实践了不少eBPF、ftrace相关的一些工具，这里再回顾一下。

1、基于eBPF的bcc工具集（/usr/share/bcc/tools/）：

![bcc tools 2019](/images/bcc-tools-2019.png)  
[出处](https://github.com/iovisor/bcc/blob/master/images/bcc_tracing_tools_2019.png)

为简化eBPF开发，发展出了bcc、bpftrace。为解决移植性问题，内核提供了BTF、`CO-RE`（Compile-Once Run-Everywhere）技术，封装在`libbpf`中。

上面这些工具之前都是基于python写的eBPF工具，作者考虑弃用转而使用新的`libbpf`接口进行实现，bcc仓库里的 [libbpf-tools](https://github.com/iovisor/bcc/tree/master/libbpf-tools) 已经有一部分工具了，可看到还在持续更新当中。

> Update 04-Nov-2020: The Python interface is now considered deprecated in favor of the new C libbpf interface  
> 详情可查看：[Linux Extended BPF (eBPF) Tracing Tools](https://www.brendangregg.com/ebpf.html)

2、基于`perf`和`ftrace`的 perf-tools 工具集

![perf-tools工具集](/images/perf-tools_2016.png)  
[出处](https://github.com/brendangregg/perf-tools/blob/master/images/perf-tools_2016.png)

其中的`funcgraph`很方便。结合`bpftrace`和`funcgraph`很适合跟踪前后调用栈：

* bpftrace 用来从上到下来跟踪到指定函数，即只能看到谁调用到指定追踪点
* funcgraph 用来从指定函数往下追踪调用栈

回顾之前追踪存储栈实践：[学习Linux存储IO栈（二） -- Linux内核存储栈流程和接口](https://xiaodongq.github.io/2024/08/13/linux-kernel-fs/)、[学习Linux存储IO栈（三） -- eBPF和ftrace跟踪IO写流程](https://xiaodongq.github.io/2024/08/15/linux-write-io-stack/)

如果机器上的内核没开启eBPF对应特性支持（比如未开启`CONFIG_BPF_SYSCALL`），那需要重新编译下内核。简要步骤：

* `make menuconfig`，搜索`CONFIG_BPF_SYSCALL`并设置`y`保存到`.config`
* `make -j8`，得到 bzImage，拷贝到`/boot/vmlinuzxxx`替换，或者grub里新增一个menuentry项

### 4.2. 采集实验



## 5. 小结

异步编程学习实践系列，demo实验，使用 gperftools 和 火焰图 进行性能分析。本篇先介绍工具。

## 6. 参考

* [gperftools](https://github.com/gperftools/gperftools)
* [FlameGraph GitHub](https://github.com/brendangregg/FlameGraph)
* [Flame Graphs](https://www.brendangregg.com/flamegraphs.html)
* [Linux Extended BPF (eBPF) Tracing Tools](https://www.brendangregg.com/ebpf.html)
* [BPF binaries: BTF, CO-RE, and the future of BPF perf tools](https://www.brendangregg.com/blog/2020-11-04/bpf-co-re-btf-libbpf.html)
