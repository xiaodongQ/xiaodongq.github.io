---
layout: post
title: TCP半连接全连接（三） -- eBPF跟踪全连接队列溢出
categories: 网络
tags: 网络
---

* content
{:toc}

通过eBPF跟踪TCP全连接队列溢出现象并进行分析。



## 1. 背景

在“[TCP半连接全连接（一） -- 全连接队列相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/)”这篇文章中，进行了全连接队列溢出的实验，并且遗留了几个问题。

1. 半连接队列溢出情况分析，服务端接收具体处理逻辑
2. 内核drop包的时机，以及跟抓包的关系。哪些情况可能会抓不到drop的包？
3. systemtap/ebpf跟踪TCP状态变化，跟踪上述drop事件
4. 上述全连接实验case1中，2MSL内没观察到客户端连接`FIN_WAIT2`状态，为什么？

[TCP半连接全连接（二） -- 半连接队列代码逻辑](https://xiaodongq.github.io/2024/05/30/tcp_syn_queue/) 中基本梳理涉及到问题1、2。

本篇通过eBPF跟踪TCP状态变化和溢出情况，经过"eBPF学习实践系列"，终于可以投入实际验证了。

## 2. 环境准备

1、仍使用第一篇中的客户端、服务端程序，代码和编译脚步归档在 [github处](https://github.com/xiaodongQ/prog-playground/tree/main/network/tcp_connect)

2、起2个阿里云抢占式ECS：Alibaba Cloud Linux 3.2104 LTS 64位（内核版本：5.10.134-16.1.al8.x86_64）

安装好bcc：

* `yum install bcc clang`

下载libbpf-bootstrap并安装其编译依赖：

* `git clone https://github.com/libbpf/libbpf-bootstrap.git`、`git submodule update --init --recursive`
* `yum install zlib-devel elfutils-libelf-devel`

3、基于5.10内核代码跟踪流程

## 3. bcc tools 跟踪



## 4. libbpf跟踪

## 5. 小结


## 6. 参考


