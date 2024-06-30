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

* [用 Wireshark 分析 TCP 吞吐瓶颈](https://www.kawabangga.com/posts/4794)
* [TCP性能和发送接收窗口、Buffer的关系](https://plantegg.github.io/2019/09/28/%E5%B0%B1%E6%98%AF%E8%A6%81%E4%BD%A0%E6%87%82TCP--%E6%80%A7%E8%83%BD%E5%92%8C%E5%8F%91%E9%80%81%E6%8E%A5%E6%94%B6Buffer%E7%9A%84%E5%85%B3%E7%B3%BB/)
* [TCP传输速度案例分析](https://plantegg.github.io/2021/01/15/TCP%E4%BC%A0%E8%BE%93%E9%80%9F%E5%BA%A6%E6%A1%88%E4%BE%8B%E5%88%86%E6%9E%90/)

## 2. 前置说明

这个方面扩展开来涉及很多点。针对TCP发送、接收数据相关过程，可以先去分析学习内核源码，也可以先观察现象再去跟踪代码印证，这里先看现象。

先简单介绍说明下Linux网络栈的发送、接收数据的过程。（检索过程发现很多高质量博文，见参考小节）

### 2.1. Linux网络栈接收数据简要说明

![Linux网络栈接收数据](/images/2024-06-30-kernel-network-recv.png)  
出处：[图解Linux网络包接收过程](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247484058&idx=1&sn=a2621bc27c74b313528eefbc81ee8c0f&chksm=a6e303a191948ab7d06e574661a905ddb1fae4a5d9eb1d2be9f1c44491c19a82d95957a0ffb6&scene=21#wechat_redirect)

上述流程：

1. 数据到网卡
2. 网卡DMA(Direct Memory Access)数据到内存(Ring Buffer)
3. 网卡发起硬中断通知CPU
4. CPU发起软中断
5. ksoftirqd线程处理软中断，从Ring Buffer收包 （网卡的接收队列）
6. 帧数据保存为一个`skb`
7. 网络协议层处理，处理后数据放到`socket的接收队列` （socket的接收队列）
8. 内核唤醒用户进程

### 2.2. Linux网络栈发送数据简要说明

![Linux网络栈发送数据](/images/2024-06-30-kernel-network-send.png)  
出处：[25 张图，一万字，拆解 Linux 网络包发送过程](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247485146&idx=1&sn=e5bfc79ba915df1f6a8b32b87ef0ef78&chksm=a6e307e191948ef748dc73a4b9a862a22ce1db806a486afce57475d4331d905827d6ca161711&scene=178&cur_album_id=1532487451997454337#rd)

上述流程：

1. 系统调用send （用户态）
2. 内存拷贝成skb （内核态）
3. 网络协议层处理
4. 数据进入网卡驱动的Ring Buffer （网卡的发送队列）
5. 网卡实际发送
6. 网卡发起硬中断通知CPU发完
7. CPU清理Ring Buffer

现在的服务器上的网卡一般都是支持多队列的。每个队列对应发送（传输）和接收的Ring Buffer表示：  
![网卡多队列](/images/2024-06-30-multi-queue-ringbuffer.png)

## 3. WireShark抓包并分析



## 小结


## 参考

1、[用 Wireshark 分析 TCP 吞吐瓶颈](https://www.kawabangga.com/posts/4794)

2、[TCP性能和发送接收窗口、Buffer的关系](https://plantegg.github.io/2019/09/28/%E5%B0%B1%E6%98%AF%E8%A6%81%E4%BD%A0%E6%87%82TCP--%E6%80%A7%E8%83%BD%E5%92%8C%E5%8F%91%E9%80%81%E6%8E%A5%E6%94%B6Buffer%E7%9A%84%E5%85%B3%E7%B3%BB/)

3、[图解Linux网络包接收过程](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247484058&idx=1&sn=a2621bc27c74b313528eefbc81ee8c0f&chksm=a6e303a191948ab7d06e574661a905ddb1fae4a5d9eb1d2be9f1c44491c19a82d95957a0ffb6&scene=21#wechat_redirect)

4、[25 张图，一万字，拆解 Linux 网络包发送过程](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247485146&idx=1&sn=e5bfc79ba915df1f6a8b32b87ef0ef78&chksm=a6e307e191948ef748dc73a4b9a862a22ce1db806a486afce57475d4331d905827d6ca161711&scene=178&cur_album_id=1532487451997454337#rd)

5、这篇汇总了网络栈的很多方面知识点：[Linux Network Stack](https://plantegg.github.io/2019/05/24/%E7%BD%91%E7%BB%9C%E5%8C%85%E7%9A%84%E6%B5%81%E8%BD%AC/)

6、这篇涉及的内核代码都给了github连接：[[译] Linux 网络栈监控和调优：发送数据（2017）](https://arthurchiao.art/blog/tuning-stack-tx-zh/)

7、作为上篇的姊妹篇，内核接收数据：[Linux 网络栈接收数据（RX）：原理及内核实现（2022）](https://arthurchiao.art/blog/linux-net-stack-implementation-rx-zh/)

8、[TCP传输速度案例分析](https://plantegg.github.io/2021/01/15/TCP%E4%BC%A0%E8%BE%93%E9%80%9F%E5%BA%A6%E6%A1%88%E4%BE%8B%E5%88%86%E6%9E%90/)

9、[TCP 拥塞控制对数据延迟的影响](https://www.kawabangga.com/posts/5181)

10、[TCP 长连接 CWND reset 的问题分析](https://www.kawabangga.com/posts/5217)
