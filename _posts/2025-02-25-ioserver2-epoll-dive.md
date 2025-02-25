---
layout: post
title: ioserver服务实验（二） -- 深入学习epoll原理
categories: 网络
tags: C++ 网络
---

* content
{:toc}

基于ioserver demo项目，梳理学习epoll原理。



## 1. 背景

基于C++实现的读写服务demo，借此作为场景温习并深入学习io多路复用、性能调试、MySQL/Redis等开源组件。

本篇梳理demo里面的几个io多路复用实现，并比较 [muduo](https://github.com/chenshuo/muduo) 中的实现进行学习。

参考：

* [深入揭秘 epoll 是如何实现 IO 多路复用的](https://mp.weixin.qq.com/s/OmRdUgO1guMX76EdZn11UQ)
* [muduo](https://github.com/chenshuo/muduo) 源码

## 2. 小结


## 3. 参考

* [深入揭秘 epoll 是如何实现 IO 多路复用的](https://mp.weixin.qq.com/s/OmRdUgO1guMX76EdZn11UQ)
* [muduo](https://github.com/chenshuo/muduo) 源码
