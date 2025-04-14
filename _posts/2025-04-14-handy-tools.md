---
title: 工具集索引
description: 统一记录工具和小技巧，便于随时查找和使用
categories: 工具
tags: [工具]
pin: true
---

一些工具和小技巧，有时候要去翻历史博客或者重新搜索，此处进行归档索引，便于随时查找和使用。

## 1. Wireshark

### 1.1. 协议包示意图（Packet Diagram）

![协议示意图](/images/2024-05-29-protocol-diagram.png)

设置路径：在wireshark中对照查看(**设置->Appearance->Layout->Pane3 选 Packet Diagram**)

使用示例，看协议代码时head和图印证：[TCP半连接全连接（一） -- 全连接队列相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/#63-%E6%8E%A5%E6%94%B6%E6%B5%81%E7%A8%8B)

### 1.2. TCP流统计图（TCP Stream Graphs）

详情见：[TCP发送接收过程（一） -- Wireshark跟踪TCP流统计图](https://xiaodongq.github.io/2024/06/30/tcp-wireshark-tcp-graphs/)

![TCP流图形tcptrace](/images/2024-07-01-wireshark-tcptrace.png){: .w-50 .left}

几个示意图：

![tcp RTT图形](/images/2024-07-02-tcp-graph-rtt.png){: .w-50 .left}
![tcp throughput图](/images/2024-07-02-tcp-graph-throughput.png){: .w-50 .right}
![tcptrace图](/images/2024-07-02-tcp-graph-tcptrace.png){: .w-50 .left}
![窗口规模变化图](/images/2024-07-02-tcp-graph-wnd-scaling.png){: .w-50 .right}

### 1.3. 新增实用列（Apply as Column）

在协议帧详情中，选中需要的列，右键 -> Apply as Column 即可加入到抓包列表进行显示。

可以加上下面几个字段：

![tcp-useful-column](/images/2025-04-15-tcp-useful-column.png)

* **The RTT to ACK the segment**
    * 当前 TCP 数据段被确认（ACK）所需的时间，即“往返时间”（Round-Trip Time, RTT）
    * 通过该值可了解网络路径上的延迟情况，以及网络性能是否正常。如果 RTT 值显著增加，可能表明网络中存在拥塞、丢包或其他问题
* Time since first frame in this TCP stream
    * 当前帧与该 TCP 流中**第一个帧**之间的时间差
    * 跟踪整个 TCP 流的时间跨度，帮助分析流的持续时间和行为
* Time since previous frame in this TCP stream
    * 当前帧与同一 TCP 流中**前一帧**之间的时间差
    * 用于分析帧之间的间隔时间，帮助判断数据传输是否均匀
* iRTT
    * TCP 连接建立时的初始往返时间（Initial RTT）
    * 是网络路径上首次测量的延迟，用于评估网络连接的初始状态，作为估算后续 RTT 的基准值
* **Bytes in flight**
    * 当前在网络中未被确认的数据量（单位为字节）
    * 指发送方已经发送但尚未接收到 ACK 确认的数据量，反映了网络中正在传输的未确认数据量，是衡量 TCP 拥塞控制的重要指标

## 2. gperftools、火焰图

各类火焰图：On-CPU、Off-CPU、Wakeup、Off-Wake。以及下面的 [Memory Leak and Growth火焰图](#33-memory-leak-and-growth火焰图)

[并发与异步编程（三） -- 性能分析工具：gperftools和火焰图](https://xiaodongq.github.io/2025/03/14/async-io-example-profile/)

## 3. 内存相关profile

### 3.1. Valgrind Massif

使用实验可参考：[CPU及内存调度（三） -- 内存问题定位工具和实验](https://xiaodongq.github.io/2025/04/02/memory-profiling-tools)

### 3.2. AddressSanitizer 和 其他 Sanitizer工具

使用实验可参考：[CPU及内存调度（三） -- 内存问题定位工具和实验](https://xiaodongq.github.io/2025/04/02/memory-profiling-tools)

### 3.3. Memory Leak and Growth火焰图

[Memory Leak and Growth火焰图](https://www.brendangregg.com/FlameGraphs/memoryflamegraphs.html)

使用实验可参考：[CPU及内存调度（三） -- 内存问题定位工具和实验](https://xiaodongq.github.io/2025/04/02/memory-profiling-tools)

## 4. bcc tools

[eBPF学习实践系列（二） -- bcc tools网络工具集](https://xiaodongq.github.io/2024/06/10/bcc-tools-network/)

![bcc tools 2019](/images/bcc-tools-2019.png)  

### 4.1. 60s系列BPF版本

![bcc tools 60s](/images/ebpf_60s-bcctools2017.png)

### 4.2. 60s系列Linux命令版本

```
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

## 5. bpftrace

bpftrace提供的追踪类型：

![bpftrace提供的追踪类型](/images/bpftrace_probes_2018.png)

[eBPF学习实践系列（六） -- bpftrace学习和使用](https://xiaodongq.github.io/2024/06/28/ebpf-bpftrace-learn/)



