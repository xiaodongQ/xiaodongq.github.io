---
title: 实用工具集索引
description: 统一记录工具和小技巧，便于随时查找和使用
categories: [工具和命令, HandyTools]
tags: [Wireshark, eBPF, bcc, ss, bpftrace]
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

![TCP流图形tcptrace](/images/2024-07-01-wireshark-tcptrace.png)

示意图：

![tcp RTT图形](/images/2024-07-02-tcp-graph-rtt.png)

![tcp throughput图](/images/2024-07-02-tcp-graph-throughput.png)

![tcptrace图](/images/2024-07-02-tcp-graph-tcptrace.png)

![窗口规模变化图](/images/2024-07-02-tcp-graph-wnd-scaling.png)

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

## 4. eBPF：bcc tools、bpftrace

当前几个工具集里有些功能是重复的：`bcc tools`（也包括支持`CO-RE`的libbpf版本）、`bpftrace tools`，以平时使用的情况来看，原生安装的`bcc tools`/`bpftrace tools`通用性更好。自己归档的工具（[tools](https://github.com/xiaodongQ/prog-playground/tree/main/tools)）是基于较新的版本，里面有些实现要求更高的内核版本。

> 1）较高版本内核（比如5.10），尽量用新工具：libbpf版本更小、更快
>
> 2）较低版本内核，用默认安装版本（比如`yum instal`），或者去github仓库下载对应版本
{: .prompt-tip }

比如`bitesize`的使用对比：

```sh
# 1、自行编译的bcc tools libbpf版本，提示内核要求>=5.11.0（自己环境只是4.18.0-348.7.1.el8_5.x86_64）
[CentOS-root@xdlinux ➜ ~ ]$ which bitesize 
/home/workspace/bcc_20250315/libbpf-tools/bcc_libbpf-tools_bin_db5b63f/bitesize
[CentOS-root@xdlinux ➜ ~ ]$ bitesize
libbpf: prog 'block_rq_issue': BPF program load failed: -EACCES
libbpf: prog 'block_rq_issue': -- BEGIN PROG LOAD LOG --
arg#0 type is not a struct
Unrecognized arg#0 type PTR
; if (LINUX_KERNEL_VERSION >= KERNEL_VERSION(5, 11, 0))
...

# 2、自己基于github最近release的归档，也报错了。/home/workspace/prog-playground/tools/bpftrace-tools_v0.23.1
[CentOS-root@xdlinux ➜ bpftrace-tools_v0.23.1 git:(main) ✗ ]$ ./bitesize.bt 
./bitesize.bt:23:2-9: ERROR: Can not access field 'comm' on type '(ctx) struct _tracepoint_block_block_rq_issue *'. Try dereferencing it first, or using '->'
    @[args.comm] = hist(args.bytes);
    ~~~~~~~

# 3、yum安装的bcc tools则可运行
[CentOS-root@xdlinux ➜ bpftrace-tools_v0.23.1 git:(main) ✗ ]$ /usr/share/bcc/tools/bitesize
Tracing block I/O... Hit Ctrl-C to end.
^C
Process Name = kworker/11:1H
     Kbytes              : count     distribution
         0 -> 1          : 1        |****************************************|
         2 -> 3          : 1        |****************************************|
# 4、yum安装的bpftrace tools也可运行
[CentOS-root@xdlinux ➜ bpftrace-tools_v0.23.1 git:(main) ✗ ]$ /usr/share/bpftrace/tools/bitesize.bt 
Attaching 3 probes...
Tracing block device I/O... Hit Ctrl-C to end.
^C
I/O size (bytes) histograms by process name:

@[kworker/11:1H]: 
[0]                    1 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[1]                    0 |                                                    |
[2, 4)                 0 |                                                    |
```

### 4.1. Linux内核版本对BPF的支持情况

![linux_kernel_event_bpf](/images/linux_kernel_event_bpf.png)  

[eBPF学习实践系列（一） -- 初识eBPF](https://xiaodongq.github.io/2024/06/06/ebpf_learn/)

### 4.2. bcc tools

![bcc tools 2019](/images/bcc-tools-2019.png) 

下面几篇博客做了一些介绍：

* [eBPF学习实践系列（一） -- 初识eBPF](https://xiaodongq.github.io/2024/06/06/ebpf_learn/)
* 网络相关：[eBPF学习实践系列（二） -- bcc tools网络工具集](https://xiaodongq.github.io/2024/06/10/bcc-tools-network/)
* 内存相关：[CPU及内存调度（三） -- 内存问题定位工具和实验](https://xiaodongq.github.io/2025/04/02/memory-profiling-tools/#6-bcc-tools%E5%B7%A5%E5%85%B7)

自行编译了bcc libbpf版本，工具归档在：[tools](https://github.com/xiaodongQ/prog-playground/tree/main/tools)

### 4.3. bpftrace

bpftrace提供的追踪类型：

![bpftrace提供的追踪类型](/images/bpftrace_probes_2018.png)

介绍和工具使用，可见：[eBPF学习实践系列（六） -- bpftrace学习和使用](https://xiaodongq.github.io/2024/06/28/ebpf-bpftrace-learn/)

bpftrace-tools 自己也归档了一份便于统一使用：[tools](https://github.com/xiaodongQ/prog-playground/tree/main/tools)

### 4.4. 60s系列BPF版本

![bcc tools 60s](/images/ebpf_60s-bcctools2017.png)

### 4.5. 60s系列Linux命令版本

```sh
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

### 4.6. 查看eBPF自身的资源消耗

发现一个有意思的工具：[bpftop](https://github.com/Netflix/bpftop)，可以查看eBPF自身的消耗，还能够在时间序列图中显示统计数据。

工具由Netflix的工程师Jose Fernandez开源，基于Rust开发。作者对工具的介绍：[Announcing bpftop: Streamlining eBPF performance optimization](https://netflixtechblog.com/announcing-bpftop-streamlining-ebpf-performance-optimization-6a727c1ae2e5)

**使用方式**：项目地址中有已经打包好的release二进制文件，下载即可使用，**依赖glibc版本 >= GLIBC_2.29**。

直接执行，会展示当前生效的监测点列表和资源消耗总览；可选择某个监测点后回车，会用图表形式显示eBPF程序在该样本周期内的平均执行时间、每秒事件数和估算的CPU利用率。

![bpftop区间统计](/images/2025-04-15-bpftop.png)

也可参考：[eBPF实战教程七 -- 性能监控工具—bpftop](https://www.modb.pro/db/1846730191072227328)

## 5. perf-tools（ftrace和perf写的工具集）

![perf-tools工具集](/images/perf-tools_2016.png)

介绍可见：[eBPF学习实践系列（一） -- 初识eBPF](https://xiaodongq.github.io/2024/06/06/ebpf_learn/)。

### 5.1. perf使用示例

perf的使用，可以见Brendan Gregg大佬的网站：[perf Examples](https://www.brendangregg.com/perf.html)

### 5.2. funcgraph实践使用

追踪调用栈经验：结合`bpftrace`和`funcgraph`跟踪前后调用栈。

可见：

* [Linux存储IO栈梳理（二） -- Linux内核存储栈流程和接口：追踪工具说明](https://xiaodongq.github.io/2024/08/13/linux-kernel-fs/#42-%E8%BF%BD%E8%B8%AA%E5%B7%A5%E5%85%B7%E8%AF%B4%E6%98%8E)
* [Linux存储IO栈梳理（三） -- eBPF和ftrace跟踪IO写流程](https://xiaodongq.github.io/2024/08/15/linux-write-io-stack/)

## 6. 源码阅读分析：calltree.pl 和 cpptree.pl

有点像用户态的bpftrace+funcgraph，可以通过mode：0还是1控制查看的调用栈方向。

示例：  
![redis-replicaof-call-tree](/images/2025-03-30-redis-replicaof.png)

* 作者对工具的介绍：[C++阅码神器cpptree.pl和calltree.pl的使用](https://zhuanlan.zhihu.com/p/339910341)
* 自己的归档，里面也写了用法：[cpp-calltree](https://github.com/xiaodongQ/prog-playground/tree/main/tools/cpp-calltree)

使用到该工具：

* 查看调用栈：[Redis学习实践（三） -- 主从复制和集群](https://xiaodongq.github.io/2025/03/25/redis-cluster/#23-%E4%B8%BB%E5%BA%93%E5%BA%94%E7%AD%94%E5%A4%84%E7%90%86)
* 查看代码规模：[CPU及内存调度（四） -- ptmalloc、tcmalloc、jemalloc、mimalloc内存分配器（上）](https://xiaodongq.github.io/2025/04/04/memory-allocator/#32-dlmalloc%E8%AF%B4%E6%98%8E)

## 7. 命令和小技巧

### 7.1. ss 查看TCP信息、过滤端口

> 注意：需要依赖tcp_diag模块，缺少该模块会退化成netstat一样的方式读取/proc文件。lsmod没有则可`modprobe tcp_diag`加载。
{: .prompt-warning }

实用选项：

* `-o`：显示keepalive定时器
* `-i`：显示TCP信息详情，选项、拥塞算法、拥塞窗口、各类超时时间等
* `state xxx`：过滤TCP状态
* `dst :8008` 过滤目的端口（src则过滤源端口）
* 要过滤ip则要通过grep/awk匹配，ss里不支持选项过滤ip

```sh
# ss -o -i state established dst :8008  (-o显示keepalive定时器；-i展示tcp信息；state xxx不要放后面去了)
# 过滤目的端口8008的established连接
[root@localhost qxd]# ss -o -intp dst :8008|grep -v TIME-WAIT
State Recv-Q Send-Q         Local Address:Port            Peer Address:Port Process
ESTAB 0      0      [::ffff:192.168.1.62]:45038 [::ffff:192.168.1.220]:8008 users:(("java",pid=7870,fd=274))
         ts sack cubic wscale:7,7 rto:201 rtt:0.958/0.075 ato:40 mss:1448 pmtu:1500 rcvmss:536 advmss:1448 cwnd:185 ssthresh:132 bytes_sent:71412318 bytes_retrans:73848 bytes_acked:71338471 bytes_received:14550 segs_out:49431 segs_in:5428 data_segs_out:49428 data_segs_in:66 send 2236993737bps lastsnd:9 lastrcv:4 lastack:9 pacing_rate 2683692144bps delivery_rate 2122156352bps delivered:49429 busy:311ms retrans:0/51 dsack_dups:51 reordering:300 reord_seen:156 rcv_space:14480 rcv_ssthresh:64088 minrtt:0.047                                     
ESTAB 0      266148 [::ffff:192.168.1.62]:59606 [::ffff:10.12.152.253]:8008 users:(("java",pid=7870,fd=254)) timer:(on,004ms,0)
         ts sack cubic wscale:7,7 rto:201 rtt:0.889/0.061 ato:40 mss:1448 pmtu:1500 rcvmss:536 advmss:1448 cwnd:291 ssthresh:217 bytes_sent:201549420 bytes_retrans:503904 bytes_acked:200779369 bytes_received:40824 segs_out:139531 segs_in:36139 data_segs_out:139525 data_segs_in:185 send 3791838020bps lastrcv:3 pacing_rate 4547647888bps delivery_rate 3241453728bps delivered:139299 busy:964ms unacked:184 retrans:0/348 dsack_dups:305 reordering:300 reord_seen:13051 rcv_space:14480 rcv_ssthresh:64088 minrtt:0.044   
```

## 8. 扩展工具

### 8.1. gdb工具：pwndbg

梳理内存分配器时了解到的工具，试了下功能，效果很好。除了覆盖原有的gdb命令，还会显示对应的汇编，配色效果很炫，后续若学习汇编可以用起来。

`pwndbg（/paʊnˈdiˌbʌɡ/）`是一款基于 GDB 的 Python 调试工具，专为二进制漏洞利用和分析而设计，在 CTF（Capture The Flag）竞赛、漏洞研究以及二进制安全领域应用广泛。

项目仓库：[pwndbg](https://github.com/pwndbg/pwndbg)

**使用方式**：下载项目中打包好的release文件即可使用，如：`pwndbg_2025.02.19_x86_64-portable.tar.xz`。

和gdb一样使用，展示的信息很丰富，还有一些特定功能命令，比如`arena`查看堆区结构。各个部分可以和tmux配置结合，在不同的窗口展示。

![pwndbg-case](/images/2025-04-15-pwndbg-case.png)
