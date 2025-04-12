---
layout: _post
title: TCP发送接收过程（二） -- 实际案例看TCP性能和窗口、Buffer的关系
categories: 网络
tags: TCP Wireshark 接收缓冲区
---

* content
{:toc}

通过实际案例看TCP性能和窗口、Buffer的关系，并用Wireshark跟踪TCP Stream Graphs



## 1. 背景

[上一篇博客](https://xiaodongq.github.io/2024/06/30/tcp-wireshark-tcp-graphs/)中介绍了Wireshark里的TCP Stream Graghs可视化功能并查看了几种典型的图形，本篇中学习实际案例场景中，TCP性能和窗口、Buffer的关系，并用上节介绍的工具进行跟踪分析。

注意，此处说的实际案例场景不是自己进行实验，而是学习分析该文章的案例：[TCP性能和发送接收窗口、Buffer的关系](https://plantegg.github.io/2019/09/28/%E5%B0%B1%E6%98%AF%E8%A6%81%E4%BD%A0%E6%87%82TCP--%E6%80%A7%E8%83%BD%E5%92%8C%E5%8F%91%E9%80%81%E6%8E%A5%E6%94%B6Buffer%E7%9A%84%E5%85%B3%E7%B3%BB/)，后续篇幅再自行实验对比。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*



## 5. 小结



## 6. 参考

1、[TCP性能和发送接收窗口、Buffer的关系](https://plantegg.github.io/2019/09/28/%E5%B0%B1%E6%98%AF%E8%A6%81%E4%BD%A0%E6%87%82TCP--%E6%80%A7%E8%83%BD%E5%92%8C%E5%8F%91%E9%80%81%E6%8E%A5%E6%94%B6Buffer%E7%9A%84%E5%85%B3%E7%B3%BB/)

2、[TCP传输速度案例分析](https://plantegg.github.io/2021/01/15/TCP%E4%BC%A0%E8%BE%93%E9%80%9F%E5%BA%A6%E6%A1%88%E4%BE%8B%E5%88%86%E6%9E%90/)

3、[TCP 拥塞控制对数据延迟的影响](https://www.kawabangga.com/posts/5181)

4、[TCP 长连接 CWND reset 的问题分析](https://www.kawabangga.com/posts/5217)

5、GPT
