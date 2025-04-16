---
title: 问题定位和性能优化案例集锦
description: 记录精彩的问题定位过程和性能优化手段，内化并为我所用
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

### 2.2. 软中断

[Redis 延迟毛刺问题定位-软中断篇](https://www.cyningsun.com/09-17-2024/redis-latency-irqoff.html)

问题：通过`业务监控系统`，发现线上Redis集群有延迟毛刺，出现的时间点不定，但大概每小时会有1次，每次持续大概10分钟

* **整个链路**是 Redis SDK -> Redis Proxy -> 各个Redis
    * 性能之巅中的建议：**性能分析时先画出架构链路图**
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
* 可`perf record -e skb:kfree_skb`检查丢包
    * 腾讯、字节等厂在此基础上进行了更加友好的封装：nettrace、netcap

`ifconfig`、`ethtool -S`统计信息示例，关注发送和接收的计数统计（非案例中的采集）：

```sh
# ifconfig统计的网口接收、发送包信息
[CentOS-root@xdlinux ➜ ~ ]$ ifconfig enp4s0
enp4s0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 192.168.1.150  netmask 255.255.255.0  broadcast 192.168.1.255
        ...
        ether 1c:69:7a:f5:39:32  txqueuelen 1000  (Ethernet)
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
     align_errors: 0
     tx_single_collisions: 0
     tx_multi_collisions: 0
     unicast: 2691160
     broadcast: 729420
     multicast: 4241
     tx_aborted: 0
     tx_underrun: 0
```

另外发现博主的历史文章，也覆盖了之前看过的网络发送和接收文章翻译：

* [译｜Monitoring and Tuning the Linux Networking Stack: Receiving Data](https://www.cyningsun.com/04-24-2023/monitoring-and-tuning-the-linux-networking-stack-recv-cn.html#Receive-Packet-Steering-RPS)
* [译｜Monitoring and Tuning the Linux Networking Stack: Sending Data](https://www.cyningsun.com/04-25-2023/monitoring-and-tuning-the-linux-networking-stack-sent-cn.html)

关注的ArthurChiao's Blog中也做了翻译，排版更好一点：

* [[译] Linux 网络栈监控和调优：发送数据（2017）](https://arthurchiao.art/blog/tuning-stack-tx-zh/)
* [[译] Linux 网络栈监控和调优：接收数据（2016）](https://arthurchiao.art/blog/tuning-stack-rx-zh/)

### 2.3. 进程调度

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

### 2.4. eBPF

挖坑的张师傅：

* [一次使用 eBPF LSM 来解决系统时间被回调的记录](https://mp.weixin.qq.com/s/6jpXhWpHhGbkz6fHSKckBw)
* [一次使用 ebpf 来解决 k8s 网络通信故障记录](https://mp.weixin.qq.com/s/cK8Ffhr2M6okysu-_iI6jg)