---
title: 问题定位和性能优化案例集锦
description: 记录精彩的问题定位过程和性能优化手段，内化并能为自己所用。
categories: [Troubleshooting]
tags: [Troubleshooting]
pin: true
---

## 1. 背景

TODO List里面，收藏待看的文章已经不少了，有一类是觉得比较精彩的问题定位过程，还有一类是性能优化相关的文章，需要先还一些“技术债”了。

本篇将这些文章内容做简要分析，**作为索引供后续不定期翻阅**。另外，补充篇 [问题定位和性能优化案例集锦 -- 工具补充实验](https://xiaodongq.github.io/2025/04/18/excellent-trouble-shooting-tools/) 中会记录一些涉及的工具说明和实验记录。

这里再说说 **知识效率** 和 **工程效率**（具体见：[如何在工作中学习](https://plantegg.github.io/2018/05/23/%E5%A6%82%E4%BD%95%E5%9C%A8%E5%B7%A5%E4%BD%9C%E4%B8%AD%E5%AD%A6%E4%B9%A0/)，里面讲得非常好）：

> 有些人纯看理论就能掌握好一门技能，还能举一反三，这是知识效率，这种人非常少；
>
> 大多数普通人都是看点知识然后结合实践来强化理论，要经过反反复复才能比较好地掌握一个知识，这就是工程效率，讲究技巧、工具来达到目的。
{: .prompt-info }

以及 Brendan Gregg 大佬在《性能之巅：系统、企业与云可观测性》中对`已知的已知`、`已知的未知`、`未知的未知`表述的观点：

> 你了解的越多，就能意识到未知的未知就越多，然后这些未知的未知会变成你可以去查看的已知的未知。
>
>    <cite>—— Brendan Gregg, 《性能之巅：系统、企业与云可观测性》</cite>
{: .prompt-tip }

先知道、再结合实践来强化，并通过费曼学习法输出讲述出来，这是一种高效的学习，能让技术飞轮转动起来。

## 2. 问题定位案例

先列举，前面可能略显杂乱，依次消化后梳理。

### 2.1. Brendan Gregg的博客

[Brendan Gregg's Blog](https://www.brendangregg.com/blog/index.html)

里面有一些实际案例和场景介绍，对理解大佬开发的火焰图、bcc、perf-tools等一些工具的使用场景和灵活应用很有帮助，否则只是停留于知道层面。

#### 2.1.1. page占用很高

[Analyzing a High Rate of Paging](https://www.brendangregg.com/blog/2021-08-30/high-rate-of-paging.html)

问题：微服务管理上传大小文件（100 Gbytes、40 Gbytes），大文件要数小时，小文件只要几分钟。云端监测工具显示大文件时**page页占用很高**

* 先来60s系列性能检查：`iostat` **查看总体io占用情况**
    * 发现`r_await`读等待相对较高（写的话write-back模式有cache一般等待少），`avgqu-sz`平均队列长度不少在排队，io大小则是128KB（用`rkB/s`/`r/s`，即可查看读取的io块大小，比如4K、32K、128K等）
    * [60s系列Linux命令版本](https://xiaodongq.github.io/2025/04/14/handy-tools/#45-60s%E7%B3%BB%E5%88%97linux%E5%91%BD%E4%BB%A4%E7%89%88%E6%9C%AC)
* 检查硬盘延时：`biolatency`（bcc）
    * bcc工具检查总体的bio延时情况，大部分延时统计在`[16, 127 ms]`。判断是负载比较大，**排除是硬盘的异常**。
* 检查io负载情况：bitesize（bcc）
    * 上面判断负载大，于是`bitsize`看下**io负载分布情况**（会展示不同程序的各个读写IO区间的负载分布），没明显异常
* 继续60s系列性能检查：`free`（缓存）
    * free不多了，很多在`page cache`页面缓存里面（64GB内存，有48GB在page cache里）
    * 初步分析：对于48GB的page cache，**100GB的文件会破坏page cache，而 40GB 文件则适合**
* 缓存命中情况确认：`cachestat`（bcc和perf-tools里都有该工具）
    * 确实缓存命中率有很多比较低，造成了对硬盘io，延迟会比较大
* **解决方式**
    * 定位到问题原因就好解决了。1）最简单的是服务迁移到更大内存的示例上，满足100GB文件的缓存要求 2）重构代码以约束内存使用：分别处理文件各部分，而不是多次传输文件后一次性处理
    * 本案例问题的杀手锏是 `cachestat`

最终发现是大文件对应的page页缓存命中率很低：

```sh
# /apps/perf-tools/bin/cachestat
Counting cache functions... Output every 1 seconds.
    HITS   MISSES  DIRTIES    RATIO   BUFFERS_MB   CACHE_MB
    1811      632        2    74.1%           17      48009
    1630    15132       92     9.7%           17      48033
    1634    23341       63     6.5%           17      48029
    1851    13599       17    12.0%           17      48019
    1941     3689       33    34.5%           17      48007
    1733    23007      154     7.0%           17      48034
    1195     9566       31    11.1%           17      48011
[...]
```

#### 2.1.2. 其他博客内容

先列下面这些文章，还有很多内容值得一读和实验：

* [Linux ftrace TCP Retransmit Tracing](https://www.brendangregg.com/blog/2014-09-06/linux-ftrace-tcp-retransmit-tracing.html)
    * 用ftrace（perf-tools里面的`tcpretrans`）追踪TCP重传
    * 之前用tc构造过重传实验，不过用的是bcc tools里的`tcpretrans`。有一个差别是：**perf-tools中的`tcpretrans`可以追踪堆栈**。
        * 之前自己的bcc实验见：[eBPF学习实践系列（二） -- bcc tools网络工具集](https://xiaodongq.github.io/2024/06/10/bcc-tools-network/#38-tcpretrans%E9%87%8D%E4%BC%A0%E7%9A%84tcp%E8%BF%9E%E6%8E%A5%E8%B7%9F%E8%B8%AA)
* [perf sched for Linux CPU scheduler analysis](https://www.brendangregg.com/blog/2017-03-16/perf-sched.html)
    * 介绍`perf sched`追踪调度延迟和分布情况，bcc中提供的调度相关工具为：`runqlat`、`runqslower`、`runqlen`
* [Linux bcc/BPF Run Queue (Scheduler) Latency](https://www.brendangregg.com/blog/2016-10-08/linux-bcc-runqlat.html)
    * 关于延迟，这篇文章单独做了介绍，`runqlat`、`runqlat`
* [Linux bcc/eBPF tcpdrop](https://www.brendangregg.com/blog/2018-05-31/linux-tcpdrop.html)
    * 介绍通过`tcpdrop`追踪TCP丢包的原因（显示调用路径）
* [Poor Disk Performance](https://www.brendangregg.com/blog/2021-05-09/poor-disk-performance.html)
    * 跟踪一个读延迟很大的磁盘，结合`iostat` 和 bcc的`biolatency`工具，来检查延迟分布
        * `aqu-sz`队列不长，但是`r_await`读延迟很大，434.31ms，说明不是负载太高的原因，而是磁盘本身的问题
    * 以及通过bcc中的 `biosnoop` 来查看每个磁盘事件，可以看到这块盘的dd事件及其对应的延迟
* [Linux bcc tcptop](https://www.brendangregg.com/blog/2016-10-15/linux-bcc-tcptop.html)
    * 介绍 `tcptop` 查看当前TCP流量的统计情况，按大小排列
    * 之前在 [eBPF学习实践系列（二） -- bcc tools网络工具集](https://xiaodongq.github.io/2024/06/10/bcc-tools-network/#32-tcptop%E7%BB%9F%E8%AE%A1tcp%E5%8F%91%E9%80%81%E6%8E%A5%E6%94%B6%E7%9A%84%E5%90%9E%E5%90%90%E9%87%8F) 里也实验过了。
* [Linux bcc ext4 Latency Tracing](https://www.brendangregg.com/blog/2016-10-06/linux-bcc-ext4dist-ext4slower.html)
    * 使用 `ext4dist` 追踪ext4文件系统的操作延迟，`write`、`read`、`open`等操作
    * `ext4slower` 查看高延迟

以及几篇解释指标迷惑性的文章：

* [CPU Utilization is Wrong](https://www.brendangregg.com/blog/2017-05-09/cpu-utilization-is-wrong.html)
* [Linux Load Averages: Solving the Mystery](https://www.brendangregg.com/blog/2017-08-08/linux-load-averages.html)

[Latency Heat Maps](https://www.brendangregg.com/HeatMaps/latency.html)

* 介绍了**延迟热力图**
* 通过bcc的`biosnoop.py`，或者perf-tools里面的`iosnoop`（针对老版本内核用perf写的）采集，而后通过 [HeatMap](https://github.com/brendangregg/HeatMap) 生成热力图
* 实验下：
    * `/usr/share/bcc/tools/biosnoop > out.biosnoop`，用`stress -c 8 -m 4 -i 4`加点压力采集
    * `awk 'NR > 1 { print $1, 1000 * $NF }' out.biosnoop | /home/local/HeatMap/trace2heatmap.pl --unitstime=s --unitslabel=us --maxlat=2000 > out.biosnoop.svg`

生成的图长这样（可见[heatmap_sample实验归档](https://github.com/xiaodongQ/prog-playground/tree/main/heatmap_sample)）：  
![biosnoop-heatmap](/images/out.biosnoop.svg)

### 2.2. 软中断案例

[Redis 延迟毛刺问题定位-软中断篇](https://www.cyningsun.com/09-17-2024/redis-latency-irqoff.html)

问题：通过`业务监控系统`，发现线上Redis集群有延迟毛刺，出现的时间点不定，但大概每小时会有1次，每次持续大概10分钟

* **整个链路**是 Redis SDK -> Redis Proxy -> 各个Redis
    * PS：性能之巅中的建议 -- **性能分析时先画出架构链路图**
* 通过监控面板，查看 Redis Proxy 调 Redis 的链路，有毛刺
* eBPF 抓取 Redis 执行耗时并未发现慢速命令，说明并非是业务使用命令导致的。
    * **TODO：** eBPF检查应用程序的关键函数（uprobe？还可以offcputime检查fork、io等操作）
* 缩短问题链路：通过上2步，**问题范围缩小**到 Redis Proxy 调用 Redis 的链路，先聚焦**网络层面**
* 网络问题分析
    * 出现毛刺的时间点，`mtr`检查丢包和延时，一切正常
    * 检查问题集群的上层交换机，一切正常
    * 检查到某个主机的监控，有延迟情况
    * 发现该机器上 **rx 的`missed_errors`** 高
        * 是 `ethtool -S eno2 |grep rx |grep error` 展示的指标
    * 找一台机器调高 ring buffer 大小为 4096
        * 调整buffer方式：`ethtool -G <nic> rx 4096`
        * `ethtool -g eno2` 查看网卡队列长度
    * 持续观察一天，问题不再复现
* 网络团队判断是业务层有周期性阻塞性的任务，导致**软中断线程收包阻塞**，`rx drop`是因为软中断线程收包慢导致的。
    * 使用字节跳动团队的 [trace-irqoff](https://github.com/bytedance/trace-irqoff) 监控中断延迟
    * 在自己家里的机器上试了下好像没结果，后续按需使用。编译会生成一个`.ko`，`install`会加载到内核中。
* 问题确认和解决：经相关同事确认，故障出现的前一两天确实灰度了光模块监控，会通过定期逐个机器遍历远程调用 `ethtool -m` 读取光模块的信息。程序回滚之后问题恢复。
* 另外可`perf record -e skb:kfree_skb`检查丢包（也可利用各类eBPF工具）
    * 腾讯、字节等厂在此基础上进行了更加友好的封装：`nettrace`、`netcap`

`ifconfig`、`ethtool -S`统计信息示例，关注发送和接收的计数统计（非案例中的采集）：

```sh
# ifconfig统计的网口接收、发送包信息
[CentOS-root@xdlinux ➜ ~ ]$ ifconfig enp4s0
enp4s0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 192.168.1.150  netmask 255.255.255.0  broadcast 192.168.1.255
        ...
        RX packets 3424820  bytes 3773136623 (3.5 GiB)
        RX errors 0  dropped 300959  overruns 0  frame 0
        TX packets 1365612  bytes 142186791 (135.5 MiB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

# ethtool -S 统计信息，和上面的RX、TX相关信息是对应的
[CentOS-root@xdlinux ➜ ~ ]$ ethtool -S enp4s0
NIC statistics:
     tx_packets: 1365613
     rx_packets: 3424821
     tx_errors: 0
     rx_errors: 0
     rx_missed: 0
     ...
```

网络队列、ring buffer查看相关命令示例见：[实用工具集索引 -- 网卡相关工具命令](https://xiaodongq.github.io/2025/04/14/handy-tools/#73-%E7%BD%91%E5%8D%A1%E7%9B%B8%E5%85%B3%E5%B7%A5%E5%85%B7%E5%91%BD%E4%BB%A4)

另外发现博主的历史文章，也覆盖了之前看过的网络发送和接收文章翻译：

* [译｜Monitoring and Tuning the Linux Networking Stack: Receiving Data](https://www.cyningsun.com/04-24-2023/monitoring-and-tuning-the-linux-networking-stack-recv-cn.html#Receive-Packet-Steering-RPS)
* [译｜Monitoring and Tuning the Linux Networking Stack: Sending Data](https://www.cyningsun.com/04-25-2023/monitoring-and-tuning-the-linux-networking-stack-sent-cn.html)

关注的ArthurChiao's Blog中也做了翻译，排版更好一点：

* [[译] Linux 网络栈监控和调优：发送数据（2017）](https://arthurchiao.art/blog/tuning-stack-tx-zh/)
* [[译] Linux 网络栈监控和调优：接收数据（2016）](https://arthurchiao.art/blog/tuning-stack-rx-zh/)

### 2.3. Redis长尾延迟案例

其实是上面 “软中断篇” 的上篇：[记一次 Redis 延时毛刺问题定位](https://www.cyningsun.com/12-22-2023/redis-latency-spike.html)

问题：部分线上集群出现10分钟一次的耗时毛刺

* **整个链路**是 Redis SDK -> Redis Proxy -> 各个Redis
* 在 Redis Proxy 可以观察到明显的请求耗时毛刺，可以确定问题确实出现在 Redis Proxy 调用 Redis 的某个环节
    * 问题非必现，且不固定于某台机器
    * 问题发现时，相同/类似毛刺现象涉及众多集群
    * 在线的 Redis 版本缺少 P99 指标（耗时指标仅包括执行耗时，不包括包括等待耗时）耗时毛刺被平均之后无法观察到
* 定位
    * 基于现有指标缩小问题的范围，按可能性排查范围：业务请求 > 网络 > 系统 > 应用
        * 之前碰到过 `atop` 采集进程 `PSS` 导致延迟增加。此次停止所有 atop 之后，请求延迟消失。
        * **先说结论**，原因：线上部分机器部署的 atop 版本 默认启用了 `-R` 选项。**在 atop 读 /proc/${pid}/smaps 时，会遍历整个进程的页表，期间会持有内存页表的锁。如果在此期间进程发生虚拟内存地址分配，也需要获取锁，就需要等待锁释放。具体到应用层面就是请求耗时毛刺。**
    * 根因分析。可以看看里面的手段思路
        * 了解`smaps`中的内容和文件更新原理，proc使用的文件类型是`seq_file`序列文件。
            * `smaps` 文件包含了每个进程的内存段的详细信息，包括但不限于各段的大小、权限、偏移量、设备号、inode 号以及最值得注意的——各段的 `PSS（Proportional Set Size，比例集大小）`和 `RSS（Resident Set Size，常驻集大小）`。（针对多进程共享内存的场景，`PSS`的物理内存统计比`RSS`更为准确）。
            * 关于序列文件，之前梳理netstat的实现流程中也涉及了。其读取proc文件系统的`/proc/net/tcp`就是用的序列文件，其简要流程可见：[分析netstat中的Send-Q和Recv-Q](https://xiaodongq.github.io/2024/05/27/netstat-code/#3-procnettcp%E6%96%87%E4%BB%B6%E6%9B%B4%E6%96%B0%E9%80%BB%E8%BE%91) 
        * **耗时定位思路**说明：进程耗时分2大部分：**用户空间** 和 **内核空间** 的耗时
            * 在缺乏统计系统和百分位延时指标时，`用户空间`的耗时，可以使用bcc的 `funcslower`（示例实验见补充文章）
            * `内核空间`耗时，可选工具：
                * bcc的`syscount`，syscount 并不能直接查看调用层级，但可以通过对比不同时间区间的延迟变化发现问题，可指定进程。
                * `perf trace`：相较于 syscount 提供了 histogram 图，**可以直观的发现长尾问题**（示例实验见补充文章）
            * 然后，可进一步使用perf-tools的 `funcgraph` 定位到耗时异常的函数
        * `smaps`序列文件对应 `seq_file` 的操作，由 `seq_operations` 定义读取进程数据的操作
            * `pid_smaps_open`打开、`seq_read`读取
            * 读取时，会调用`mmap_read_lock_killable`给整个`mm`结构体加锁，在读取结束时，m_stop会调用`mmap_read_unlock`解锁
                * 即 `mmap_sem`，里面是一个和VMA相关的读写锁：`struct rw_semaphore`
            * 上述用到的锁结构是`mmap_lock`，该**锁的粒度很大**，当进程发生 `VMA`（虚拟内存区） 操作都需要持有该锁，如内存分配和释放。
                * 遍历 VMA 耗时：如果进程的内存比较大，就会长时间持有该锁，影响进程的内存管理。
            * `syscount -L -i 30 -p $PID` 抓取问题前后`mmap`的耗时变化，**问题发生时mmap耗时 177 ms**
                * `SYSCALL      COUNT        TIME (us)`
                * `mmap          1           11.003` （时间点 [21:39:27]）
                * `mmap          1       177477.938` （时间点 [21:40:14]）
        * 其他方式继续追踪佐证
            * `perf trace -p $PID -s` 追踪
            * `funcgraph`追踪
            * `bpftrace -e 'tracepoint:mmap_lock:mmap_lock_start_locking /args->write == true/{ @[comm, kstack] = count();}'`
                * 不需要记住，需要时`perf list`过滤查看具体的追踪点
                * PS：自己4.18的内核环境里面，貌似没有`mmap_lock`这个tracepoint了

看下自己机器上 smaps内容 和 maps内容的示例（更多一点的信息可以看本文的补充篇）：

```sh
# smaps内容
[CentOS-root@xdlinux ➜ ~ ]$ cat /proc/$(pidof mysqld)/smaps
# 该内存段的虚拟地址范围，smaps里有很多段范围信息
# r-xp 是权限标志；00000000：偏移量，表示文件映射到内存中的偏移位置
# fd:00：设备号，fd 是主设备号，00 是次设备号；136301417：inode号，标识文件
# /usr/libexec/mysqld：内存映射的文件路径
55a5d35ad000-55a5d70ba000 r-xp 00000000 fd:00 136301417                  /usr/libexec/mysqld
# 内存段的总大小，包括未使用的部分
Size:              60468 kB
# KernelPageSize 和 MMUPageSize，是 内核和硬件 MMU（内存管理单元）支持的页面大小，通常为 4 KB
KernelPageSize:        4 kB
MMUPageSize:           4 kB
# Resident Set Size，常驻物理内存
Rss:               28692 kB
# Proportional Set Size，按比例分配的内存大小。此处和Rss一样，说明没有共享内存
Pss:               28692 kB
...
...

# maps内容
[CentOS-root@xdlinux ➜ ~ ]$ cat /proc/$(pidof mysqld)/maps
55a5d35ad000-55a5d70ba000 r-xp 00000000 fd:00 136301417                  /usr/libexec/mysqld
55a5d70ba000-55a5d722f000 r--p 03b0c000 fd:00 136301417                  /usr/libexec/mysqld
55a5d722f000-55a5d75b6000 rw-p 03c81000 fd:00 136301417                  /usr/libexec/mysqld
...
55a5d7f4e000-55a5da7d0000 rw-p 00000000 00:00 0                          [heap]
...
```

### 2.4. 进程调度案例

[阴差阳错｜记一次深入内核的数据库抖动排查](https://zhuanlan.zhihu.com/p/14709946806?utm_campaign=shareopn&utm_medium=social&utm_psn=1889473112485106949&utm_source=wechat_session)

问题：

* 分布式关系型数据库（C++），一个集群有多个节点，跑在k8s上。这个业务各个pod所在的宿主机正好都只分配了1个pod，且已经做了CPU绑核处理，照理说应该非常稳定。
    * 集群之所以进行CPU绑核，就是因为之前定位过另一个抖动问题：在未绑核的情况下，很容易触发cgroup限流（可了解 [Kubernetes迁移踩坑：CPU节流](https://zhuanlan.zhihu.com/p/60199662)）
* 但每天都会发生1-2次抖动。现象是：不论读请求还是写请求，不管是处理用户请求的线程还是底层raft相关的线程，都hang住了数百毫秒
* 慢请求日志里显示处理线程没有suspend，`wall time`很大，但真正耗费的`CPU time`很小；
* 且抖动发生时不论是容器还是宿主机，CPU使用率都非常低。

分析和定位：

* 有了上次的踩坑经验（CPU绑核避免cgroup限流），这次第一时间就怀疑是内核调度的锅。
* 写了一个简单的ticker，不停地干10ms活再sleep 10ms，一个loop内如果总耗时>25ms就认为发生了抖动，输出一些CPU、调度的信息。
* 容器和宿主机、绑核和不绑核的各种组合场景运行，都有不同程度的抖动
    * 其中 “ticker运行在容器内，绑核” 是最抖的，调度延迟经常>5ms，但抖动的频率远高于我们的数据库进程，而抖动幅度又远小于，还是不太相似。
* 还是从应用进程入手，让GPT写了个脚本，在容器内不停地通过`perf sched`抓取操作系统的调度事件，然后等待抖动复现。
    * 复现后利用`perf sched latency`看看各个线程的调度延迟以及时间点 （`perf sched`实验可见补充文章）
    * `:211677:211677        |    160.391 ms |     2276 | avg:    2.231 ms | max:  630.267 ms | max at: 1802765.259076 s`
    * `:211670:211670        |    137.200 ms |     2018 | avg:    2.356 ms | max:  591.592 ms | max at: 1802765.270541 s`
    * 这俩的max at时间点是接近的，max抖动的值和数据库的慢请求日志也能对上。**说明数据库的抖动就是来自于内核调度延迟**
    * 根据max at的时间点在`perf sched script`里找原始的事件，下面贴了perf sched结果
        * tid 114把tid 115唤醒了（在075核上），但过了500+ms后，009核上的tid 112运行完才再次调度tid 115
        * 这意味着009核出于某些原因一直不运行tid 115
        * 再往前看看009这个核在干嘛，发现一直在调度时间轮线程
    * 猜测
        * TimeWheel由于干的活非常轻(2us)，sleep时间(1ms)相对显得非常大，于是vruntime涨的很慢
        * 由于调度，rpchandler线程到了TimeWheel所在的核上，它的vruntime在新核上属于很大的
        * cfs调度器倾向于一直调度TimeWheel线程
* 容器里抓取内容缺少部分事件，无法实锤，在宿主机抓取`perf sched`
    * `rpchandler 211677 [067] 1889343.661328:       sched:sched_switch: rpchandler:211677 [120] T ==> swapper/67:0 [120]`
    * `swapper     0 [067] 1889344.350873:       sched:sched_wakeup: rpchandler:211677 [120] success=1 CPU:067`
    * 发现某次切出后过了`689ms`才被swapper唤醒，和数据库观测到的延迟吻合
        * 注意到211677是**以`T`状态切出**的，这个状态的意思是 *stopped by job control signal*，也就是**有人给线程发SIGSTOP信号**。收到这个信号的线程会被暂停，直到之后收到`SIGCONT`信号才会继续运行。
        * 可以推断有个什么外部进程在给所有线程发信号，用来抓取某些信息。结合之前cgroup限流的知识，很有可能就是这个进程发送了`SIGSTOP`后正好用尽了时间片被cfs调度器切出，过了**几百毫秒**后才重新执行，发送了`SIGCONT`信号。
    * **在这个时间点附近观察有没有什么可疑的进程**，同事很快锁定了其中一个由安全团队部署的插件，因为在内网wiki里它的介绍是：**进程监控**
* **根因定位及确认**
    * 试着关闭了该组件，抖动消失了
    * 询问安全团队该插件是否有发送`SIGSTOP`的行为，得到的答复是没有。用`bpftrace`追踪了`do_signal`，也**并没有捕获到SIGSTOP信号**
    * 进一步从安全团队了解到该插件会利用`/proc`伪文件系统定时扫描宿主机上所有进程的cpuset、comm、cwd等信息，需要排查具体是插件的哪个行为导致了抖动
        * 安全团队修改代码，让插件记录每个扫描项的开始时间和结束时间，输出到日志中。这样数据库发生抖动后，我们只要对比扫描时间和抖动时间，就能锁定是哪个扫描项。
        * 但好几天都没发生抖动，**看来获取时间以及输出日志破坏了抖动的触发场景**
        * 不过从日志中我们发现读取`/proc/pid/environ`的耗时经常抖动至**几百ms**，非常可疑
        * 还原并进行对比测试：去掉日志，把机器分为两组：第1组只扫描environ，第2组只去掉environ。第1组发生了抖动，而第2组则岁月静好
        * 于是 **明确是读取`/proc/pid/environ`导致的抖动**。
    * 但仍然疑点重重：扫描`/proc/pid/environ`为什么会导致抖动？扫描`environ`为什么会导致线程处于`T`状态？
        * 既然没有证据表明有人发`SIGSTOP`，那么还能让这么多线程同时挂起的只有**锁**了
        * 查询资料发现读取`/proc/pid/environ`序列文件时，会有锁
            * 即 `mmap_sem`，里面是一个和VMA相关的读写锁：`struct rw_semaphore`。粒度很大，facebook的安全监控读environ的时候加mmap_sem读锁成功，然后由于时间片用完被调度出去了。而数据库运行过程中需要加写锁，就block住了，并且之后的读锁也都会被block，直到安全监控重新调度后释放了读锁。
            * 对应内核代码：[proc base.c](https://elixir.bootlin.com/linux/v4.18/source/fs/proc/base.c#L887)
            * **和上面 [Redis长尾延迟案例](#23-redis长尾延迟案例) 中读取`/proc/pid/smaps` 类似，都是读取proc文件系统内容加锁！**
        * 尝试在测试环境复现一下
            * 实现一个持续读取数据库进程environ的程序
            * 利用cgroup给它CPU限额至一个较低的值（单核的3%）
            * 结果：果然数据库频繁发生100ms以上的抖动，1分钟大概会出现2次。如果把CPU限额取消，即使该程序疯狂读取environ、跑满了CPU，数据库也没有任何抖动
            * 找到了稳定复现的方式，问题就不难排查了
    * 找哪个路径会对 `mmap_sem` 加写锁，利用perf-tools里的 `functrace` 很轻易的找到了`::write`会调用`down_write`
        * `functrace`可以快速追踪到谁调用到了指定函数，很多地方会调用`down_write`，可以指定进程`./functrace -p 1216 down_write`
        * 要查看完整调用栈的话则可以用`bpftrace`来追踪
            * 到tracing文件系统里过滤`down_write`，没有tracepoint但可以追踪kprobe（/sys/kernel/tracing/available_filter_functions）
            * bpftrace过滤pid追踪：`bpftrace -e 'kprobe:down_write /pid==1216/  {printf("comm:%s, \nkstack:%s\n", comm, kstack)}'`
        * functrace结果中调用down_write的线程，恰好就是数据库的raft线程，它在落盘raft log时需要调用::write与::sync
    * 还有一个问题没解决：为啥perf sched显示数据库线程是T状态切出的
        * 写bpftrace脚本，追踪tracepoint：`sched:sched_switch`，以及kprobe：`finish_task_switch`、`prepare_to_wait_exclusive`
        * 追踪到状态显示在这个内核版本是不对的，新内核中依旧修改了

参考链接对应的sched跟踪信息：

```sh
$ perf sched latency
...
  :211677:211677        |    160.391 ms |     2276 | avg:    2.231 ms | max:  630.267 ms | max at: 1802765.259076 s
  :211670:211670        |    137.200 ms |     2018 | avg:    2.356 ms | max:  591.592 ms | max at: 1802765.270541 s
...

$ perf sched script
# 结果截取
# tid 114把tid 115唤醒了（在075核上），但过了500+ms后，009核上的tid 112运行完才再次调度tid 115。
# 这意味着009核出于某些原因一直不运行tid 115
rpchandler   114 [011] 1802764.628809:       sched:sched_wakeup: rpchandler:211677 [120] success=1 CPU:075
rpchandler   112 [009] 1802765.259076:       sched:sched_switch: rpchandler:211674 [120] T ==> rpchandler:211677 [120]
rpchandler   115 [009] 1802765.259087: sched:sched_stat_runtime: comm=rpchandler pid=211677 runtime=12753 [ns] vruntime=136438477015677 [ns]
```

再往前看看009这个核在干嘛，发现一直在调度时间轮线程（每次TimeWheel `2us`，sleep时间`1ms`）：

```sh
 TimeWheel.Routi    43 [009] 1802765.162014: sched:sched_stat_runtime: comm=TimeWheel.Routi pid=210771 runtime=2655 [ns] vruntime=136438438256234 [ns]
 TimeWheel.Routi    43 [009] 1802765.162015:       sched:sched_switch: TimeWheel.Routi:210771 [120] D ==> swapper/9:0 [120]
         swapper     0 [009] 1802765.163067:       sched:sched_wakeup: TimeWheel.Routi:210771 [120] success=1 CPU:009
         swapper     0 [009] 1802765.163069:       sched:sched_switch: swapper/9:0 [120] S ==> TimeWheel.Routi:210771 [120]
 TimeWheel.Routi    43 [009] 1802765.163073: sched:sched_stat_runtime: comm=TimeWheel.Routi pid=210771 runtime=4047 [ns] vruntime=136438438260281 [ns]
 TimeWheel.Routi    43 [009] 1802765.163074:       sched:sched_switch: TimeWheel.Routi:210771 [120] D ==> swapper/9:0 [120]
         swapper     0 [009] 1802765.164129:       sched:sched_wakeup: TimeWheel.Routi:210771 [120] success=1 CPU:009
         swapper     0 [009] 1802765.164131:       sched:sched_switch: swapper/9:0 [120] S ==> TimeWheel.Routi:210771 [120]
 TimeWheel.Routi    43 [009] 1802765.164135: sched:sched_stat_runtime: comm=TimeWheel.Routi pid=210771 runtime=3616 [ns] vruntime=136438438263897 [ns]
 TimeWheel.Routi    43 [009] 1802765.164137:       sched:sched_switch: TimeWheel.Routi:210771 [120] D ==> swapper/9:0 [120]
         swapper     0 [009] 1802765.165187:       sched:sched_wakeup: TimeWheel.Routi:210771 [120] success=1 CPU:009
         swapper     0 [009] 1802765.165189:       sched:sched_switch: swapper/9:0 [120] S ==> TimeWheel.Routi:210771 [120]
```

宿主机抓的sched事件：

```sh
rpchandler 211677 [067] 1889343.661328:       sched:sched_switch: rpchandler:211677 [120] T ==> swapper/67:0 [120]
swapper     0 [067] 1889344.350873:       sched:sched_wakeup: rpchandler:211677 [120] success=1 CPU:067
```

```c
// linux-5.10.10/fs/proc/base.c
static const struct file_operations proc_environ_operations = {
	.open		= environ_open,
	.read		= environ_read,
	.llseek		= generic_file_llseek,
	.release	= mem_release,
};
```

### 2.5. eBPF辅助案例

* [eBPF/Ftrace 双剑合璧：no space left on device 无处遁形](https://mp.weixin.qq.com/s/VuD20JgMQlbf-RIeCGniaA)
    * 问题：生产环境中遇到了几次创建容器报错 ”no space left on device“ 失败，但排查发现磁盘使用空间和 inode 都比较正常
    * 定位：
        * 拿报错信息在内核中直接搜索
        * 利用bcc tools提供的 **`syscount`**（ubuntu上是`syscount-bpfcc`），基于错误码来进行系统调用过滤
        * `syscount-bpfcc -e ENOSPC --ebpf` 指定错误码，**初步确定了 dokcerd 系统调用 `mount` 的返回 ENOSPC 报错**
            * `mount`中的实现，会调用：`__arm64_sys_mount`（arm平台）
        * 而后利用perf-tools提供的 **`funcgraph`，跟踪内核函数的调用子流程**
            * `./funcgraph -m 2 __arm64_sys_mount`，限制堆栈层级
            * 在内核函数调用过程中，如果遇到出错，一般会直接跳转到错误相关的清理函数逻辑中（不再继续调用后续的子函数），这里我们可将注意力从 __arm64_sys_mount 函数转移到尾部的内核函数 `path_mount` 中重点分析。
        * 通过bcc tools提供的 **`trace`（ubuntu上是trace-bpfcc） 获取整个函数调用链的返回值**（上述`path_mount`的子流程都进行监测）
            * 跟踪到其中`count_mounts`的返回值 0xffffffe4 转成 10 进制，则正好为 -28（0x1B)，= -ENOSPC（28）
        * 进一步分析`count_mounts`的源码确定到了原因：确定是当前namespace中加载的文件数量超过了系统所允许的`sysctl_mount_max`最大值
    * 在根源定位以后，将该值调大为默认值 100000，重新 docker run 命令即可成功。

* [【BPF网络篇系列-2】容器网络延时之 ipvs 定时器篇](https://www.ebpf.top/post/ebpf_network_kpath_ipvs/)
    * kubernetes 底层负载均衡 ipvs 模块导致的网络抖动问题。
    * 问题：容器集群中新部署的`服务A`，通过服务注册发现访问下游`服务B`，调用延时 999 线偶发抖动，测试 QPS 比较小，从业务监控上看起来比较明显，最大的延时可以达到 200 ms。
        * 服务间的访问通过 gRPC 接口访问，节点发现基于 consul 的服务注册发现。
    * 定位
        * 初步定位：在服务 A 容器内的抓包分析和排查，服务A在其他ECS部署也没有改善，逐步把**范围缩小至服务 B 所在的主机上的底层网络抖动**
        * 经过多次 ping 包测试，寻找到了某台主机 A 与 主机 B 两者之间的 **ping 延时抖动与服务调用延时抖动规律比较一致**，由于 ping 包 的分析比 gRPC 的分析更加简单直接，因此我们**将目标转移至底层网络的 ping 包测试的轨道上**。
        * 在 ping 测试过程中分别在主机 A 和主机 B 上使用 tcpdump 抓包分析，发现在主机 B 上的 eth1 与网卡 cali95f3fd83a87 之间的延时达 `133 ms`。
            * 到此为止问题已经逐步明确，在主机 B 上接收到 ping 包在转发过程中有 100 多ms 的延时，那么**是什么原因导致的 ping 数据包在主机 B转发的延时呢？**
            * **网络数据包内核中的处理流程**：数据 -> 网卡DMA数据到`Ring Buffer` -> 网络设备驱动发起硬中断通知CPU（中断处理函数即`ISR，Interrupt Service Routines`） -> CPU发起软中断 -> `ksoftirqd`线程处理软中断，从Ring Buffer收包 -> 帧数据保存为一个skb -> 网络协议层处理，处理后数据放到socket的接收队列 -> 内核唤醒用户进程
            * 之前自己也基于几篇参考链接梳理过，可见：[TCP发送接收过程（一） -- Wireshark跟踪TCP流统计图](https://xiaodongq.github.io/2024/06/30/tcp-wireshark-tcp-graphs/)
        * 这里用了个基于bcc写的工具：[traceicmpsoftirq.py](https://gist.github.com/theojulienne/9d78a0cb68dbe56f19a2ae6316bc6846)，跟踪ping时的中断情况
            * 使用bcc里面的`trace`追踪`icmp_echo`的效果也差不多（可到`/proc/kallsyms`里过滤icmp相关的符号）
            * 从主机 A ping `主机B中容器IP` 的地址，每次处理包的处理都会固定落到 `CPU#0` 上
            * 出现延时的时候该 CPU#0 都在运行软中断处理内核线程 `ksoftirqd/0`，即在处理软中断的过程中调用的数据包处理，软中断另外一种处理时机如上所述 irq_exit 硬中断退出时；
            * 通过实际的测试验证，ping `主机B宿主机IP` 地址时候，全部都落在了 `CPU#19` 上。
        * 而后重点开始排查 CPU#0 上的 CPU 内核态的性能指标，看看是否有运行的函数导致了软中断处理的延期。
            * `perf top -C 0 -U` 查看CPU0
            * 并采集CPU0的火焰图
            * 注意到 CPU#0 的内核态中，`estimation_timer` 这个函数的使用率一直占用比较高，同样我们通过对于 CPU#0 上的火焰图分析，也基本与 perf top 的结果一致。
        * 用perf-tools的 `funcgraph` 分析函数 estimation_timer 在内核中的调用关系图和占用延时
            * `funcgraph -m 1 -a -d 6 estimation_timer`
            * 注意到 estimation_timer 函数在 CPU#0 内核中的遍历一次遍历时间为 119 ms，在内核处理软中断的情况中占用过长的时间，这一定会影响到其他软中断的处理。
            * PS：自己的环境4.18.0-348.7.1.el8_5.x86_64里，/proc/kallsyms里已经没有`estimation_timer`符号了
        * 进一步用bcc的`softirqs`，查看CPU0的软中断延时分布
            * `/usr/share/bcc/tools/softirqs -d  10 1 -C 0`
            * 通过 timer 在持续 10s 内的 timer 数据分析，我们发现执行的时长分布在 [65 - 130] ms区间的记录有 5 条。这个结论完全与通过 funcgraph 工具抓取到的 estimation_timer 在 CPU#0 上的延时一致。
        * **原因确认**：去分析 ipvs 相关的源码，使用 `estimation_timer` 的场景
            * 从 estimation_timer 的函数实现来看，会首先调用 spin_lock 进行锁的操作，然后遍历当前 Network Namespace 下的全部 ipvs 规则。由于我们集群的某些历史原因导致生产集群中的 Service 比较多，因此导致一次遍历的时候会占用比较长的时间。
            * 既然每个 Network Namespace 下都会有 estimation_timer 的遍历，为什么只有 CPU#0 上的规则如此多呢？
            * 这是因为只有主机的 Host Network Namespace 中才会有全部的 ipvs 规则，这个我们也可以通过 ipvsadm -Ln (执行在 Host Network Namespace 下) 验证。
            * 从现象来看，CPU#0 是 ipvs 模块加载的时候用于处理宿主机 Host Network Namespace 中的 ipvs 规则，当然这个核的加载完全是随机的。
    * 解决
        * 为了保证生产环境的稳定和实施的难易程度，最终我们把眼光定位在 Linux Kernel 热修的 `kpatch` 方案上，`kpath` 实现的 `livepatch` 功能可以实时为正在运行的内核提供功能增强，无需重新启动系统。（**`kpatch`热修复，留个印象**）

trace追踪示例，在另一台机器ping即可看到本机处理对应中断的CPU：

```sh
[CentOS-root@xdlinux ➜ tools ]$ /usr/share/bcc/tools/trace icmp_echo
PID     TID     COMM            FUNC             
0       0       swapper/15      icmp_echo        
0       0       swapper/15      icmp_echo        
0       0       swapper/15      icmp_echo        
0       0       swapper/15      icmp_echo        
0       0       swapper/15      icmp_echo
```

* [【BPF网络篇系列-1】k8s api-server slb 异常流量定位分析](https://www.ebpf.top/post/ebpf_network_traffic_monitor/)
    * 问题：k8s集群近期新增服务后，某天SLB（Server Load Balancing，服务负载均衡）告警出现了流量丢失
    * 定位：
        * 首先第一步需要确定丢包时刻出口流量流向何处，使用了 `iftop` 工具（其底层基于 `libpcap` 的机制实现）
            * `iftop -n -t -s 5 -L 5` // -s 5 5s 后退出， -L 5 只打印最大的 5 行
        * 由于 SLB 流量抖动时间不固定，因此需要通过定时采集的方式来进行流量记录，然后结合 SLB 的流量时间点进行分析
            * `iftop -nNB -P -f "tcp port 6443" -t -s 60 -L 100 -o 40s`，-P显示统计中的流量端口，-o 40s 按照近 40s 排序
        * 发现在 SLB 流量高峰**出现丢包的时候，数据都是发送到 kube-proxy 进程**，由于集群规模大概 1000 台左右，在集群 Pod 出现集中调度的时候，会出现大量的同步事件
            * 通过阅读 kube-proxy 的源码，得知 kube-proxy 进程只会从 kube-apiserver 上**同步 service 和 endpoint 对象**
            * 在该集群中的 Service 对象基本固定，那么在高峰流量期同步的必然是 **endpoint 对象**。
    * 原因：
        * SLB 高峰流量时间点正好是我们一个离线服务 A 从混部集群中重新调度的时间，而该服务的副本大概有 1000 多个。
        * 服务 A 需要跨集群重新调度的时候（即使通过了平滑调度处理）由于批量 Pod 的频繁创建和销毁， endpoint 的状态更新流量会变得非常大，从而导致 SLB 的流量超过带宽限制，导致流量丢失。
    * **iftop 和 tcptop 性能对比**
        * 考虑到 libpcap 的获取包的性能，决定采用 iperf 工具进行压测，使用`iperf3`打流并开着`iftop`监控。
            * 服务端绑核到15核上，`taskset -c 15 iperf3 -s`
            * 客户端绑到14核，`taskset -c 14 iperf3 -c 127.0.0.1 -t 120`
            * 用pidstat、top查看`iftop`的资源消耗（`top -p $(pidof iftop)`、`pidstat -p $(pidof iftop) 1`）
            * 结果：pidstat 分析 iftop 程序的 CPU 的消耗，发现主要在 %system ，大概 50%，%user 大概 20%。 在 16C 的系统中，占用掉一个核，占用资源不到 5%，生产环境也是可以接受。
        * bcc中的`tcptop`，同样用`iperf3`打流，查看资源使用情况
            * 避免了每个数据包从内核传递到用户空间（`iftop` 中为 256个头部字节）
            * `pidstat -p 11264  1`查看，%user %system 基本上都为 0
            * `tcptop` 的数据统计和分析的功能**转移到了内核空间的 BPF 程序中，用户空间只是定期负责收集汇总的数据**，从整体性能上来讲会比使用 `libpcap` 库（底层采用 cBPF）**采集协议头数据（256字节）通过 mmap 映射内存的方式传递到用户态**分析性能更加高效。

* [一次使用 ebpf 来解决 k8s 网络通信故障记录](https://mp.weixin.qq.com/s/cK8Ffhr2M6okysu-_iI6jg)
    * 场景问题：网络方案使用的是 Flannel VXLAN 覆盖网络，发送一些数据到对端的 vxlan 监听的 8472 端口，是可以抓到包的，说明网络链路是通的。但是vxlan 发送的 udp 包对端却始终收不到
    * 定位：
        * 找到其中一个 vxlan 包来手动发送：
            * 使用 nc 手动发送，通过抓包确认对端没有收到，
            * 但是随便换一个内容（里面是普通 ascii 字符串）发送，对端是可以立刻抓到包的。
        * 通过分析分析两边的丢包（使用 dropwatch、systemtap 等工具），并没有看到 udp 相关的丢包，因此推断问题可能出现在了 vxlan 包的特点上，大概率是被中间交换机等设备拦截。
        * 拦截设备如何可以精准识别 vxlan 的包？查看rfc了解 vxlan 的特征
            * 可以知道 vxlan 包的包头是固定的 0x08，中间交换机大概率是根据这个来判断的
            * 于是初步的测试，把一直发送不成功的包，稍微改一下。
            * 只改了一个字节，对端就能收到了，vxlan 的 flag 也变为了 0x88
    * 解决方式可选
        * 联系客户处理、切换k8s网路模型、使用iptables或eBPF来hack修改
    * 说下**hack方式**：使用rust aya来快速开发eBPF程序，`Aya`是一个用Rust编写的 eBPF 开发框架，专注于简化Linux eBPF程序的开发过程。
        * **使用 ebpf 来把每个发出去的 vxlan 包的第一个字节从 0x08 改为 0x88（或者其它），收到对端的 vxlan 包以后，再把 0x88 还原为 0x08，交给内核处理 vxlan 包**
        * 处理出站流量（egress）：把 vxlan 包中第一个字节从 0x08 改为 0x88；
        * 出入入站：ingress 流量处理是完全一样的，把 0x88 改为 0x80
* [一次使用 eBPF LSM 来解决系统时间被回调的记录](https://mp.weixin.qq.com/s/6jpXhWpHhGbkz6fHSKckBw)

若要自己写eBPF工具，结合场景更有体感，可以看看DBdoctor的几篇文章：

* [eBPF实战教程二｜数据库网络流量最精准的量化方法(含源码)](https://www.modb.pro/db/1799006796924407808)
    * 基于BCC，利用`kprobe`写了一个eBPF程序，观测MySQL的接收和发送的数据包
    * 对于统计TCP接收的网络流量，应该选择`tcp_cleanup_rbuf`函数，而不是选择`tcp_recvmsg`。选用`tcp_recvmsg`函数会存在统计的重复和遗漏
    * 探测了：`tcp_sendmsg`和`tcp_cleanup_rbuf`函数
* [eBPF实战教程三｜数据库磁盘IO最精准的量化方法(含源码)](https://www.modb.pro/db/1802889896725139456)
    * 基于BCC，利用`kprobe`写了一个eBPF程序，观测MySQL库表维度的磁盘IO的读写
    * 探测了：`vfs_read`和`vfs_write`

### 2.6. softlockup、hardlockup、内核hung住等定位思路

* [Softlockup和Hardlockup介绍和定位思路总结](https://zhuanlan.zhihu.com/p/463434168)
* [Oom介绍和定位思路](https://zhuanlan.zhihu.com/p/463434212)
* [内核Hungtask原理和定位思路总结](https://zhuanlan.zhihu.com/p/463433198)
* [ftrace&perf解决实际调度问题](https://zhuanlan.zhihu.com/p/420487043)

## 3. 性能优化

### 3.1. 一些参考文章

看过的一些文章，先列举，前面可能略显杂乱。需要梳理总结，不断消化并融于实践当中。

zStorage： 
* [丝析发解丨zStorage 是如何保持性能稳步上升的?](https://www.modb.pro/db/1762660180899205120)
    * 了解学习zStorage中看护性能指标的项目实践
        * 近1年来，zStorage 三节点集群的`4KB随机读写`性能从`120万`IOPS稳步提升到了`210万`IOPS
        * 为了追求极致性能，zStorage 数据面代码全部采用**标准C语言**编写
    * zStorage 在`MR（Merge Request）`合入之后，对每个`MR`会做性能测试，采用`Jenkins`自动化测试流水线，自动选择MR、编译、打包、部署、性能测试、输出性能结果。每个MR的性能测试结果，都会长期保存，以供后续分析。
    * 自动化措施
        * 1、检查软硬件环境，排除常见问题。包括**IB网卡**、硬盘数量。
        * 2、生成火焰图：比较不同`Merge Request`的火焰图，并可生成**差分火焰图**。查看哪些函数消耗了大量的CPU资源，还可用于观察**缓存未命中**等指标
* [分布式存储系统性能调优 - zStorage性能进化历程概述](https://zhuanlan.zhihu.com/p/692175522)
* [通过IPC指标诊断性能问题](https://zhuanlan.zhihu.com/p/3613097921)
* [zStorage分布式存储系统的性能分析方法](https://www.zhihu.com/collection/331116627)
    * 对 CPU、Memory、Disk、Network 分别进行测试
    * perf 火焰图 ipc
* [Linux C 性能优化实战（基于SPDK框架）](https://weibo.com/1202332555/KyDuKB3hY)

公众号：极客重生

讳疾忌医公众号：  
* [为什么你的高并发锁优化做不好？大部份开发者不知的无锁编程陷阱](https://mp.weixin.qq.com/s/EoW1Y7n_SXAjZtGRtcCeVw)
    * 分片锁：哈希均匀性与缓存对齐是关键
    * 无锁编程：CAS需警惕ABA，内存管理不可忽视
    * TLS：缓存行对齐是性能跃升的秘密武器
* [同事写了个比蜗牛还慢的排序，我用3行代码让他崩溃](https://mp.weixin.qq.com/s/qqLw9iNtSRI77vCILDGDgQ)  
    * 从手写O(n²)到STL的O(nlogn)，从单线程到并行化，再到移动语义和内存优化

[Linux内核性能剖析的方法学和主要工具（上文）](https://zhuanlan.zhihu.com/p/538791061)  
    盯着perf report里面排名第1，第2的整起来

百度Geek说公众号：  
* [百度C++工程师的那些极限优化（内存篇）](https://mp.weixin.qq.com/s/wF4M2pqlVq7KljaHAruRug)
* [百度C++工程师的那些极限优化（并发篇）](https://mp.weixin.qq.com/s/0Ofo8ak7-UXuuOoD0KIHwA)

[codedump的网络日志](https://www.codedump.info/)  
* codedump的网络日志 分布式存储 系统编程 存储引擎

[用 CPI 火焰图分析 Linux 性能问题](https://developer.aliyun.com/article/465499)

* CPI火焰图：[CPI Flame Graphs: Catching Your CPUs Napping](https://www.brendangregg.com/blog/2014-10-31/cpi-flame-graphs.html)
* [震惊，用了这么多年的 CPU 利用率，其实是错的](https://mp.weixin.qq.com/s/KaDJ1EF5Y-ndjRv2iUO3cA)
    * 译自上面贴过的Brendan Gregg大佬的这篇文章：[CPU Utilization is Wrong](https://www.brendangregg.com/blog/2017-05-09/cpu-utilization-is-wrong.html)

`perf c2c record/report` 查看cacheline情况

字节跳动sys tech的文章：  
* [DPDK内存碎片优化，性能最高提升30+倍!](https://mp.weixin.qq.com/s?__biz=Mzg3Mjg2NjU4NA==&mid=2247484462&idx=1&sn=406c59905ea57718018c602cba66f40e&chksm=cee9f259f99e7b4f7597eb6754367214a28f120c062c72c827f6e8c4225f9e54e4c65d4395d8&scene=21#wechat_redirect)
* [DPDK Graph Pipeline框架简介与实现原理](https://mp.weixin.qq.com/s?__biz=Mzg3Mjg2NjU4NA==&mid=2247483974&idx=1&sn=25a198745ee4bec9755fe1f64f500dd8&chksm=cee9f431f99e7d27527c7a74c0fd2969c00cf904cd5a25d09dd9e2ba1adb1e2f1a3ced267940&scene=21#wechat_redirect)

### 3.2. 总体思路

参考极客重生公众号中的梳理，总结得很好。可作为索引地图，在实践中按图索骥、查漏补缺。

1、单线

* 消除冗余：代码重构，临时变量，数据结构和算法，池化（内存池、线程池、连接池、对象池）、inline，RVO，vDSO，COW延迟计算，零拷贝等
* Cache优化：循环展开，local变量，cache对齐，内存对齐，预取，亲和性（绑核、独占），大页内存，内存池
* 指令优化：-O2，乱序优化，分支预测，向量指令`SIMD`（MMX，SSE，AVX）
* 硬件加速：DMA，网卡offload，加解密芯片，FPGA加速

2、多线（并发优化）

* 并行计算：流水线，超线程，多核，NUMA，GPU，多进程，多线程，多协程
* 并行竞争优化：原子操作，锁与无锁，local线程/CPU设计
* IO并行：多线程，多协程，非阻塞IO（epoll），异步IO（io_uring）
* 并行通信：MPI，共享内存，Actor模型-channel，无锁队列

3、整体（架构优化）

* 数据库优化：索引优化，读写分离，数据分片，水平和垂直分库分表
* 冷热分离：CDN优化，缓存优化
* 水平扩展：无状态设计，负载均衡，分布式计算-MapReduce模型
* 异步处理：消息队列，异步IO
* 高性能框架：Netty（Java）、Nginx、libevent、libev等

#### 3.2.1. 网络IO优化

* 1、IO加速
    * 内核旁路（Kernel Bypass）：让数据在**用户空间**和硬件设备之间直接进行传输和处理，**无需频繁地经过操作系统内核的干预**
        * 向上offload：`DPDK`/`SPDK`，如 `F-Stack`框架（基于DPDK的开源高性能网络开发框架）
        * 向下offload：`RDMA`
    * 硬件
        * FPGA（基于P4语言用于FPGA的编程）
* 2、CPU并发优化
    * 多进程、多线程、协程
    * 多核编程，绑核独占
    * 无锁、per CPU设计
* 3、减少cache miss
    * 预取、分支预测、亲和性、局部性原理
    * 大页、TLB
* 4、Linux网络系统优化
    * 网卡offload优化：checksum、GRO、GSO
        * `checksum`，将计算校验和的任务从CPU卸载到网卡，减轻 CPU 的负担
        * `GRO`（Generic Receive Offload，通用接收卸载），**网卡**将多个较小的网络数据包合并成一个较大的数据包，再传给上层协议栈，减少处理包次数，降低中断频率。适用于**接收大量小数据包**的应用。
        * `GSO`（Generic Segmentation Offload，通用分段卸载），**网卡**将较大的数据包在**发送端分割**成多个较小的数据包，并在**接收端重新组装**。可避免在发送端由CPU进行数据包分割，接收端也由网卡组装。
    * 并行优化：RSS、RPS、RFS、aRFS、XPS、SO_REUSEPORT
    * IO框架：select/poll/**epoll**/**io_uring**
    * 内核调参
        * 调整CPU亲和性（中断RSS、软中断RPS等）设置
        * 调整驱动budget/backlog大小
        * 调整TCP队列（等待队列，接收队列）大小
            * SYN队列、accept队列（全连接队列）
        * 调整sock缓冲区大小
        * 调整TCP缓冲区大小
5、减少重复操作
    * 池化技术：内存池，线程池，连接池等
    * 缓存技术
    * 零拷贝优化

#### 3.2.2. CPU性能优化

* 1、指令优化
    * 编译器优化，gcc优化选项如`-O2`（中等优化，相较于`-O1`、`-O3`更常用一些）
    * 指令预取，分支预测，局部性原理
* 2、算法优化
    * 算法和数据结构优化。比如STL中不关注顺序则`unordered_map`优于`map`、数据量大时`O(nlogn)`的排序、`O(logn)`的查找算法
* 3、并行优化
    * 多线程、多协程：上下文切换的开销不同
        * 可参考：[CPU及内存调度（一） -- 进程、线程、系统调用、协程上下文切换](https://xiaodongq.github.io/2025/03/09/context-switch/)）
        * 量级参考：进程上下文切换2.7us到5.48us之间、线程上下文切换3.8us左右、系统调用200ns、协程切换120ns
    * 异步处理：可避免程序因为等待而一直阻塞
    * 锁优化优化：细粒度锁、无锁设计，CPU/Thread local（比如tcmalloc内存池）
* 4、Cache优化
    * Cache对齐：提高缓存命中率，善用局部性原理。比如C++结构体定义时，指定`alignas(64)`
    * CPU绑定：提高CPU缓存命中率，减少跨CPU调度
* 5、调度优化
    * 优先级调整：`nice`调整进程优先级
    * CPU独占：`taskset`命令 或者 `pthread_setaffinity_np`接口
    * 中断负载均衡
        * `irqbalance`在高吞吐环境效果不一定好，手动设置方式可了解：[网卡相关工具命令](https://xiaodongq.github.io/2025/04/14/handy-tools/#73-%E7%BD%91%E5%8D%A1%E7%9B%B8%E5%85%B3%E5%B7%A5%E5%85%B7%E5%91%BD%E4%BB%A4)
* 6、亲和性优化
    * 中断亲和：网卡硬中断（RSS）和软中断（RPS）均衡绑定处理中断的CPU
        * 可以到`/proc/interrupts`里面过滤网卡设备，查看对应的中断号和中断处理的分布情况
        * 还有bcc的`softirqs`查看中断分布、`trace`跟踪指定函数对应的中断处理CPU
    * NUMA亲和性：多个node时，尽量让CPU只访问本地内存
        * 比如Redis配置文件里面配置时，设置CPU亲和性范围就需要关注NUMA的分布

#### 3.2.3. 内存性能优化

* 1、减少内存动态分配
    * 减少分配释放次数：内存池化，多线程场景考虑tcmalloc、jemalloc等内存分配器
    * 增大大小：page分配、大页、减少TLB miss等
* 2、内存分配优化
    * 数据通路缓存：per CPU缓存
    * 管理机制缓存：分级管理，比如tcmalloc中的前、中、后端
* 3、减少内存
    * 精细化调度体：比如协程替换线程，协程栈比线程栈小得多
    * 控制内存分配：按需分配，减少内存泄漏
* 4、算法优化
    * bitmap、布隆过滤器、数据库索引等
* 5、内存对齐
    * cacheline对齐，提升缓存命中率

#### 3.2.4. 硬盘IO优化

* 1、提高写性能
    * 顺序IO、Append-only
    * 批量写入：LSM tree，如LevelDB
* 2、提高读性能
    * 顺序读
    * 缓存：B+树索引，如MySQL的InnoDB存储引擎
    * 零拷贝：如mmap
* 3、硬盘优化
    * 硬件加速，SSD替换HDD
    * 调整预读块大小、硬盘队列长度
* 4、软件IO加锁
    * aio、io_uring、SPDK、NVME加速
    * 调整IO调度算法

