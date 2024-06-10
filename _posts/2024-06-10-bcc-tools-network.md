---
layout: post
title: eBPF学习实践系列（二） -- bcc tools网络工具集
categories: eBPF
tags: Linux eBPF
---

* content
{:toc}

bcc tools工具集中网络部分说明和使用。



## 1. 背景

上篇([eBPF学习实践系列（一） -- 第一课](https://xiaodongq.github.io/2024/06/06/ebpf_learn/#22-ebpf%E5%86%85%E6%A0%B8%E7%89%88%E6%9C%AC%E6%94%AF%E6%8C%81%E8%AF%B4%E6%98%8E))中提到性能分析大师`Brendan Gregg`等编写了**诸多的 BCC 或 BPFTrace 的工具集**可以拿来直接使用，可以满足很多我们日常问题分析和排查，先学习下网络相关的几个工具。

![bcc tools 2019](/images/bcc-tools-2019.png)  

## Linux性能分析60s

### 60s系列系统命令版本

```sh
uptime
dmesg | tail
vmstat 1
mpstat -P ALL 1
pidstat 1
iostat -xz 1
free -m
sar -n DEV 1
sar -n TCP,ETCP 1
top
```

### 60s系列BPF版本

![bcc tools 60s](/images/ebpf_60s-bcctools2017.png)  
[参考](https://www.ebpf.top/post/ebpf_intro/)

## 4. 小结

1、[【BPF入门系列-1】eBPF 技术简介](https://www.ebpf.top/post/ebpf_intro/)


## 5. 参考


