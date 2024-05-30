---
layout: post
title: TCP半连接队列溢出实验及分析
categories: 网络
tags: 网络
---

* content
{:toc}

半连接队列溢出分析及实验，并用工具跟踪



## 1. 背景

[TCP建立连接相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/)中，进行了全连接队列溢出的实验，并且遗留了几个问题。

本博客实验分析半连接队列溢出情况，并探究上述文章中的遗留问题。

1. 半连接队列溢出情况分析，服务端接收具体处理逻辑
2. 内核drop包的时机，以及跟抓包的关系。哪些情况可能会抓不到drop的包？
3. systemtap/ebpf跟踪TCP状态变化，跟踪上述drop事件
4. 上述全连接实验case1中，2MSL内没观察到客户端连接`FIN_WAIT2`状态，为什么？

## 2. 前置说明

主要基于这篇文章："[从一次线上问题说起，详解 TCP 半连接队列、全连接队列](https://mp.weixin.qq.com/s/YpSlU1yaowTs-pF6R43hMw?poc_token=HKCgSGaji2dgAtvVc7gzTQykh3Aw6neDWcojHyB8)"，进行学习和扩展。

环境：起两个阿里云抢占式实例，Alibaba Cloud Linux 3.2104 LTS 64位（内核版本：5.10.134-16.1.al8.x86_64）

基于5.10内核代码跟踪流程

## 分析半连接

上篇文章中自己的实验没抓到`SYN`发出后继续重发的情况，先跟着参考文章分析TCP半连接队列流程，再进行实验复现。

## 小结

## 参考

1、[从一次线上问题说起，详解 TCP 半连接队列、全连接队列](https://mp.weixin.qq.com/s/YpSlU1yaowTs-pF6R43hMw?poc_token=HKCgSGaji2dgAtvVc7gzTQykh3Aw6neDWcojHyB8)

