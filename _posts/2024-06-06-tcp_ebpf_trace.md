---
layout: post
title: TCP半连接队列系列（二） -- ebpf跟踪内核关键流程
categories: 网络
tags: 网络
---

* content
{:toc}

学习ebpf，并使用ebpf跟踪内核中网络的关键过程



## 1. 背景

在“[TCP建立连接相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/)”这篇文章中，进行了全连接队列溢出的实验，并且遗留了几个问题。

1. ~~半连接队列溢出情况分析，服务端接收具体处理逻辑~~
2. ~~内核drop包的时机~~，以及跟抓包的关系。哪些情况可能会抓不到drop的包？
3. systemtap/ebpf跟踪TCP状态变化，跟踪上述drop事件
4. 上述全连接实验case1中，2MSL内没观察到客户端连接`FIN_WAIT2`状态，为什么？

本文学习并使用ebpf工具进行跟踪分析。

## 2. eBPF基本介绍

eBPF（Extended Berkeley Packet Filter）是一个在Linux内核中实现的强大工具，允许用户空间程序通过加载BPF（Berkeley Packet Filter）字节码到内核，安全地执行各种网络、追踪和安全相关的任务。

### 2.1. eBPF 提供了四种不同的操作机制

1. **内核跟踪点(Kernel Tracepoints)**：内核跟踪点是由内核开发人员预定义的事件，可以使用 `TRACE_EVENT` 宏在内核代码中设置。这些跟踪点允许 eBPF 程序挂接到特定的内核事件，并捕获相关数据进行分析和监控。
2. **USDT（User Statically Defined Tracing）**：USDT 是一种机制，允许开发人员在应用程序代码中设置预定义的跟踪点。通过在代码中插入特定的标记，eBPF 程序可以挂接到这些跟踪点，并捕获与应用程序相关的数据，以实现更细粒度的观测和分析。
3. **Kprobes（Kernel Probes）**：Kprobes 是一种内核探针机制，允许 eBPF 程序在**运行时动态挂接**到内核代码的任何部分。通过在目标内核函数的入口或出口处插入探针，eBPF 程序可以捕获函数调用和返回的参数、返回值等信息，从而实现对内核行为的监控和分析。
4. **Uprobes（User Probes）**：Uprobes 是一种用户探针机制，允许 eBPF 程序在运行时动态挂接到用户空间应用程序的任何部分。通过在目标用户空间函数的入口或出口处插入探针，eBPF 程序可以捕获函数调用和返回的参数、返回值等信息，以实现对应用程序的可观察性和调试能力。

> 由于 eBPF 还在快速发展期，内核中的功能也日趋增强，一般推荐基于`Linux 4.4+ (4.9 以上会更好)`内核的来使用 eBPF。

**部分 Linux Event 和 BPF 版本支持见下图：**

