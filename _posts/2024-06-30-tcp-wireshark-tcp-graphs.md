---
title: TCP发送接收过程（一） -- Wireshark跟踪TCP流统计图
categories: 网络
tags: [TCP, Wireshark, 接收窗口]
---

TCP发送接收过程相关学习实践和Wireshark跟踪，本节先介绍基本过程及如何使用TCP Stream Graphs

## 1. 背景

前段时间立了个flag，准备6月底完成之前的网络知识点TODO，已经月底了，常态性延期。

虽然没达到最终预期，但这种方式对提高效率确实管用，这几天是deadline，昨天**看**了好几篇之前放着没看的文章（初期计划是**看+实验**）。

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

调整了下标题，后续该主题的学习实践笔记作为一个小系列，此为第一篇。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 前置说明

这个方面扩展开来涉及很多点。针对TCP发送、接收数据相关过程，可以先去分析学习内核源码再去实验，也可以先观察现象再去跟踪代码印证，这里结合两种方式：先看简单原理大概梳理后再实验，再去跟源码，再跟实验印证。

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
    - 这里涉及接收缓冲区buffer（接收窗口）
8. 内核唤醒用户进程

### 2.2. Linux网络栈发送数据简要说明

![Linux网络栈发送数据](/images/2024-06-30-kernel-network-send.png)  
出处：[25 张图，一万字，拆解 Linux 网络包发送过程](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247485146&idx=1&sn=e5bfc79ba915df1f6a8b32b87ef0ef78&chksm=a6e307e191948ef748dc73a4b9a862a22ce1db806a486afce57475d4331d905827d6ca161711&scene=178&cur_album_id=1532487451997454337#rd)

上述流程：

1. 系统调用send （用户态）
2. 内存拷贝成skb （内核态）
3. 网络协议层处理 （socket的发送队列，具体位置在2还是3前后待定 TODO）
    - 这里涉及发送缓冲区buffer（发送窗口）
4. 数据进入网卡驱动的Ring Buffer （网卡的发送队列）
5. 网卡实际发送
6. 网卡发起硬中断通知CPU发完
7. CPU清理Ring Buffer

现在的服务器上的网卡一般都是支持多队列的。每个队列对应发送（传输）和接收的Ring Buffer表示：

![网卡多队列](/images/2024-06-30-multi-queue-ringbuffer.png)

### 2.3. TCP发送、接收窗口

> TCP 为了优化传输效率（注意这里的传输效率，并不是单纯某一个 TCP 连接的传输效率，而是整体网络的效率），会:
>
> 1. 保护接收端，发送的数据不会超过接收端的 buffer 大小 (Flow control)。数据发送到接受端，也是和上面介绍的过程类似，kernel 先负责收好包放到 buffer 中，然后上层应用程序处理这个 buffer 中的内容，如果接收端的 buffer 过小，那么很容易出现瓶颈，即应用程序还没来得及处理就被填满了。那么如果数据继续发过来，buffer 存不下，接收端只能丢弃。
> 2. 保护网络，发送的数据不会 overwhelming 网络 (Congestion Control, 拥塞控制), 如果中间的网络出现瓶颈，会导致长肥管道的吞吐不理想；

TCP三次握手时会协商好接收窗口，而发送窗口复杂一些，会根据接收窗口和网络因素决定。

> 对于接收端的保护，在两边连接建立的时候，会协商好接收端的 buffer 大小 (`receiver window size, rwnd`), 并且在后续的发送中，接收端也会在每一个 ack 回包中报告自己剩余和接受的 window 大小。这样，发送端在发送的时候会保证不会发送超过接收端 buffer 大小的数据。

> 对于网络的保护，原理也是维护一个 Window，叫做 `Congestion window，拥塞窗口，cwnd`, 这个窗口就是当前网络的限制，发送端不会发送超过这个窗口的容量（没有 ack 的总数不会超过 cwnd）。

参考：[用 Wireshark 分析 TCP 吞吐瓶颈](https://www.kawabangga.com/posts/4794)

（三次握手时的协商观察，可见MTU实验：[网络实验-设置机器的MTU和MSS](https://xiaodongq.github.io/2023/04/09/network-mtu-mss/)，之前还留了TODO项）

也推荐看下林沛满的《Wireshark网络分析就这么简单》、《Wireshark网络分析的艺术》。

## 3. WireShark如何查看TCP Stream Graphs

### 3.1. 总体说明

Wireshak提供的TCP Stream Graphs可视化功能，用于展示TCP连接中的数据传输情况。

查看方式：

![TCP流图形tcptrace](/images/2024-07-01-wireshark-tcptrace.png)

下面根据抓包进行分别说明。

### 3.2. 基本场景构造

构造场景基于一个抓包文件查看

1、**服务端**：192.168.1.150，`python -m http.server`起http服务，并开启抓包`tcpdump -i any port 8000 -nn -w 8000_wget.cap -v`

```sh
# 且当前目录有个1.7MB的文件
[root@xdlinux ➜ workspace ]$ ls -ltrh
-rwxr-xr-x   1 root    root    1.7M Jun 17 22:42 minimal

[root@xdlinux ➜ workspace ]$ python -m http.server
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...
```

2、**客户端**：192.168.1.2，下载文件`wget 192.168.1.150:8000/minimal`

抓包文件在：[这里](/images/srcfiles/20240701-wnd-8000_wget.cap)

### 3.3. 1）Round Trip Time

往返时间图，RTT图表直接展示了每个数据包或ACK从发送到接收到响应的时间，能直观地了解数据在两端之间往返的延迟变化情况。

如果RTT波动大，可能指示网络拥塞、丢包或路由不稳定；如果RTT持续较高，则可能意味着网络基础结构存在延迟问题。

![tcp RTT图形](/images/2024-07-02-tcp-graph-rtt.png)

（Q：详细介绍下 wireshark 里TCP Stream Graphs中 RTT图表）

主要用途：

1. 延迟诊断：识别网络中的延迟问题，例如，高且不稳定的RTT值可能指示网络拥塞、路由问题或物理距离过远。
2. 性能优化：评估网络连接的响应速度，根据RTT趋势调整网络配置或应用参数，以提升用户体验。
3. 拥塞控制分析：结合TCP的拥塞控制机制，理解数据包的发送速率如何受网络状况影响，如慢启动、拥塞避免阶段。
4. 问题定位：帮助定位延迟发生的具体环节，比如是客户端、服务端还是中间网络的问题。
5. 趋势监测：观察RTT随时间的变化，判断网络状况是否恶化或改善。

**图表解读：**

- **横轴**：通常表示时间序列，每个点或线段对应一个数据包的发送时刻。
- **纵轴**：表示RTT的值，单位通常是毫秒(ms)，反映了数据包往返所需的时间。
- **点/线**：图表上的点或线段直观展现了每个数据包的RTT值，密集的点群可能表示数据传输频繁，稀疏的点群则可能意味着数据传输间歇。

**分析技巧：**

- 寻找异常：注意异常高的RTT值，这可能是网络问题的信号。
- 趋势分析：观察RTT随时间的走势，上升趋势可能预示着网络拥塞加剧。
- 对比分析：对比不同时间段、不同连接或不同网络条件下的RTT，找出差异和规律。
- 结合其他图：结合吞吐量图、窗口规模图等，全面分析TCP连接的性能。

### 3.4. 2）Throughput

吞吐量图，展示了TCP数据流在一段时间内的数据传输速率，通常以每秒比特数(bps)或每秒字节(byt/s)为单位。图表的横轴代表时间，纵轴代表吞吐量，通过图形化的方式直观地显示数据传输速度的变化情况。

![tcp throughput图](/images/2024-07-02-tcp-graph-throughput.png)

（Q：详细介绍下 wireshark 里TCP Stream Graphs中 RTT图表；里面还有个goodput是什么）

在Wireshark的TCP Stream Graphs中，Throughput（吞吐量）图表是用于展示TCP连接随时间的数据传输速率，这对于评估网络性能、诊断带宽限制或拥塞问题非常重要。

主要用途：

1. 性能评估：评估网络连接或应用的数据传输能力，判断是否达到预期的带宽利用率。
2. 瓶颈识别：帮助识别网络中的带宽瓶颈，比如当吞吐量无法达到理论最大值时，可能是因为网络配置、硬件限制或网络拥堵。
3. 趋势分析：观察吞吐量随时间的变化趋势，了解数据传输速率是否稳定，是否存在周期性波动或突然下降。
4. 故障定位：结合其他指标（如RTT、重传率），帮助确定数据传输缓慢的原因，比如网络拥塞、丢包导致的TCP重传和慢启动。
5. 优化决策：为网络优化和扩容提供依据，比如决定是否需要增加带宽资源或调整TCP参数。

**图表解读：**

- **横轴**：时间轴，展示数据采集的持续时间，可用来分析特定时间段内的吞吐量变化。
- **纵轴**：吞吐量轴，单位通常为bps或byt/s，显示了在这段时间内平均每秒传输的数据量。
- **曲线形态**：平滑上升的曲线可能表明数据传输平稳；波动的曲线可能说明网络存在波动或间歇性拥塞；急剧下降可能指示网络故障或应用暂停传输。
- **Goodput（有效吞吐量）**：是指实际对应用层有用的数据传输速率，即扣除所有重传、协议开销、丢包以及其他传输中损耗后，成功传输到接收端并能被应用使用的数据量的速率。相比于Throughput（吞吐量），Goodput更能准确反映网络对终端用户的有效数据交付能力。

**分析技巧：**

- 识别峰值与低谷：查找吞吐量的最高点和最低点，分析网络容量的极限以及可能的性能下降原因。
- 时间关联分析：将吞吐量下降的时间点与网络事件、应用行为或用户活动关联起来，寻找因果关系。
- 长期趋势：分析长时间跨度内的吞吐量趋势，判断网络是否能够满足日益增长的数据需求。
- 对比分析：比较不同时间段、不同连接或不同条件下的吞吐量，评估网络优化措施的效果。

### 3.5. 3）Time/Sequence(Stevens)

时间序列图，由网络专家 Bill Stevens 提倡并以其命名，关注于展示单位时间内TCP流在某个方向上传输的字节数

图表中的线条代表了随时间变化的数据流传输速率，这对于观察数据传输的速度和模式非常有用。
Stevens 图更侧重于展示数据传输量与时间的关系，帮助用户理解数据传输的动态过程和速率变化。

![tcp time/sequence stevens图](/images/2024-07-02-tcp-graph-ts-stevens.png)

（Q：详细介绍下 wireshark 里TCP Stream Graphs中 time/sequence stevens图表）

它以时间序列为基础，展示每个数据包的序列号（Sequence Number）及其在时间轴上的分布，以此来帮助分析TCP流的行为和性能。

功能概述：

- 序列号跟踪：此图表通过序列号展示了数据包在网络中传输的顺序和完整性，序列号的连续性有助于识别数据包丢失、乱序或重传。
- 时间轴展示：**横轴代表时间，纵轴代表TCP数据流中的字节偏移量（或序列号）**，直观显示了数据包发送和接收的时间分布。
- 流量模式：通过数据点的密集程度和分布，可以观察到数据传输的速率变化，如突发传输、空闲期等。
- 连接活动分析：帮助理解TCP连接的活动模式，比如连接建立、数据传输、暂停、重传和连接终止等阶段。

**图表解读：**

- **序列号跳跃**：如果序列号出现非连续的跳跃，可能意味着某些数据包未被接收方确认或丢失。
- **时间间隔**：数据点间的水平距离反映了数据包间的时间间隔，长时间间隔可能意味着传输暂停或延迟。
- **斜率变化**：斜率反映了数据传输速率，斜率陡峭表示高速传输，平坦则表示传输放缓或暂停。

**分析技巧：**

- 结合其他统计：与RTT、Throughput等其他图表结合使用，可以更全面地分析TCP连接的性能。
- 异常检测：寻找序列号不连续、大量重传或窗口突然减小等异常现象，这些可能是问题的信号。
- 数据包筛选：在查看图表前，先通过Wireshark的过滤器功能筛选出特定的TCP流或事件，以聚焦分析目标。

### 3.6. 4）Time/Sequence(tcptrace)

另一种时间序列图，源自Unix的tcptrace工具，tcptrace图表提供了比Stevens格式更详尽的信息，特别侧重于TCP连接的性能和控制特性。

tcptrace 的图表示的是单方向的数据发送，有时需要切换方向：

![切换方向](/images/2024-07-01-switch-dir.png)

![tcptrace图](/images/2024-07-02-tcp-graph-tcptrace.png)

这里也能大概看到慢启动的过程，前面发送数据的斜率更大一些。

（Q：详细介绍下 wireshark 里TCP Stream Graphs中 time/sequence tcptrace图表）

tcptrace图表通过展示TCP数据包的发送和接收时间以及序列号，帮助分析人员深入了解TCP连接的细节，包括但不限于：

- 数据传输速率：通过时间序列上的点分布，可以观察数据传输的速率变化。
- TCP窗口行为：图表上方的线通常表示接收窗口的大小变化，帮助分析流量控制机制。
- 确认行为：可以观察到ACK的返回模式，分析TCP的确认机制。
- 重传和丢失：通过序列号的重复或跳跃，以及时间间隔的异常，可以推断数据包的丢失和重传情况。

**图表解读：**

- **图形说明**：下方蓝点/线代表TCP在某个方向上所传输数据字节数，上方线（绿线）代表接收窗口的大小。如果上下两条线接近或重叠，可能意味着发送方受到了接收方窗口大小的限制。黄线表示已被ACK的数据。
- **斜率和间距**：数据点的斜率反映了数据传输速度，点之间的间距则体现了数据包的发送间隔，进而可以分析网络延迟或拥塞情况。
- **窗口变化**：接收窗口的扩大或缩小直接反映了接收方的缓冲区状态和流量控制策略。

**分析技巧：**

- 窗口动态分析：观察接收窗口随时间的变化，判断是否出现了窗口缩放导致的数据传输受限。
- 重传确认：寻找序列号重复或预期之外的序列号跳变，结合时间轴判断是否有重传发生，以及重传对整体性能的影响。
- 性能瓶颈识别：窗口大小长时间保持不变或频繁调整，可能是网络瓶颈或接收方处理能力限制的信号。

已发送的数据（蓝点）和ACK线之间，竖直方向的距离代表在途字节数（Bytes in flight）

![tcptrace1](https://packetbomb.com/wp-content/uploads/2014/06/tcptrace1.png)  
[出处](https://packetbomb.com/understanding-the-tcptrace-time-sequence-graph-in-wireshark)

#### 3.6.1. 另外两种线：SACK和丢包

参考文章里给的另外两种线：

![tcptrace-sack](https://www.kawabangga.com/wp-content/uploads/2022/08/tcptrace-sack.png)

> 需要始终记住的是 Y 轴是 Sequence Number，红色的线表示 SACK 的线表示这一段 Sequence Number 我已经收到了，然后配合黄色线表示 ACK 过的 Sequence Number，那么发送端就会知道，在中间这段空挡，包丢了，**红色线和黄色线纵向的空白**，是没有被 ACK 的包。所以，需要重新传输。而蓝色的线就是表示又重新传输了一遍。

#### 3.6.2. tcptrace图的一些细节

参考：[在Wireshark的tcptrace图中看清TCP拥塞控制算法的细节(CUBIC/BBR算法为例)](https://blog.csdn.net/dog250/article/details/53227203)，博主对拥塞算法很有研究，后续涉及到在具体学习。

此处仅列几个细节点，留一点印象。

![tcptrace图的一些细节](/images/2024-07-03-tcp-graph-tcptrace-detail.jpeg)

红圈标识了3个阶段，并借助辅助线标识了斜率、间距的含义：

* 启动阶段
* 产生队列拥塞
* 拥塞缓解和消除

### 3.7. 5）Windows Scaling

窗口规模图，Windows Scaling图表主要关注TCP连接的窗口规模（Window Scaling）特性，这是TCP协议中用于提高数据传输效率的一个机制。展示了TCP连接中**接收窗口**规模随时间的变化情况。（下面的图中还可以看到发送端发送出去的包）

![窗口规模变化图](/images/2024-07-02-tcp-graph-wnd-scaling.png)

实际接收窗口为通过`window * factor`计算得到的乘积：

![窗口factor](/images/2024-07-02-wnd-factor.png)

（Q：详细介绍下 wireshark 里TCP Stream Graphs中 Windows Scaling图表）

主要特点：

1. 接收窗口规模：图表展示了接收方通告的窗口大小如何随时间调整，这直接关系到发送方能发送多少数据而不必等待确认。
2. 动态调整：通过图表可以观察到窗口规模在通信过程中的动态调整，反映了TCP的流量控制机制。
3. 性能影响：窗口规模的变化对数据传输速率有直接影响，图表有助于分析窗口缩放对整体吞吐量的潜在影响。
4. 优化分析：分析窗口规模设置是否合理，是否成为限制传输速率的因素，为网络优化提供参考。

图表解读：

- **窗口规模因子**：通常在TCP三次握手期间通过TCP选项协商确定，图表可能以数值或调整后的窗口大小展示这一信息。
    - 上面的图中接收窗口大小是根据factor计算后的
- **接收窗口大小**：图表中的实际数值反映了接收方当前能够接收的数据量，其变化可能反映出接收方缓冲区的可用空间变化。
- **时间序列**：横轴代表时间，纵轴通常表示窗口大小，图表上的点或线随时间变化，显示窗口规模调整的时刻和幅度。

**分析技巧：**

- **评估窗口缩放效果**：检查窗口规模是否随数据传输需求适时调整，评估其对吞吐量的正面或负面影响。
- **识别瓶颈**：如果窗口规模长时间维持在一个较低水平，可能意味着接收方处理能力或网络条件限制了数据传输。
- **优化建议**：基于窗口调整行为，提出调整TCP参数或优化网络配置的建议，以提升传输效率。

## 4. 看图说话-几种常见的图形模式

基于上面的几种类型的graph说明，对照“[用 Wireshark 分析 TCP 吞吐瓶颈](https://www.kawabangga.com/posts/4794)”中的几种图形印证学习。

### 4.1. 丢包

![丢包图形](https://www.kawabangga.com/wp-content/uploads/2022/08/wireshark-packet-loss.png)

> 很多红色 SACK，说明接收端那边重复在说：中间有一个包我没有收到，中间有一个包我没有收到。

前面说过红色的线表示这一段 Sequence Number 已经收到了，黄色（**或者说棕色**）线表示 ACK 过的 Sequence Number，红色线和黄色线纵向的空白是没有ACK的包，即需要重传的包。

上述图形中，红色和黄色之间的空白貌似不大明显，待构造一个简单丢包场景抓包查看。（TODO）

### 4.2. 吞吐受到接收端 window size 限制

![接收缓冲区瓶颈](https://www.kawabangga.com/wp-content/uploads/2022/08/rwnd-too-low.png)

> 从这个图可以看出，黄色的线（接收端一 ACK）一上升，蓝色就跟着上升（发送端就开始发），直到填满绿色的线（window size）。说明网络并不是瓶颈，可以调大接收端的 buffer size.

这里说明了一下因果关系：**已发送数据先被接收端ACK（黄线），然后才发送数据（蓝点）**，直到填满接收端的接收缓冲区，所以瓶颈在接收端。

### 4.3. 吞吐受到发送端 Buffer 的限制

![发送缓冲区瓶颈](https://www.kawabangga.com/wp-content/uploads/2022/08/limited-by-sender-buffer.png)

> 可以看到绿线（接收端的 window size）远没有达到瓶颈，但是发送端的模式不是一直发， 而是发一段停一段。就说明发送端的 buffer 已经满了，这时候 Kernel block 住了 App，必须等这些数据被 ACK 了，才能让 App 继续往 buffer 中塞入数据。

也可以用上面的因果关系来解释：接收端ACK后（黄线），发送端开始发送数据（蓝点），但是所发数据并没有达到对端可接收的上限（绿线），所以瓶颈在发送端。（需要跟拥塞控制区分开，下小节介绍）

发送端的发送缓冲区大小多少合适，涉及**带宽时延积（Bandwidth-Delay Product，BDP）**概念，即带宽和时延RTT的乘积，用来量化在特定时间内网络中可以传输的数据量。

* 例如，如果一个网络链路的带宽是100 Mbps（兆比特每秒），而端到端的延迟是100毫秒（ms），则`BDP = 100 Mbps * 100 ms = 10,000,000 bits`，即1,250,000 字节（1.2MB）
* 在TCP协议中，为了高效利用带宽并减少拥塞，TCP窗口大小（即**一次可以发送而不必等待确认的数据量**）应该与BDP匹配。如果窗口太小，不能充分利用带宽；太大则可能导致网络拥塞。
* 理解BDP有助于设计更有效的流量控制和拥塞控制机制，确保数据在网络中的平稳传输

#### 4.3.1. 和拥塞控制区分开

此时间序列波形对应的窗口变化图如下：

![窗口规模图](https://www.kawabangga.com/wp-content/uploads/2022/08/traffic-limited-by-sender.png)

> 可以看一开始蓝色线的垂直距离很短，后面逐渐变长，说明 cwnd 在变大，然后变大到一定的程度不变了。说明 cwnd 没成为瓶颈。

> 蓝色线每次发送数据时，短时间达到某一个最高点就不再上升了。但是上升的过程也没有下降过，“没有下降过”就可以说明，cwnd 没有下降过，即 cwnd 没有成为瓶颈。

作为对比，查看我们上面构造的wget场景的窗口规模图：

![窗口规模变化图](/images/2024-07-02-tcp-graph-wnd-scaling.png)

可看到并没有到接收端接收窗口的瓶颈，但后面发送端发送数据（蓝点/线）的垂直距离有长有短，且其水平线也有高有低。**说明什么呢？**（**TODO 待明确**，说明拥塞控制机制？说明受网络质量影响？局域网两台机器并没有丢包）

### 4.4. 吞吐受到网络质量限制

示例1:

![拥塞窗口影响](https://www.kawabangga.com/wp-content/uploads/2022/08/wireshark-cwnd-low.png)

> 从这张图中可以看出，接收端的 window size 远远不是瓶颈，还有很多空闲。但是发送端不会一直发直到填满接收端的 buffer。

放大后的图：

![放大后的图](https://www.kawabangga.com/wp-content/uploads/2022/08/wireshark-cwnd-low-zoom.png)

> 放大可以看出，中间有很多丢包和重传，这会让发送端认为网络质量不好，会谨慎发送数据，想避免造成网络拥塞。发送端每次只发送一点点数据，发送的模式是发一点，停一点，然后再发一点，而不是一直发。这也说明很有可能是 cwnd 太小了，受到了拥塞控制算法的限制。

示例2：下面这种模式是一种更加典型的因为丢包导致带宽很小的问题

![丢包导致带宽很小](https://www.kawabangga.com/wp-content/uploads/2022/08/packet-drop-caused-bandwidth-issue.png)

可看到：

> * 在这个链接中，Flow Control（即 Linux 中的 tcp buffer 参数，绿色线）远远没有达到瓶颈；
> * 图中有很多红色线，表示 SACK，说明图中有很多丢包；
> * 蓝色线表示发送的数据，发送的模式是，每隔 0.23s 就发送一波，然后暂停，等 0.23s 然后再发送一波。蓝色线在 Y 轴上表示一次性发送的数据，可以看到，每一段的纵向长度在不断减少。
>     * 0.23s 是物理上的延迟
>     * 蓝色线没有一直发送，而是发送，暂停，发送，暂停，是因为拥塞控制算法的窗口（cwnd）变小了，每次发送很快填满窗口，等接收端（0.23s之后）收到了，再继续发送；
>     * 并且蓝色线的纵向距离每一波都在减少，说明这个窗口在每次发生丢包之后都在变小（减为一半）。

放大后的图：

![放大后的图](https://www.kawabangga.com/wp-content/uploads/2022/08/explain-for-congestion-control.png)

### 4.5. 完美的 TCP 连接

> 最后放一张完美的 TCP 连接（长肥管道），发送端一直稳定的发，没有填满 receiver window，cwnd 也没有限制发送速率。

![完美TCP连接发送数据](https://www.kawabangga.com/wp-content/uploads/2022/08/a-perfect-tcp-connection.png)

> 这个完美连接的带宽是 10Mib/s，RTT < 1ms, 可以看到2s发送的 Sequence nunber 是 2500000，计算可以得到 2500000 / 1024 / 1024 * 8 / 2 = 9.535 Mib/s，正好达到了带宽。

这里说明一下**长肥管道（Long Fat Networks，LFN，[RFC7323](https://datatracker.ietf.org/doc/html/rfc7323)）**：

TCP长肥管道（长肥网络）指在具有高带宽（Bandwidth）和高延迟（Latency）特性的网络环境中运行的TCP连接。这个术语形象地描绘了网络如同一个既长又宽的管道，其中“长”指的是延迟高，“肥”则指的是带宽大。

相关的挑战和解决方案：

* **窗口大小限制**
    * TCP协议最初设计时，其头部中的接收窗口大小字段为16位，这意味着理论上最大的接收窗口大小为65535字节（或64KiB）。在高带宽时延乘积（Bandwidth-Delay Product, BDP）的网络中，这个窗口大小不足以支撑足够的待确认数据量来充分利用高带宽，从而限制了数据传输速率。
    * **解决方案**：窗口缩放选项（Window Scaling），TCP选项之一，允许窗口大小通过一个缩放因子（`scaling factor`）扩展到超过65535字节。RFC 1323引入了这个选项，使得窗口大小理论上可以达到2^30字节，从而提高了在高BDP网络中的性能。
* **慢启动**
    * TCP连接开始时会经历慢启动阶段，逐步增加发送窗口大小。在长肥管道中，这个过程会更加缓慢，因为需要更多的往返时间（Round-Trip Time, RTT）才能达到较高的数据传输率。
    * **解决方案**：拥塞控制算法优化，现代的拥塞控制算法如`CUBIC`和`BBR`通过更快速地探测网络容量和动态调整发送速率，在长肥管道中可以更快地达到较高的数据传输率，相对缩短了达到最佳传输速度所需的时间，缓解了慢启动的问题。
* **拥塞控制过于保守**
    * 标准的TCP拥塞控制算法如TCP Tahoe或TCP Reno可能在长肥管道中过于保守，导致无法充分利用可用带宽。此外，长距离传输中的轻微丢包可能导致不必要的拥塞窗口减小，进一步降低吞吐量。
    * **解决方案**：同样是通过采用更先进的拥塞控制算法，如上面的`BBR`，这些算法不仅仅基于丢包来判断网络拥塞，还考虑了瓶颈带宽和往返时延，能够在不过分反应丢包事件的情况下，更精细地调节发送速率，避免不必要的窗口减小，确保高效利用带宽。
* **隐含挑战：丢包导致的性能下降**
    * **解决方案**：`选择性确认（SACK）`，SACK机制帮助快速定位并恢复丢失的数据段，而不需要重传已正确接收的数据，减少了因误判丢包导致的不必要的流量，提高了整体传输效率和可靠性。

## 5. 小结

学习了TCP发送和接收涉及的总体传输过程，以及Wireshark的几种TCP Stream Graphs可视化统计信息含义，其中简单涉及发送、接收窗口、拥塞窗口，慢启动等机制。

自己实验构造了简单场景，并结合参考文章里的常见图形印证学习。

参考文章列表中有些实际案例，本篇暂未涉及，后续单独分析。

## 6. 参考

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

11、[在Wireshark的tcptrace图中看清TCP拥塞控制算法的细节(CUBIC/BBR算法为例)](https://blog.csdn.net/dog250/article/details/53227203)

12、[Understanding the tcptrace Time-Sequence Graph in Wireshark](https://packetbomb.com/understanding-the-tcptrace-time-sequence-graph-in-wireshark/)

13、GPT
