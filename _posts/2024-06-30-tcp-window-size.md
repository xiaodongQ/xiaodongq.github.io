---
layout: post
title: TCP发送接收窗口和Wireshark跟踪
categories: 网络
tags: TCP Wireshark 接收窗口
---

* content
{:toc}

TCP发送接收窗口相关学习实践和Wireshark跟踪



## 1. 背景

前段时间立了个flag，要按项目迭代的方式迭代自己。初步迭代任务是6月底完成之前的网络知识点TODO，已经月底了，常态性延期。

虽然没达到最终预期，但这种方式对提高效率确实管用，这几天是deadline，昨天**看**了好几篇之前放着没看的文章（初期计划是看+实验）。

最近学习时，很多文章来自下面几个大佬的博客：

* [开发内功修炼之网络篇](https://mp.weixin.qq.com/mp/appmsgalbum?__biz=MjM5Njg5NDgwNA==&action=getalbum&album_id=1532487451997454337#wechat_redirect)
* [kawabangga](https://www.kawabangga.com/posts/category/%e7%bd%91%e7%bb%9c)
* [plantegg](https://plantegg.github.io/categories/TCP/)

本来准备做一下Linux客户端和服务端最多支撑多少个TCP连接，以及对应的内存消耗的实验，转念一想自己做完只是印证下结论而已，优先级放低。

有一个点卡住自己很久了，有点难受，这次来啃一下：**TCP发送接收窗口、慢启动、拥塞控制等，并在Wireshark里跟踪。**

先收集几篇参考文章，下面进行进一步学习实践：

* [TCP 长连接 CWND reset 的问题分析](https://www.kawabangga.com/posts/5217)
* [TCP 拥塞控制对数据延迟的影响](https://www.kawabangga.com/posts/5181)
* [TCP性能和发送接收窗口、Buffer的关系](https://plantegg.github.io/2019/09/28/%E5%B0%B1%E6%98%AF%E8%A6%81%E4%BD%A0%E6%87%82TCP--%E6%80%A7%E8%83%BD%E5%92%8C%E5%8F%91%E9%80%81%E6%8E%A5%E6%94%B6Buffer%E7%9A%84%E5%85%B3%E7%B3%BB/)
* [TCP传输速度案例分析](https://plantegg.github.io/2021/01/15/TCP%E4%BC%A0%E8%BE%93%E9%80%9F%E5%BA%A6%E6%A1%88%E4%BE%8B%E5%88%86%E6%9E%90/)

## 小结


## 参考

