---
layout: post
title: eBPF学习实践系列（三） -- 基于libbpf开发实践
categories: eBPF
tags: eBPF libbpf CO-RE
---

* content
{:toc}

基于libbpf开发实践



## 1. 背景

最近初步学习了`libbpf-bootstrap`和`BCC` (其中的`bcc tools`/`libbpf-tools`)。并在一个环境A里从BCC项目(0.23.0版本)中的`libbpf-tools`移植了`tcpconnect`工具到`libbpf-bootstrap`，成功编译运行了；但是在另一个环境B里(0.19.0版本)，依赖的工具类文件比较多放弃移植测试了。

这里先跳出框架，基于libbpf学习实践，加深些理解，主要参考下面几篇文章。

[使用C语言从头开发一个Hello World级别的eBPF程序](https://tonybai.com/2022/07/05/develop-hello-world-ebpf-program-in-c-from-scratch/)

[eBPF动手实践系列三：基于原生libbpf库的eBPF编程改进方案](https://mp.weixin.qq.com/s/R70hmc965cA8X3WUZRp2hQ)里的demo学习。

## 2. 基于libbpf开发hello world级BPF程序



## 3. 小结


## 4. 参考

1、[eBPF动手实践系列三：基于原生libbpf库的eBPF编程改进方案](https://mp.weixin.qq.com/s/R70hmc965cA8X3WUZRp2hQ)

2、[使用C语言从头开发一个Hello World级别的eBPF程序](https://tonybai.com/2022/07/05/develop-hello-world-ebpf-program-in-c-from-scratch/)

3、[BPF 系统接口 与 libbpf 示例分析- eBPF基础知识 Part2](https://blog.mygraphql.com/zh/notes/bpf/libbpf/libbpf-bootstrap-study-1-minimal/)

4、[BPF 二进制文件：BTF，CO-RE 和 BPF 性能工具的未来【译】](https://www.ebpf.top/post/bpf-co-re-btf-libbpf/)

5、[BCC 到 libbpf 的转换指南【译】](https://www.ebpf.top/post/bcc-to-libbpf-guid/)

6、GPT
