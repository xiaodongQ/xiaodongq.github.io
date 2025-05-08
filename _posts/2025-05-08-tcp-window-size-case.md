---
title: TCP发送接收过程（二） -- 实际案例看TCP性能和窗口、Buffer的关系
description: 通过实际案例看TCP性能和窗口、Buffer的关系，并用Wireshark跟踪TCP Stream Graphs。
categories: [网络, TCP]
tags: [TCP, Wireshark, 接收缓冲区]
---


## 1. 引言

[上一篇博客](https://xiaodongq.github.io/2024/06/30/tcp-wireshark-tcp-graphs/)中介绍了Wireshark里的TCP Stream Graghs可视化功能并查看了几种典型的图形，本篇进行实验观察TCP性能和窗口、Buffer的关系，并分析一些参考文章中的案例。

一些相关文章：

* 参考本篇进行实验：[TCP性能和发送接收窗口、Buffer的关系](https://plantegg.github.io/2019/09/28/%E5%B0%B1%E6%98%AF%E8%A6%81%E4%BD%A0%E6%87%82TCP--%E6%80%A7%E8%83%BD%E5%92%8C%E5%8F%91%E9%80%81%E6%8E%A5%E6%94%B6Buffer%E7%9A%84%E5%85%B3%E7%B3%BB/)
* [TCP传输速度案例分析](https://plantegg.github.io/2021/01/15/TCP%E4%BC%A0%E8%BE%93%E9%80%9F%E5%BA%A6%E6%A1%88%E4%BE%8B%E5%88%86%E6%9E%90/)
* [TCP 拥塞控制对数据延迟的影响](https://www.kawabangga.com/posts/5181)
* [TCP 长连接 CWND reset 的问题分析](https://www.kawabangga.com/posts/5217)

**202505更新**：之前一直占坑没进行实验，最近定位问题碰到UDP接收缓冲区满导致丢包的情况，补充本实验增强体感。

另外近段时间重新过了下之前看过的几篇网络相关文章，对知识树查漏补缺挺有帮助：

* [云网络丢包故障定位全景指南](https://www.modb.pro/db/199920)
    * 极客重生公众号作者，前面的博客中也有部分内容索引到作者的文章，干货挺多，后续梳理学习其他历史文章
* [[译] RFC 1180：朴素 TCP/IP 教程（1991）](https://arthurchiao.art/blog/rfc1180-a-tcp-ip-tutorial-zh/)
    * 自己之前也梳理画过图了：[RFC1180学习笔记](https://xiaodongq.github.io/2023/05/10/rfc1180-tcpip-tutorial/)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 实验说明



## 2. 小结

## 3. 参考

* [TCP性能和发送接收窗口、Buffer的关系](https://plantegg.github.io/2019/09/28/%E5%B0%B1%E6%98%AF%E8%A6%81%E4%BD%A0%E6%87%82TCP--%E6%80%A7%E8%83%BD%E5%92%8C%E5%8F%91%E9%80%81%E6%8E%A5%E6%94%B6Buffer%E7%9A%84%E5%85%B3%E7%B3%BB/)
* [TCP传输速度案例分析](https://plantegg.github.io/2021/01/15/TCP%E4%BC%A0%E8%BE%93%E9%80%9F%E5%BA%A6%E6%A1%88%E4%BE%8B%E5%88%86%E6%9E%90/)
* [TCP 拥塞控制对数据延迟的影响](https://www.kawabangga.com/posts/5181)
* [TCP 长连接 CWND reset 的问题分析](https://www.kawabangga.com/posts/5217)
* LLM
