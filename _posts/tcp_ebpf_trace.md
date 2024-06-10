<!-- ---
layout: post
title: TCP半连接队列系列（二） -- ebpf跟踪内核关键流程
categories: 网络
tags: 网络
---

* content
{:toc} -->

使用ebpf跟踪内核中网络的关键过程



## 1. 背景

在“[TCP全连接队列相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/)”这篇文章中，进行了全连接队列溢出的实验，并且遗留了几个问题。

1. ~~半连接队列溢出情况分析，服务端接收具体处理逻辑~~
2. ~~内核drop包的时机~~，以及跟抓包的关系。哪些情况可能会抓不到drop的包？
3. systemtap/ebpf跟踪TCP状态变化，跟踪上述drop事件
4. 上述全连接实验case1中，2MSL内没观察到客户端连接`FIN_WAIT2`状态，为什么？

本文使用ebpf工具进行跟踪分析。

## 2. ebpf跟踪脚本准备



## 3. 小结


## 4. 参考


