---
layout: post
title: 深入学习netfilter和iptables
categories: 网络
tags: TCP netfilter iptables
---

* content
{:toc}

深入学习netfilter和iptables



## 1. 背景

在[追踪内核网络堆栈的几种方式](https://xiaodongq.github.io/2024/07/03/strace-kernel-network-stack)里记录了一下iptables设置日志跟踪的实践过程，CentOS8下为什么实验失败还没有定论。

平常工作中设置iptables防火墙规则，基本只是浮于表面记住，不清楚为什么这么设置，规则也经常混淆。

[TCP半连接全连接（一） -- 全连接队列相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/)里面的TODO项：“内核drop包的时机，以及跟抓包的关系。哪些情况可能会抓不到drop的包？”，在系列文章里分析了源码里全连接、半连接溢出时drop的位置，给了个tcpdump能抓到drop原始请求包的现象结论，但没有理清楚流程。

这些问题都或多或少，或直接或间接跟**内核中的netfilter框架**有关系。

基于上述几个原因，深入学习一下`netfilter`框架和基于其实现的`iptables`，以及tcpdump抓包跟`netfilter`的关系。

主要参考学习以下文章：

* [[译] 深入理解 iptables 和 netfilter 架构](https://arthurchiao.art/blog/deep-dive-into-iptables-and-netfilter-arch-zh)
* [用户态 tcpdump 如何实现抓到内核网络包的?](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247486315&idx=1&sn=ce3a85a531447873e02ccef17198e8fe&chksm=a6e30a509194834693bb7ee50cdd3868ab1f686a3a0807e2d1a514253ba1579d1246b99bf35d&scene=178&cur_album_id=1532487451997454337#rd)
* [来，今天飞哥带你理解 iptables 原理！](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247487465&idx=1&sn=aace79dcb4edb011cf69e7cd9f7331f9&chksm=a6e30ed2919487c402f20fdda822bc63f057a334e81e8d26e48194f5b679882c627311205bbe&scene=178&cur_album_id=1532487451997454337#rd)
* [iptable 的基石：netfilter 原理与实战](https://juejin.cn/book/6844733794801418253/section/7355436057355583528)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. netfilter介绍



## 小结


## 参考

1、[[译] 深入理解 iptables 和 netfilter 架构](https://arthurchiao.art/blog/deep-dive-into-iptables-and-netfilter-arch-zh)

2、[用户态 tcpdump 如何实现抓到内核网络包的?](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247486315&idx=1&sn=ce3a85a531447873e02ccef17198e8fe&chksm=a6e30a509194834693bb7ee50cdd3868ab1f686a3a0807e2d1a514253ba1579d1246b99bf35d&scene=178&cur_album_id=1532487451997454337#rd)

3、[来，今天飞哥带你理解 iptables 原理！](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247487465&idx=1&sn=aace79dcb4edb011cf69e7cd9f7331f9&chksm=a6e30ed2919487c402f20fdda822bc63f057a334e81e8d26e48194f5b679882c627311205bbe&scene=178&cur_album_id=1532487451997454337#rd)

4、[iptable 的基石：netfilter 原理与实战](https://juejin.cn/book/6844733794801418253/section/7355436057355583528)

5、GPT
