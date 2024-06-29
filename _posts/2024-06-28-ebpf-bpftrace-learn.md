---
layout: post
title: eBPF学习实践系列（六） -- bpftrace学习和使用
categories: eBPF
tags: eBPF bpftrace
---

* content
{:toc}

bpftrace学习和使用



## 1. 背景

前面学习bcc和libbpf时，提到Brendan Gregg等大佬们编写的工具集（几个示意图可参考：[eBPF学习实践系列（一） -- 初识eBPF](https://xiaodongq.github.io/2024/06/06/ebpf_learn/) ），这些工具已经能提供很丰富的功能了。

但是想自己跟踪一些想要的个性化信息时，需要基于Python或者C/C++写逻辑，写完后有时还要调试各类编译问题，于是学习下`bpftrace`的使用，实践中更容易上手。

小结下近期的eBPF学习历程：  
![eBPF学习历程](/images/2024-06-28-ebpf-learn-record.png)

## 2. bpftrace说明

bpftrace是一种针对较近期的Linux内核（4.x系列起）中eBPF的高级跟踪语言。bpftrace利用`LLVM`作为后端，将脚本编译为BPF字节码，并借助`BCC`与Linux BPF系统进行交互，同时也利用了Linux现有的跟踪功能，包括内核动态跟踪（`kprobes`）、用户级动态跟踪（`uprobes`）及`tracepoint`。

bpftrace语言受到了awk、C语言以及先驱跟踪工具如`DTrace`和`SystemTap`的启发，并由[Alastair Robertson](https://github.com/ajor)创建。

项目主页：[bpftrace](https://github.com/bpftrace/bpftrace)

bpftrace内部结构示意图：  
![bpftrace内部结构](/images/bpftrace_internals_2018.png)

bpftrace提供的追踪类型：  
![bpftrace提供的追踪类型](/images/bpftrace_probes_2018.png)

## 3. 基本用法

查看github上bpftrace项目的一行使用教程：[tutorial_one_liners](https://github.com/bpftrace/bpftrace/blob/master/docs/tutorial_one_liners.md)，里面提供了12个简单的使用说明。 (也可以看这篇译文：[bpftrace一行教程](https://eunomia.dev/zh/tutorials/bpftrace-tutorial/))

记录下自己运行环境的bcc和bpftrace、llvm版本（有的环境发现有问题）

```sh
# 使用正常
[root@xdlinux ➜ ~ ]$ rpm -qa|grep bpftr
bpftrace-0.12.1-3.el8.x86_64
[root@xdlinux ➜ ~ ]$ rpm -qa|grep bcc
bcc-0.19.0-4.el8.x86_64
bcc-tools-0.19.0-4.el8.x86_64
python3-bcc-0.19.0-4.el8.x86_64
[root@xdlinux ➜ ~ ]$ rpm -qa|grep llvm
llvm-libs-12.0.1-2.module_el8.5.0+918+ed335b90.x86_64
llvm-12.0.1-2.module_el8.5.0+918+ed335b90.x86_64
```

前面eBPF学习基础后，理解和使用bpftrace就比较丝滑了，很多直接可用的轮子。

### 3.1. 列出所有探针

## 4. 小结


## 5. 参考

1、[bpftrace](https://github.com/bpftrace/bpftrace)

2、[tutorial_one_liners](https://github.com/bpftrace/bpftrace/blob/master/docs/tutorial_one_liners.md)

3、[bpftrace一行教程](https://eunomia.dev/zh/tutorials/bpftrace-tutorial/)

4、GPT