![linux_kernel_event_bpf](/images/linux_kernel_event_bpf.png)  
[出处](https://www.ebpf.top/post/ebpf_intro/)

性能分析大师 Brendan Gregg 等编写了**诸多的 BCC 或 BPFTrace 的工具集**可以拿来直接使用，可以满足很多我们日常问题分析和排查。

CentOS安装：`yum install bcc`，而后在`/usr/share/bcc/tools/`可查看。工具集示意图如下：

![bcc tools 60s](/images/ebpf_60s.png)  
[出处](https://www.ebpf.top/post/ebpf_intro/)

起一个ECS实例，安装bcc，可看到bcc-tools等依赖及大小(单独安装bcc-tools大概也要300多M)，安装后可看到上述工具(里面内容为python)

![安装bcc](/images/2024-06-07-yum_install_bcc.png)

### 2.2. BPF程序的开发方式

参考：[使用C语言从头开发一个Hello World级别的eBPF程序](https://tonybai.com/2022/07/05/develop-hello-world-ebpf-program-in-c-from-scratch/)

(后续如无特别指出，BPF指的就是新一代的eBPF技术)

BPF演进了这么多年，虽然一直在努力提高，但BPF程序的开发与构建体验依然不够理想。为此社区也创建了像`BPF Compiler Collection(BCC)`这样的用于简化BPF开发的框架和库集合，以及像`bpftrace`这样的提供高级BPF开发语言的项目(可以理解是开发BPF的`DSL`语言，Domain Specific Language)。

很多时候我们无需自己开发BPF程序，像`bcc`和`bpftrace`这样的开源项目给我们提供了很多高质量的BPF程序。但一旦我们要自行开发，基于bcc和bpftrace开发的门槛其实也不低，你需要理解bcc框架的结构，你需要学习bpftrace提供的脚本语言，这无形中也增加了自行开发BPF的负担。

**BPF的移植性问题：**

* Linux不同版本内核的数据结构字段可能不同，对于不需要查看这些信息的BPF程序可能不存在问题，但是需要的BPF程序则会存在移植性问题，需要考虑不同内核版本内部数据结构变化的影响
* 最初解决方式是在要运行的目标机器上编译BPF程序，以保证BPF访问的内核类型布局和目标主机内核一致。但这样每次需要在目标机器安装BPF依赖的开发包、编译器，显然比较麻烦。
* 为了解决BPF可移植性问题，内核引入了`BTF`（BPF Type Format）和`CO-RE`（Compile Once - Run Everywhere）两种新技术。
    * `BTF`提供结构信息以避免对`Clang`和内核头文件的依赖。
    * `CO-RE`使得编译出的BPF字节码是可重定位(relocatable)的，避免了LLVM重新编译的需要。
    * 使用这些新技术构建的BPF程序可以在不同linux内核版本中正常工作，无需为目标机器上的特定内核而重新编译它。目标机器上也无需再像之前那样安装数百兆的LLVM、Clang和kernel头文件依赖了。
* 这些新技术(`BTF`、`CO-RE`)对于BPF程序自身是透明的，Linux内核源码提供的`libbpf`用户API将上述新技术都封装了起来，只要用户态加载程序基于libbpf开发，那么libbpf就会悄悄地帮助BPF程序在目标主机内核中重新定位到其所需要的内核结构的相应字段，这让libbpf成为开发BPF加载程序的首选。
* `libbpf`究竟是什么？其实`libbpf`是指linux内核代码库中的`tools/lib/bpf`，这是内核提供给外部开发者的C库，用于创建BPF用户态的程序。

在开发eBPF程序时，有多种开发框架可供选择，如 `bcc（BPF Compiler Collection）libbpf`、`cilium/ebpf`、`eunomia-bpf` 等。虽然不同工具的特点各异，但它们的基本开发流程大致相同。

1. `libbpf-bootstrap`
    * 内核BPF开发者Andrii Nakryiko在github上开源了一个直接基于`libbpf`开发BPF程序与加载器的引导项目[libbpf-bootstrap](https://github.com/libbpf/libbpf-bootstrap)。这个项目中包含使用c和rust开发BPF程序和用户态程序的例子。
    * > "这也是我目前看到的体验最好的基于C语言的BPF程序和加载器的开发方式。"
2. `eunomia-bpf` 是一个开源的 eBPF 动态加载运行时和开发工具链，它的目的是简化 eBPF 程序的开发、构建、分发、运行。
    * 它基于 `libbpf` 的 `CO-RE`(Compile Once – Run Everywhere) 轻量级开发框架，支持通过用户态 WASM 虚拟机控制 eBPF 程序的加载和执行，并将预编译的 eBPF 程序打包为通用的 JSON 或 WASM 模块进行分发。
    * 网站：[eunomia-bpf 用户手册: 让 eBPF 程序的开发和部署尽可能简单](https://eunomia.dev/zh/eunomia-bpf/manual/)
3. 下面是一个关于`ebpf`不错的教程
    * 系列教程链接：[eBPF 开发实践教程：基于 CO-RE，通过小工具快速上手 eBPF 开发](https://eunomia.dev/zh/tutorials/)
    * 提供了从入门到进阶的 eBPF 开发实践，包括基本概念、代码实例、实际应用等内容。和 BCC 不同的是，我们使用 `libbpf`、`Cilium`、`libbpf-rs`、`eunomia-bpf` 等框架进行开发，包含 C、Go、Rust 等语言的示例。
    * 其中的学习建议：[关于如何学习 eBPF 相关的开发的一些建议](https://eunomia.dev/zh/tutorials/0-introduce/#2-ebpf)
    * 里面也有：`bcc` 和 `bpftrace`相关简单教程

通过上面的梳理，我们可以知道`bcc`和`bcc libbpf`是不同的，内核提供了`BTF`、`CO-RE`技术，封装在`libbpf`中，而在这之上又有多种基于`libbpf`框架可选择。

下面基于 `libbpf-bootstrap` 学习梳理，并进行实验。

## 3. 基于libbpf-bootstrap基本开发示例

一个以开发BPF程序为目的的工程通常由**两类**源文件组成

1. 一类是运行于内核态的BPF程序的源代码文件
2. 另外一类则是用于向内核加载BPF程序、从内核卸载BPF程序、与内核态进行数据交互、展现用户态程序逻辑的用户态程序的源代码文件

目前运行于内核态的BPF程序只能用C语言开发(对应于第一类源代码文件)，更准确地说只能用受限制的C语法进行开发，**并且可以完善地将C源码编译成BPF目标文件的只有clang编译器**(clang是一个C、C++、Objective-C等编程语言的编译器前端，采用LLVM作为后端)。

### 安装依赖

安装`clang` (上面安装bcc只是有clang的lib库)

```sh
[root@iZ2zeh7m46vtyf29xmdw90Z tools]# clang -v
clang version 15.0.7 ( 15.0.7-1.0.3.al8)
Target: x86_64-koji-linux-gnu
Thread model: posix
```

### 下载libbpf-bootstrap

临时开的ECS里连不上github，下面操作在本地搞完打包传ECS了。

1、下载 libbpf-bootstrap

`git clone https://github.com/libbpf/libbpf-bootstrap.git`

2、初始化和更新libbpf-bootstrap的依赖

libbpf-bootstrap将其依赖的libbpf、bpftool以git submodule的形式配置到其项目中，可查看`.gitmodules`

`git submodule update --init --recursive`

### hello world级BPF程序

到 `libbpf-bootstrap/examples/c` 下创建文件

1、helloworld.bpf.c

```c
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>

SEC("tracepoint/syscalls/sys_enter_execve")

int bpf_prog(void *ctx) {
  char msg[] = "Hello, World!";
  bpf_printk("invoke bpf_prog: %s\n", msg);
  return 0;
}

char LICENSE[] SEC("license") = "Dual BSD/GPL";
```

2、helloworld.c

```c
#include <stdio.h>
#include <unistd.h>
#include <sys/resource.h>
#include <bpf/libbpf.h>
#include "helloworld.skel.h"

static int libbpf_print_fn(enum libbpf_print_level level, const char *format, va_list args)
{
    return vfprintf(stderr, format, args);
}

int main(int argc, char **argv)
{
    struct helloworld_bpf *skel;
    int err;

    libbpf_set_strict_mode(LIBBPF_STRICT_ALL);
    /* Set up libbpf errors and debug info callback */
    libbpf_set_print(libbpf_print_fn);

    /* Open BPF application */
    skel = helloworld_bpf__open();
    if (!skel) {
        fprintf(stderr, "Failed to open BPF skeleton\n");
        return 1;
    }   

    /* Load & verify BPF programs */
    err = helloworld_bpf__load(skel);
    if (err) {
        fprintf(stderr, "Failed to load and verify BPF skeleton\n");
        goto cleanup;
    }

    /* Attach tracepoint handler */
    err = helloworld_bpf__attach(skel);
    if (err) {
        fprintf(stderr, "Failed to attach BPF skeleton\n");
        goto cleanup;
    }

    printf("Successfully started! Please run `sudo cat /sys/kernel/debug/tracing/trace_pipe` "
           "to see output of the BPF programs.\n");

    for (;;) {
        /* trigger our BPF program */
        fprintf(stderr, ".");
        sleep(1);
    }

cleanup:
    helloworld_bpf__destroy(skel);
    return -err;
}
```

3、libbpf_bootstrap/examples/c/Makefile里的`APPS`，加个helloworld

```sh
APPS = helloworld minimal minimal_legacy bootstrap uprobe kprobe fentry
```

4、编译：`make`

```sh
In file included from bpf.c:37:
libbpf_internal.h:19:10: fatal error: libelf.h: No such file or directory
   19 | #include <libelf.h>
      |          ^~~~~~~~~~
compilation terminated.
make[1]: *** [Makefile:134: /home/xd/libbpf-bootstrap/examples/c/.output//libbpf/staticobjs/bpf.o] Error 1
make: *** [Makefile:87: /home/xd/libbpf-bootstrap/examples/c/.output/libbpf.a] Error 2
```


## 4. 小结


## 5. 参考

1、[使用C语言从头开发一个Hello World级别的eBPF程序](https://tonybai.com/2022/07/05/develop-hello-world-ebpf-program-in-c-from-scratch/)

2、[【BPF入门系列-1】eBPF 技术简介](https://www.ebpf.top/post/ebpf_intro/)

3、[eBPF 入门开发实践教程一：Hello World，基本框架和开发流程](https://cloud.tencent.com/developer/article/2312629)

4、GPT
