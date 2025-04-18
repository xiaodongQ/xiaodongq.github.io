---
title: 问题定位和性能优化案例集锦
description: 记录精彩的问题定位过程和性能优化手段，内化并能为自己所用。
categories: [Troubleshooting]
tags: [Troubleshooting]
pin: true
---

## 1. 背景

TODO List里面，收藏待看的文章已经不少了，有一类是觉得比较精彩的问题定位过程，还有一类是性能优化相关的文章，需要先还一些“技术债”了。

本篇将这些文章内容做简要分析，作为索引供后续不定期翻阅。

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

网络队列、ring buffer查看相关命令示例见：[实用工具集索引](https://xiaodongq.github.io/2025/04/14/handy-tools/)

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
        * 先说结论，原因：线上部分机器部署的 atop 版本 默认启用了 `-R` 选项。**在 atop 读 /proc/${pid}/smaps 时，会遍历整个进程的页表，期间会持有内存页表的锁。如果在此期间进程发生虚拟内存地址分配，也需要获取锁，就需要等待锁释放。具体到应用层面就是请求耗时毛刺。**
    * 根因分析。可以看看里面的手段思路
        * 了解`smaps`中的内容和文件更新原理，proc使用的文件类型是`seq_file`序列文件。
            * `smaps` 文件包含了每个进程的内存段的详细信息，包括但不限于各段的大小、权限、偏移量、设备号、inode 号以及最值得注意的——各段的 `PSS（Proportional Set Size，比例集大小）`和 `RSS（Resident Set Size，常驻集大小）`。（针对多进程共享内存的场景，`PSS`的物理内存统计比`RSS`更为准确）。
            * 关于序列文件，之前梳理netstat的实现流程中也涉及了。其读取proc文件系统的`/proc/net/tcp`就是用的序列文件，其简要流程可见：[分析netstat中的Send-Q和Recv-Q](https://xiaodongq.github.io/2024/05/27/netstat-code/#3-procnettcp%E6%96%87%E4%BB%B6%E6%9B%B4%E6%96%B0%E9%80%BB%E8%BE%91) 
        * 进程耗时分2大部分：**用户空间** 和 **内核空间** 的耗时
            * 在缺乏统计系统和百分位延时指标时，`用户空间`的耗时，可以使用bcc的 `funcslower`（示例实验见补充文章）
            * `内核空间`耗时，可选工具：
                * bcc的`syscount`，syscount 并不能直接查看调用层级，但可以通过对比不同时间区间的延迟变化发现问题，可指定进程。
                * `perf trace`：相较于 syscount 提供了 histogram 图，**可以直观的发现长尾问题**（示例实验见补充文章）
            * 然后，可进一步使用perf-tools的 `funcgraph` 定位到耗时异常的函数

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

问题：数据库核心业务1-2次抖动

* 不论读请求还是写请求，不管是处理用户请求的线程还是底层raft相关的线程，都hang住了数百毫秒
* 慢请求日志里显示处理线程没有suspend，wall time很大，但真正耗费的CPU time[1]很小；且抖动发生时不论是容器还是宿主机，CPU使用率都非常低。
* CPU绑核了，但还是抖动
* 怀疑是内核调度的锅
* 写了一个简单的ticker，不停地干10ms活再sleep 10ms，一个loop内如果总耗时>25ms就认为发生了抖动，输出一些CPU、调度的信息。
* 复现后利用`perf sched latency`看看各个线程的调度延迟以及时间点
* 进程发送了SIGSTOP
    * 同事很快锁定了其中一个由安全团队部署的插件，因为在内网wiki里它的介绍是：进程监控
    * 进一步从安全团队了解到该插件会利用/proc伪文件系统定时扫描宿主机上所有进程的cpuset、comm、cwd等信息，需要排查具体是插件的哪个行为导致了抖动
* 利用https://github.com/brendangregg/perf-tools/tree/master里的`functrace`很轻易的找到了::write会调用down_write
* **数据库里哪个路径需要加mmap_sem的写锁**

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

[Linux内核性能剖析的方法学和主要工具（上文）](https://zhuanlan.zhihu.com/p/538791061)  
    盯着perf report里面排名第1，第2的整起来

讳疾忌医公众号：  
[为什么你的高并发锁优化做不好？大部份开发者不知的无锁编程陷阱](https://mp.weixin.qq.com/s/EoW1Y7n_SXAjZtGRtcCeVw)

* 分片锁：哈希均匀性与缓存对齐是关键
* 无锁编程：CAS需警惕ABA，内存管理不可忽视
* TLS：缓存行对齐是性能跃升的秘密武器

[同事写了个比蜗牛还慢的排序，我用3行代码让他崩溃](https://mp.weixin.qq.com/s/qqLw9iNtSRI77vCILDGDgQ)  
    从手写O(n²)到STL的O(nlogn)，从单线程到并行化，再到移动语义和内存优化

[百度C++工程师的那些极限优化（内存篇）](https://mp.weixin.qq.com/s/wF4M2pqlVq7KljaHAruRug)

[百度C++工程师的那些极限优化（并发篇）](https://mp.weixin.qq.com/s/0Ofo8ak7-UXuuOoD0KIHwA)


https://zhuanlan.zhihu.com/p/692175522 分布式存储系统性能调优 - zStorage性能进化历程概述

[丝析发解丨zStorage 是如何保持性能稳步上升的?](https://www.modb.pro/db/1762660180899205120)

https://www.codedump.info/ codedump的网络日志 分布式存储 系统编程 存储引擎

https://weibo.com/1202332555/KyDuKB3hY


zStorage：小川  
* [通过IPC指标诊断性能问题](https://zhuanlan.zhihu.com/p/3613097921)
* [zStorage分布式存储系统的性能分析方法](https://www.zhihu.com/collection/331116627)
    * 对 CPU、Memory、Disk、Network 分别进行测试
    * perf 火焰图 ipc

[用 CPI 火焰图分析 Linux 性能问题](https://developer.aliyun.com/article/465499)

* CPI火焰图：[CPI Flame Graphs: Catching Your CPUs Napping](https://www.brendangregg.com/blog/2014-10-31/cpi-flame-graphs.html)
* [震惊，用了这么多年的 CPU 利用率，其实是错的](https://mp.weixin.qq.com/s/KaDJ1EF5Y-ndjRv2iUO3cA)

`perf c2c record/report` 查看cacheline情况

字节跳动sys tech的文章：

[DPDK内存碎片优化，性能最高提升30+倍!](https://mp.weixin.qq.com/s?__biz=Mzg3Mjg2NjU4NA==&mid=2247484462&idx=1&sn=406c59905ea57718018c602cba66f40e&chksm=cee9f259f99e7b4f7597eb6754367214a28f120c062c72c827f6e8c4225f9e54e4c65d4395d8&scene=21#wechat_redirect)

[DPDK Graph Pipeline框架简介与实现原理](https://mp.weixin.qq.com/s?__biz=Mzg3Mjg2NjU4NA==&mid=2247483974&idx=1&sn=25a198745ee4bec9755fe1f64f500dd8&chksm=cee9f431f99e7d27527c7a74c0fd2969c00cf904cd5a25d09dd9e2ba1adb1e2f1a3ced267940&scene=21#wechat_redirect)

