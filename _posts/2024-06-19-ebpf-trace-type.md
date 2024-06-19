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

此外还有不少其他类型，如：

* Socket Filter
    * 允许在网络层面对数据包进行过滤和分析。通过编写eBPF程序并附加到网络套接字上，可以实时捕获和分析网络流量，实现如流量分类、性能监控等任务
* Syscall Tracing
    * 追踪系统调用的执行情况

## eBPF程序类型

> eBPF 程序通常包含用户态和内核态两部分：用户态程序通过 BPF 系统调用，完成 eBPF 程序的加载、事件挂载以及映射创建和更新，而内核态中的 eBPF 程序则需要通过 BPF 辅助函数完成所需的任务。

并不是所有的辅助函数都可以在 eBPF 程序中随意使用，不同类型的 eBPF 程序所支持的辅助函数是不同的。

在libbpf的`include/uapi/linux/bpf.h`中，查看`bpf_prog_type`即可看到类型。

5.10.10内核（LIBBPF_0.2.0）中的类型定义如下，其中有30种，高版本可能更多。

```sh
# linux-5.10.10/tools/include/uapi/linux/bpf.h
enum bpf_prog_type {
	BPF_PROG_TYPE_UNSPEC,
	BPF_PROG_TYPE_SOCKET_FILTER,
	BPF_PROG_TYPE_KPROBE,
	BPF_PROG_TYPE_SCHED_CLS,
	BPF_PROG_TYPE_SCHED_ACT,
	BPF_PROG_TYPE_TRACEPOINT,
	BPF_PROG_TYPE_XDP,
	BPF_PROG_TYPE_PERF_EVENT,
	BPF_PROG_TYPE_CGROUP_SKB,
	BPF_PROG_TYPE_CGROUP_SOCK,
	BPF_PROG_TYPE_LWT_IN,
	BPF_PROG_TYPE_LWT_OUT,
	BPF_PROG_TYPE_LWT_XMIT,
	BPF_PROG_TYPE_SOCK_OPS,
	BPF_PROG_TYPE_SK_SKB,
	BPF_PROG_TYPE_CGROUP_DEVICE,
	BPF_PROG_TYPE_SK_MSG,
	BPF_PROG_TYPE_RAW_TRACEPOINT,
	BPF_PROG_TYPE_CGROUP_SOCK_ADDR,
	BPF_PROG_TYPE_LWT_SEG6LOCAL,
	BPF_PROG_TYPE_LIRC_MODE2,
	BPF_PROG_TYPE_SK_REUSEPORT,
	BPF_PROG_TYPE_FLOW_DISSECTOR,
	BPF_PROG_TYPE_CGROUP_SYSCTL,
	BPF_PROG_TYPE_RAW_TRACEPOINT_WRITABLE,
	BPF_PROG_TYPE_CGROUP_SOCKOPT,
	BPF_PROG_TYPE_TRACING,
	BPF_PROG_TYPE_STRUCT_OPS,
	BPF_PROG_TYPE_EXT,
	BPF_PROG_TYPE_LSM,
	BPF_PROG_TYPE_SK_LOOKUP,
};
```

因为不同内核的版本和编译配置选项不同，一个内核并不会支持所有的程序类型。查询当前系统支持的程序类型：`bpftool feature probe | grep program_type` 

## 3. 小结



## 4. 参考

1、[BPF 跟踪机制之原始跟踪点 rawtracepoint 介绍、使用和样例](https://www.ebpf.top/post/bpf_rawtracepoint/)

2、[06 | 事件触发：各类eBPF程序的触发机制及其应用场景](https://time.geekbang.org/column/article/483364)

2、[深入浅出 eBPF｜你要了解的 7 个核心问题](https://developer.aliyun.com/article/985159)

3、[一文带你深入探索 eBPF 可观测性技术底层奥秘](https://cloud.tencent.com/developer/article/2329533)


5、GPT
