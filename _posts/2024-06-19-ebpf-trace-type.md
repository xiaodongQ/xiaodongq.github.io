---
layout: post
title: eBPF学习实践系列（四） -- eBPF追踪机制实践
categories: eBPF
tags: eBPF libbpf
---

* content
{:toc}

eBPF追踪机制实践



## 1. 背景

前面涉及了helloworld级别程序的开发流程，本文梳理学习具体追踪机制及使用方式。

先通过BCC和libbpf-bootstrap中的示例学习。

几种追踪机制：

* Tracepoints（Kernel Tracepoints），内核预定义跟踪点，跟踪特定事件或操作，是静态定义的
* Kprobes（Kernel Probes），内核探针，运行时动态挂接到内核代码
* Uprobes（User Probes），用户探针，运行时动态挂接到用户空间应用程序
* USDT（User Statically Defined Tracing），用户预定义跟踪点

此外还有：

* Socket Filter
    * 允许在网络层面对数据包进行过滤和分析。通过编写eBPF程序并附加到网络套接字上，可以实时捕获和分析网络流量，实现如流量分类、性能监控等任务
* Syscall Tracing
    * 追踪系统调用的执行情况

## 2. libbpf-bootstrap示例的追踪

## 3. 小结



## 4. 参考

1、[06 | 事件触发：各类eBPF程序的触发机制及其应用场景](https://time.geekbang.org/column/article/483364)

2、[深入浅出 eBPF｜你要了解的 7 个核心问题](https://developer.aliyun.com/article/985159)

3、[一文带你深入探索 eBPF 可观测性技术底层奥秘](https://cloud.tencent.com/developer/article/2329533)

4、[BPF 跟踪机制之原始跟踪点 rawtracepoint 介绍、使用和样例](https://www.ebpf.top/post/bpf_rawtracepoint/)

5、GPT
