---
title: 实用工具集索引
description: 统一记录工具和小技巧，便于随时查找和使用
categories: [工具和命令, HandyTools]
tags: [Wireshark, eBPF, bcc, ss, bpftrace]
---

一些工具和小技巧，有时候要去翻历史博客或者重新搜索，此处进行归档索引，便于随时查找和使用。

![handy-tools.drawio](/images/handy-tools.drawio.svg)

## 1. Wireshark

### 1.1. 协议包示意图（Packet Diagram）

![协议示意图](/images/2024-05-29-protocol-diagram.png)

设置路径：在Wireshark中对照查看(**设置->Appearance->Layout->Pane3 选 Packet Diagram**)

使用示例，看协议代码时head和图印证：[TCP半连接全连接（一） -- 全连接队列相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/#63-%E6%8E%A5%E6%94%B6%E6%B5%81%E7%A8%8B)

### 1.2. TCP流统计图（TCP Stream Graphs）

几个图的说明示例可见：[TCP发送接收过程（一） -- Wireshark跟踪TCP流统计图](https://xiaodongq.github.io/2024/06/30/tcp-wireshark-tcp-graphs/)

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

### 1.4. 优化当前行背景颜色

默认情况下，当前行展示不大明显，可以如下设置。

![wireshark-current-line-backcolor](/images/wireshark-current-line-backcolor.png)

## 2. gperftools、火焰图

各类火焰图：On-CPU、Off-CPU、Wakeup、Off-Wake。

使用示例可见：[并发与异步编程（三） -- 性能分析工具：gperftools和火焰图](https://xiaodongq.github.io/2025/03/14/async-io-example-profile/)

火焰图还有下面介绍的 [Memory Leak and Growth火焰图](#33-memory-leak-and-growth火焰图)。

## 3. 内存相关profile

### 3.1. Valgrind Massif

使用实验可参考：[CPU及内存调度（三） -- 内存问题定位工具和实验](https://xiaodongq.github.io/2025/04/02/memory-profiling-tools)

### 3.2. AddressSanitizer 和 其他 Sanitizer工具

使用实验可参考：[CPU及内存调度（三） -- 内存问题定位工具和实验](https://xiaodongq.github.io/2025/04/02/memory-profiling-tools)

### 3.3. Memory Leak and Growth火焰图

[Memory Leak and Growth火焰图](https://www.brendangregg.com/FlameGraphs/memoryflamegraphs.html)

使用实验可参考：[CPU及内存调度（三） -- 内存问题定位工具和实验](https://xiaodongq.github.io/2025/04/02/memory-profiling-tools)

## 4. eBPF：bcc tools、bpftrace

当前几个工具集里有些功能是重复的：`bcc tools`（也包括支持`CO-RE`的libbpf版本）、`bpftrace tools`，以平时使用的情况来看，原生安装的`bcc tools`/`bpftrace tools`通用性更好。自己归档了一份工具便于统一使用（[tools](https://github.com/xiaodongQ/prog-playground/tree/main/tools)），是基于较新的版本，里面有些实现要求更高的内核版本。

> 1）较高版本内核（比如5.10），可以用新工具：libbpf版本更小、更快
>
> 2）较低版本内核，用默认安装版本（比如`yum install`），或者去github仓库下载对应版本
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

[eBPF学习实践系列（一） -- 初识eBPF](https://xiaodongq.github.io/2024/06/06/ebpf_learn/#22-ebpf%E5%86%85%E6%A0%B8%E7%89%88%E6%9C%AC%E6%94%AF%E6%8C%81%E5%8F%8A%E5%AE%9E%E7%94%A8%E5%B7%A5%E5%85%B7) 里简要说明了下。

### 4.2. bcc tools

![bcc tools 2019](/images/bcc-tools-2019.png) 

下面几篇博客做了一些介绍和实验：

* [eBPF学习实践系列（一） -- 初识eBPF](https://xiaodongq.github.io/2024/06/06/ebpf_learn/)
* 网络相关：[eBPF学习实践系列（二） -- bcc tools网络工具集](https://xiaodongq.github.io/2024/06/10/bcc-tools-network/)
* 内存相关：[CPU及内存调度（三） -- 内存问题定位工具和实验](https://xiaodongq.github.io/2025/04/02/memory-profiling-tools/#6-bcc-tools%E5%B7%A5%E5%85%B7)

自行编译了bcc libbpf版本，工具归档在：[tools](https://github.com/xiaodongQ/prog-playground/tree/main/tools)，其中的 bcc_libbpf-tools_bin_db5b63f.tar.xz 压缩包。基于 x86_64，gcc8.5.0，bcc commitid：db5b63ff876d3346021871e2189a354bfc6d510e，20250315才提交的，项目一直在更新，后续按需编译。

### 4.3. bpftrace

bpftrace提供的追踪类型：

![bpftrace提供的追踪类型](/images/bpftrace_probes_2018.png)

介绍和工具使用，可见：[eBPF学习实践系列（六） -- bpftrace学习和使用](https://xiaodongq.github.io/2024/06/28/ebpf-bpftrace-learn/)

bpftrace-tools 自己也归档了一份便于统一使用：[tools](https://github.com/xiaodongQ/prog-playground/tree/main/tools)，其中的bpftrace-tools_v0.23.1。

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

可了解：[eBPF学习实践系列（一） -- 初识eBPF](https://xiaodongq.github.io/2024/06/06/ebpf_learn/#222-perf-tools)。

### 5.1. perf使用示例

perf的使用，可以见Brendan Gregg大佬的网站：[perf Examples](https://www.brendangregg.com/perf.html)

### 5.2. funcgraph实践使用

追踪调用栈经验：结合`bpftrace`和`funcgraph`跟踪前后调用栈。

可见：

* [Linux存储IO栈梳理（二） -- Linux内核存储栈流程和接口：追踪工具说明](https://xiaodongq.github.io/2024/08/13/linux-kernel-fs/#42-%E8%BF%BD%E8%B8%AA%E5%B7%A5%E5%85%B7%E8%AF%B4%E6%98%8E)
* [Linux存储IO栈梳理（三） -- eBPF和ftrace跟踪IO写流程](https://xiaodongq.github.io/2024/08/15/linux-write-io-stack/)

## 6. 源码阅读分析：calltree.pl 和 cpptree.pl

追踪静态代码效果有点像用户态的bpftrace+funcgraph（追踪调用栈场景），可以通过mode：0还是1控制查看的调用栈方向。

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

### 7.2. 硬盘相关工具命令

下面工具只是主要关注了2个硬盘相关字段，还有很多其他信息。工具放在这里备用，用的时候能第一时间想起来。

lsblk、fdisk、smartctl、/sys/block文件系统、blockdev、lshw、hdparm

1、查看扇区：

```sh
# 1、lsblk
[root@localhost test]# lsblk /dev/sda -d -o NAME,PHY-SEC,LOG-SEC
NAME PHY-SEC LOG-SEC
sda     4096     512

# 2、fdisk -l
[root@localhost test]# fdisk -l /dev/sda | grep "Sector size"
Sector size (logical/physical): 512 bytes / 4096 bytes

# 3、smartctl
[root@localhost Service]# smartctl -a /dev/sda | grep "Sector Size"
Sector Sizes:     512 bytes logical, 4096 bytes physical

# 4、hdparm（不适用于NVME接口）
[root@localhost test]# hdparm -I /dev/sda | grep "Sector size"
        Logical  Sector size:                   512 bytes
        Physical Sector size:                  4096 bytes

# 5、/sys/block查看逻辑扇区大小（通常与文件系统相关）
[root@localhost test]# cat /sys/block/sda/queue/logical_block_size
512
# /sys/block查看物理扇区大小（磁盘硬件实际扇区）
[root@localhost test]# cat /sys/block/sda/queue/physical_block_size
4096

# 6、blockdev 查看逻辑扇区大小
[root@localhost test]# blockdev --getss /dev/sda
512
# blockdev 查看物理扇区大小
[root@localhost test]# blockdev --getpbsz /dev/sda
4096
```

2、是否SSD：

```sh
# 1、lsblk，ROTA 或者 MODEL型号判断
[root@localhost test]# lsblk -d -o NAME,ROTA,SIZE,MODEL
NAME    ROTA   SIZE MODEL
sda        1  18.2T xx20000NM002H-xxxx33
sdb        1  18.2T xx20000NM002H-xxxx33
sdy        0 476.9G xx512Gxxxxxx
nvme1n1    0 953.9G xx1Txxxxxxxx

# 2、/sys/block文件系统
[root@localhost test]# cat /sys/block/sda/queue/rotational
1

# 3、smartctl 有转速则为HDD
[root@localhost test]# smartctl -a /dev/sda | grep "Rotation Rate"
Rotation Rate:    7200 rpm

# 4、lshw
[root@localhost test]# lshw -class disk -short
H/W path             Device        Class          Description
=============================================================
/0/100/11.5/0.0.0    /dev/sdy      disk           512GB xx512Gxxxxxx
/0/100/1b/0/1        /dev/nvme0n1  disk           960GB NVMe disk
/0/100/1d/0/1        /dev/nvme1n1  disk           1024GB NVMe disk
/0/101/0/0.0.0       /dev/sdb      disk           20TB xx20000xxxxxx-3K
/0/101/0/0.1.0       /dev/sda      disk           20TB xx20000xxxxxx-3K
```

### 7.3. 网卡相关工具命令

1、`ethtool -S`查看统计信息，快速查看是否有网络瓶颈：`ethtool -S eth1 | grep -E "discard|error|drop"`

下面的网卡队列数和ring buffer数都会影响性能

2、`ethtool -l eth1`查看网卡队列数（每个队列都是缓存和管理网络数据包的独立通道），`ethtool -L`设置

多队列支持并发处理数据包，每个队列产生独立的中断（IRQ），可通过中断绑定（smp_affinity）分配到不同CPU核心。

```sh
[root@store test]# ethtool -l eth1
Channel parameters for eth1:
Pre-set maximums:
RX:             n/a
TX:             n/a
Other:          1
# 硬件支持的最大队列数（总队列数）（通常与CPU核心数相关）
Combined:       63
Current hardware settings:
RX:             n/a
TX:             n/a
Other:          1
# 当前启用的队列数
# 最佳实践：队列数应与处理网络中断的CPU核心数一致（例如：8队列绑定8个CPU）
Combined:       40
```

3、检查中断分配：`cat /proc/interrupts | grep eth1`，中断计数是否均衡在各个CPU上

```sh
# 设置网卡中断负载均衡。启用irqbalance服务 或者 手动绑定
# 在高吞吐量网络环境中，irqbalance可能会频繁调整中断分配，导致额外的开销，反而影响性能（NUMA、虚拟化环境、低延迟场景建议手动）
1. 遍历/sys/class/net/确定网卡
2. /proc/interrupts里是每个CPU的中断情况，grep网卡查看该网卡对应的中断
3. 从/proc/interrupts里过滤出该网卡对应的中断号列表
（中断号, CPU核心中断计数, 中断控制器类型, 中断触发方式, 设备或中断源名称）（类型列举：timer-系统定时器、rtc0-实时时钟、eth0-网卡、nvme0q0-NVMe硬盘队列、ahci-SATA控制器）
           CPU0       CPU1       CPU2       CPU3   ...   CPU14      CPU15
   0:         64          0          0          0  ...       0          0   PCI-MSI 12582912-edge      eth0
   8:          0          0          0          0  ...       0          0   PCI-MSI 12582913-edge      eth0-TxRx-0
4. 将中断号均衡绑定CPU。可每个中断号依次绑定不同CPU（比如：echo 1、echo 2、echo 4、echo 8到该网卡中断号列表，以达到均衡）
    将中断号为 100 的中断绑定到 CPU0 和 CPU1
    支持中断号绑定多个CPU，示例：echo 3 > /proc/irq/100/smp_affinity  # 3 = 二进制 00000011（CPU0 和 CPU1）
```

5、`ethtool -g eth1` 查看网卡环形缓冲区(ring buffer)大小（条目数），`-G`设置

```sh
# 环缓冲区过小会导致在高流量下数据包被丢弃，因为网卡来不及处理。
# 开销：每个缓冲区条目占用约 2KB 内存；增大缓冲区会轻微增加网络延迟，需权衡缓冲区大小与延迟
[root@store test]# ethtool -g eth1
Ring parameters for eth1:
Pre-set maximums:
RX:             4096
RX Mini:        n/a
RX Jumbo:       n/a
TX:             4096
Current hardware settings:
# RX 接收ring buffer数
RX:             512
RX Mini:        n/a
RX Jumbo:       n/a
# TX 发送ring buffer数
TX:             512
RX Buf Len:             n/a
TX Push:        n/a
```

6、`ethtool -k eth1` 查看网卡的卸载功能状态，包括RSS是否启用等

## 8. 扩展工具

### 8.1. C++工具：Compiler Explorer 和 C++ Insights

1、**Compiler Explorer**：[Compiler Explorer](https://godbolt.org/)

* 支持各类语言的编译（C++、go、rust...），选择不同编译器，设置不同选项，进行快速验证
* 还可以查看汇编输出

2、**C++ Insights**：[C++ Insights](https://cppinsights.io/)

* 理解编译器怎么处理代码的

### 8.2. 在线看内核代码：elixir.bootlin

[elixir.bootlin](https://elixir.bootlin.com/linux/v5.10.236/source)

支持函数及变量跳转，支持引用搜索，可灵活选择不同内核版本。

可避免需要查看内核代码时，每次要去打开工程的麻烦。用VS Code的话挺耗资源的，而且每次打开还要等加载代码目录。

### 8.3. gdb工具：pwndbg

梳理内存分配器时了解到的工具，试了下功能，效果很好。除了覆盖原有的gdb命令，还会显示对应的汇编，配色效果很炫，后续若学习汇编可以用起来。

`pwndbg（/paʊnˈdiˌbʌɡ/）`是一款基于 GDB 的 Python 调试工具，专为二进制漏洞利用和分析而设计，在 CTF（Capture The Flag）竞赛、漏洞研究以及二进制安全领域应用广泛。

项目仓库：[pwndbg](https://github.com/pwndbg/pwndbg)

**使用方式**：下载项目中打包好的release文件即可使用，如：`pwndbg_2025.02.19_x86_64-portable.tar.xz`。

和gdb一样使用，展示的信息很丰富，还有一些特定功能命令，比如`arena`查看堆区结构。各个部分可以和tmux配置结合，在不同的窗口展示。

![pwndbg-case](/images/2025-04-15-pwndbg-case.png)

### 8.4. 画图：draw.io 和 Excalidraw

* [Excalidraw](https://excalidraw.com/)
* [draw.io](https://app.diagrams.net/)

1、记录下draw.io常用组件的快捷键，用起来也比较丝滑，不过快捷键体验感比较好的还得是Excalidraw。

```
a: 文本
d: 方框
c: 箭头
f: 圆
r: 菱形
x: 自由绘制
```

2、draw.io 的几个亮点

* **动态流图**，即文章开头的动图效果
* 设置默认样式
* 配色比较美观

但注意默认样式只在本次有效，需要通过json保存修改配置。draw.io的可定制性很强，参考：[把 draw.io 装修为简单且现代的白板应用](https://www.sansui233.com/posts/2024-11-12-%E6%8A%8Adrawio%E8%A3%85%E4%BF%AE%E4%B8%BA%E7%AE%80%E5%8D%95%E7%BE%8E%E8%A7%82%E7%9A%84%E7%99%BD%E6%9D%BF%E5%BA%94%E7%94%A8)。
