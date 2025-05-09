---
title: TCP发送接收过程（二） -- 实验观察TCP性能和窗口、Buffer的关系
description: 通过实验观察TCP性能和窗口、Buffer的关系，并用Wireshark跟踪TCP Stream Graphs。
categories: [网络, TCP]
tags: [TCP, Wireshark, 接收缓冲区]
---


## 1. 引言

[上一篇博客](https://xiaodongq.github.io/2024/06/30/tcp-wireshark-tcp-graphs/)中介绍了Wireshark里的TCP Stream Graghs可视化功能并查看了几种典型的图形，本篇进行实验观察TCP性能和窗口、Buffer的关系，并分析一些参考文章中的案例。

一些相关文章：

* 参考本篇进行实验：[TCP性能和发送接收窗口、Buffer的关系](https://plantegg.github.io/2019/09/28/%E5%B0%B1%E6%98%AF%E8%A6%81%E4%BD%A0%E6%87%82TCP--%E6%80%A7%E8%83%BD%E5%92%8C%E5%8F%91%E9%80%81%E6%8E%A5%E6%94%B6Buffer%E7%9A%84%E5%85%B3%E7%B3%BB/)
    * 实验来自 [知识星球 -- 实验动起来 BDP和buffer、RT的关系](https://wx.zsxq.com/group/15552551584552/topic/181428425525182)。
    * 下面是其他人做的实验，呈现方式挺好，可参考。
    * [Packet capture experiment 1](https://yishenggong.com/2023/04/11/packet-capture-experiment-1-packet-delay-loss-duplicate-corrupt-out-of-order-and-bandwidth-limit/)
    * [Packet capture experiment 2](https://yishenggong.com/2023/04/15/packet-capture-experiment-2-send-receive-buffer/)
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

## 2. 理论和技巧说明

### 2.1. 计算在途字节数

**在途字节数（`Bytes in flight`）**：发送方已发送出去，但是尚未接收到ACK确认的字节数（正在链路上传输的数据）。`在途字节数`如果超出网络的承载能力，会出现丢包重传。

**如何计算在途字节数？**
* TCP传输过程中，由于客户端和服务端的网络包可能是不同的顺序，所以最好两端都进行抓包，并从 **<mark>数据发送方</mark>** 抓到的包分析在途字节数。
* 计算方式：`在途字节数 = Seq + Len - Ack`（Wireshark中提供的`SEQ/ACK analysis`功能会自动计算）
* TCP协议中，由发送窗口动态控制，跟`cwnd`拥塞窗口和`rwnd`接收窗口也有关系。

在Wireshark中可以直接查看其提供的`Seq`、`Ack`分析结果，方式可见 [Wireshark中新增实用列](https://xiaodongq.github.io/2025/04/14/handy-tools/#13-%E6%96%B0%E5%A2%9E%E5%AE%9E%E7%94%A8%E5%88%97apply-as-column)中的示例：

![tcp-useful-column](/images/2025-04-15-tcp-useful-column.png)

### 2.2. 估算网络拥塞点

当发送方发送大量数据，`在途字节数`超出网络承载能力时，就会导致拥塞，这个数据量就是 **<mark>拥塞点</mark>**。

大致可以认为：**发生拥塞时的在途字节数就是该时刻的网络拥塞点。**

**如何在Wireshark中找到拥塞点？**

* 从Wireshark中找到一连串**重传包**中的<mark>第一个</mark>，再根据重传包的`Seq`找到 **<mark>原始包</mark>**，最后查看原始包发送时刻的**在途字节数**。
* 具体步骤：
    * 在 **<mark>Export Info</mark>**中查看重传统计表
    * 找到第一个重传包，根据其`Seq`**找原始包**，可以直接在`SEQ/ACK analysis`中跳转到原始包。
    * 如下图所示，对应的原始包是`No为46`的包，其在途字节数为`908`，即此时的网络拥塞点。
* 该方法不一定很精确，但很有参考意义。

拥塞点估算示例：  
![wireshark-find-retran-seq](/images/wireshark-find-retran-seq.png)

### 2.3. 带宽时延积（BDP）

**带宽时延积`BDP（Bandwidth-Delay Product）`**：`带宽 (bps)` 和 `往返时延 (RTT, 秒)`的乘积，衡量在特定带宽和往返时延（RTT）下，网络链路上可同时传输的最大数据量。

* 公式：`BDP (bits)=带宽 (bps) * 往返时延 (RTT, 秒)`
    * 如：带宽1Gbps（即万兆）、RTT为50ms，则 `BDP = 10^9 * 0.05 = 5*10^7 = 6.25MB`
    * 试下`LaTeX`语法：\text{BDP} = \(10^9 \times 0.05 = 5 \times 10^7\) bits = \text{6.25MB}
* 和**在途字节数**的关系：`BDP`是链路的理论容量，`在途字节数`是实时传输中的数据量。
    * 若`在途字节数 == BDP`，说明链路被完全填满，可达到最大吞吐量
    * 若`在途字节数 < BDP`，链路未充分利用
    * 若`在途字节数 > BDP`，可能引发拥塞或丢包

## 3. 实验说明

### 3.1. 环境和步骤

自己本地只有一个Mac笔记本和Rocky Linux系统的PC，对MacOS的内核网络控制不熟悉，还是尽量模拟生产环境中的Linux间通信，起ECS进行实验。

起2个阿里云ECS（2核2G）：
* 系统：Rocky Linux release 9.5 (Blue Onyx)
* 内核：5.14.0-503.35.1.el9_5.x86_64

网速基准：TCP 2.1Gbps左右

```sh
# TCP
[root@iZbp169scc1yz2vwe6mp31Z ~]# iperf3 -c 172.16.58.147
Connecting to host 172.16.58.147, port 5201
[  5] local 172.16.58.146 port 56178 connected to 172.16.58.147 port 5201
[ ID] Interval           Transfer     Bitrate         Retr  Cwnd
...
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  2.56 GBytes  2.20 Gbits/sec  87452             sender
[  5]   0.00-10.22  sec  2.56 GBytes  2.15 Gbits/sec                  receiver
```

步骤说明：
* 服务端：`python -m http.server`起http服务，监听8000端口
    * `dd`一个2GB文件用于测试：`dd if=/dev/zero of=test.dat bs=1G count=2`
* 客户端：`curl`请求下载文件
    * `curl "http://xxx:8000/test.dat" --output test.dat`
* 抓包：
    * `tcpdump -i any port 8000 -s 100 -w normal_client.cap -v`
    * 先两端都抓包对比下，服务端也抓包：`tcpdump -i any port 8000 -s 100 -w normal_server.cap -v`
    * 下面只看客户端（网络路径比较简单，抓包差别不大，只看一边即可）

自己PC的Rocky Linux发送接收窗口相关参数默认值（**可通过<mark>man tcp</mark>查看各选项含义和功能**）：

```sh
# ECS里则把下面两项：TCP和UDP的内存配置降低了，其他一样
# net.ipv4.tcp_mem = 18951        25271   37902
# net.ipv4.udp_mem = 37905        50542   75810

# 本地PC
[root@xdlinux ➜ tmpdir ]$ sysctl -a|grep mem
# 每个socket接缓冲区的默认值，字节
net.core.rmem_default = 212992
# 每个socket接收缓冲区的最大允许值，字节
net.core.rmem_max = 212992
# 每个socket发送缓冲区的默认值，字节
net.core.wmem_default = 212992
# 每个socket发送缓冲区的最大允许值，字节
net.core.wmem_max = 212992

# TCP协议整体使用的内存阈值，注意：单位是page（page size一般4KB，可`getconf PAGESIZE`查看）
# [low, pressure, high]数组。
# low：TCP内存充足，无需限制；pressure：内核开始限制TCP内存分配；high：内核拒绝新连接
    # (低水位 压力模式 上限)
    # (1.43GB 1.92GB 2.88GB)
net.ipv4.tcp_mem = 371808	495745	743616
# TCP单个连接的接收缓冲区窗口，单位：字节。在TCP中会覆盖上面的全局socket缓冲区配置
# TCP根据网络状况动态调整缓冲区大小，范围在[min, max]之间
    # [min, default, max]
    # 4KB 128KB 6MB
net.ipv4.tcp_rmem = 4096	131072	6291456
# TCP单个连接的发送缓冲区大小
    # 4KB 16KB 4MB
net.ipv4.tcp_wmem = 4096	16384	4194304

# UDP整体使用的内存阈值，单位：page
    # (低水位 压力模式 上限)
    # (2.88GB 3.84GB 5.76GB)
net.ipv4.udp_mem = 743616	991490	1487232
# UDP单个连接接收缓冲区的最小值，4KB
net.ipv4.udp_rmem_min = 4096
# UDP单个连接发送缓冲区的最小值，4KB
net.ipv4.udp_wmem_min = 4096
```

### 3.2. 实验用例

* 1、保持默认参数正常curl下载文件，抓包用作基准对比
* 2、修改**服务端的发送窗口**为最小值：4096，即一个page size；**客户端不变**
    * 服务端：`sysctl -w net.ipv4.tcp_wmem="4096 4096 4096"`
* 3、**服务端不变**；修改**客户端的接收窗口**为4096
    * 客户端：`sysctl -w net.ipv4.tcp_rmem="4096 4096 4096"`

### 3.3. 结果及分析

用例1：默认参数

![bdp-case-normal-param](/images/bdp-case-normal-param.svg)

用例2：服务端的发送窗口4096字节

![bdp-case-normal-param](/images/bdp-case-server-swnd4096.svg)

用例3：客户端的接收窗口4096字节。很慢且抓包太大，手动打断了下载

![bdp-case-normal-param](/images/bdp-case-client-rwnd4096.svg)



## 4. 小结

## 5. 参考

* [TCP性能和发送接收窗口、Buffer的关系](https://plantegg.github.io/2019/09/28/%E5%B0%B1%E6%98%AF%E8%A6%81%E4%BD%A0%E6%87%82TCP--%E6%80%A7%E8%83%BD%E5%92%8C%E5%8F%91%E9%80%81%E6%8E%A5%E6%94%B6Buffer%E7%9A%84%E5%85%B3%E7%B3%BB/)
* [TCP传输速度案例分析](https://plantegg.github.io/2021/01/15/TCP%E4%BC%A0%E8%BE%93%E9%80%9F%E5%BA%A6%E6%A1%88%E4%BE%8B%E5%88%86%E6%9E%90/)
* [TCP 拥塞控制对数据延迟的影响](https://www.kawabangga.com/posts/5181)
* [TCP 长连接 CWND reset 的问题分析](https://www.kawabangga.com/posts/5217)
* 《Wireshark网络分析的艺术》
* LLM
