---
layout: post
title: eBPF学习实践系列（三） -- libbpf学习实践
categories: eBPF
tags: eBPF libbpf CO-RE
---

* content
{:toc}

libbpf CO-RE学习实践



## 1. 背景

最近学习`libbpf-bootstrap`和`BCC` (其中的`bcc tools`/`libbpf-tools`)过程中，认识到libbpf的强大。移植性、环境依赖、大小、运行速度等方面，libbpf都有其优势之处。

而且不同eBPF框架开发时，很多语法糖有所差别，这也是最近自己比较困扰的一点，想找到一个通用的tracepoint/kprobe/uprobe/USDT列表，但是这些框架间差异造成了很多困惑。最近在一个环境A里从BCC项目(0.23.0版本)中的`libbpf-tools`移植了`tcpconnect`工具到`libbpf-bootstrap`，成功编译运行了；但是在另一个环境B里(0.19.0版本)，依赖的工具类文件比较多放弃移植测试了。

在了解框架的基础上想进一步摸清底层原理，那么“自底向上“式学习libbpf，是一个不错的选择。

Brendan Gregg大佬也提到libbpf的趋势

> 对于 BPF 性能工具，你应该从运行 BCC 和 bpftrace 工具开始，然后在 bpftrace 中进行编码。 BCC 工具最终应该在后台实现上从 Python 切换到 libbpf C，但是仍然可以正常使用。现在，随着我们转向带有 BTF 和 CO-RE 的libbpf C，已经不赞成使用 BCC Python 中的性能工具（尽管我们仍需要继续完善库的功能，例如对 USDT 的支持，因此需要一段时间才能使用 Python 版本）。 -- [BPF 二进制文件：BTF，CO-RE 和 BPF 性能工具的未来【译】](https://www.ebpf.top/post/bpf-co-re-btf-libbpf/)



## 4. 小结


## 5. 参考

1、[eBPF动手实践系列三：基于原生libbpf库的eBPF编程改进方案](https://mp.weixin.qq.com/s/R70hmc965cA8X3WUZRp2hQ)

2、[经典 libbpf 范例: uprobe 分析 - eBPF基础知识 Part4](https://mp.weixin.qq.com/s/pM0YXZLEsEhsExUxeiD7jQ)

3、[BPF 二进制文件：BTF，CO-RE 和 BPF 性能工具的未来【译】](https://www.ebpf.top/post/bpf-co-re-btf-libbpf/)

4、[BCC 到 libbpf 的转换指南【译】](https://www.ebpf.top/post/bcc-to-libbpf-guid/)

5、GPT
