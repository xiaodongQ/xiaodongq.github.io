---
layout: post
title: TCP半连接队列系列（二） -- ebpf跟踪内核关键流程
categories: 网络
tags: 网络
---

* content
{:toc}

使用ebpf跟踪内核中网络的关键过程



## 1. 背景

在“[TCP建立连接相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/)”这篇文章中，进行了全连接队列溢出的实验，并且遗留了几个问题。

1. ~~半连接队列溢出情况分析，服务端接收具体处理逻辑~~
2. ~~内核drop包的时机~~，以及跟抓包的关系。哪些情况可能会抓不到drop的包？
3. systemtap/ebpf跟踪TCP状态变化，跟踪上述drop事件
4. 上述全连接实验case1中，2MSL内没观察到客户端连接`FIN_WAIT2`状态，为什么？

本文学习并使用ebpf工具进行跟踪分析。

## 基本介绍

eBPF（Extended Berkeley Packet Filter）是一个在Linux内核中实现的强大工具，允许用户空间程序通过加载BPF（Berkeley Packet Filter）字节码到内核，安全地执行各种网络、追踪和安全相关的任务。当使用eBPF跟踪socket交互过程时，主要关注的是网络流量和socket层面的行为。以下是eBPF跟踪socket交互过程的一些关键点和步骤：

1. **eBPF的基本概念**：
   - eBPF是Linux内核中的一个虚拟机（VM-like）组件，能够在许多内核hook点安全地执行字节码。
   - eBPF技术的前身是BPF（Berkeley Packet Filter），但在Linux内核中进行了扩展，增加了更多的功能和应用场景。

2. **eBPF在socket交互中的作用**：
   - eBPF可以用于socket层面的数据捕获和分析，无需修改应用程序代码或插入埋点。
   - 通过socket filter或syscall追踪，eBPF可以帮助开发者在不同的内核层次追踪HTTP等网络请求数据。

3. **跟踪socket交互的步骤**：
   - **定义eBPF程序**：首先，需要定义一个eBPF程序，该程序将用于捕获和分析socket层面的数据。这通常涉及到编写BPF字节码，这些字节码将在内核中执行。
   - **加载eBPF程序到内核**：使用用户空间工具（如bcc、libbpf等）将eBPF程序加载到Linux内核中。
   - **挂接eBPF hook**：在socket系统调用上挂接eBPF hook，以便在socket创建、连接、读写等操作时执行eBPF程序。
   - **捕获和分析数据**：当socket交互发生时，eBPF程序将被触发并执行。程序可以捕获socket层面的数据（如源IP、目的IP、端口号、数据包内容等），并进行必要的分析。
   - **输出结果**：eBPF程序可以将捕获和分析的数据输出到用户空间，以便进一步处理或展示。

4. **优化和注意事项**：
   - 在使用eBPF跟踪socket交互时，需要注意性能开销。虽然eBPF提供了强大的功能，但在高负载场景下可能会对系统性能产生影响。
   - 为了减少性能开销，可以选择性地捕获和分析socket数据，避免不必要的处理。
   - 另外，eBPF程序的编写需要一定的专业知识和经验。建议参考相关文档和教程，以获取更多关于eBPF编程的信息。

5. **eBPF在云原生网络实践中的应用**：
   - 在云原生环境中，eBPF被广泛应用于网络性能优化、安全监控等方面。例如，在Kubernetes中，可以使用eBPF来优化service网络的转发性能，提升整体网络性能。

前期准备，先找几篇参考文章：

1、[eBPF 入门开发实践教程一：Hello World，基本框架和开发流程](https://cloud.tencent.com/developer/article/2312629)

2、[使用C语言从头开发一个Hello World级别的eBPF程序](https://tonybai.com/2022/07/05/develop-hello-world-ebpf-program-in-c-from-scratch/)

3、[ebpf & bcc 中文教程及手册](https://blog.cyru1s.com/posts/ebpf-bcc.html)

## 小结


## 参考

1、[eBPF 入门开发实践教程一：Hello World，基本框架和开发流程](https://cloud.tencent.com/developer/article/2312629)

2、[使用C语言从头开发一个Hello World级别的eBPF程序](https://tonybai.com/2022/07/05/develop-hello-world-ebpf-program-in-c-from-scratch/)

3、[ebpf & bcc 中文教程及手册](https://blog.cyru1s.com/posts/ebpf-bcc.html)

4、GPT
