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

### 2.2. 软中断案例

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

### 2.3. 进程调度案例

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

### 2.4. eBPF辅助案例

挖坑的张师傅：

* [一次使用 eBPF LSM 来解决系统时间被回调的记录](https://mp.weixin.qq.com/s/6jpXhWpHhGbkz6fHSKckBw)
* [一次使用 ebpf 来解决 k8s 网络通信故障记录](https://mp.weixin.qq.com/s/cK8Ffhr2M6okysu-_iI6jg)

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

## 4. 问题定位工具

### 4.1. kdump 和 crash

1、kdump：

```sh
# 触发系统panic：
[CentOS-root@xdlinux ➜ ~ ]$ echo c > /proc/sysrq-trigger
# 查看dump文件
[CentOS-root@xdlinux ➜ ~ ]$ ll /var/crash 
drwxr-xr-x 2 root root 67 Mar 30 10:29 127.0.0.1-2025-03-30-10:29:58
[CentOS-root@xdlinux ➜ ~ ]$ ll /var/crash/127.0.0.1-2025-03-30-10:29:58 
# 上次内核的dmesg信息
-rw------- 1 root root  98K Mar 30 10:29 kexec-dmesg.log
-rw------- 1 root root 295M Mar 30 10:29 vmcore
# 崩溃时的dmesg信息
-rw------- 1 root root  80K Mar 30 10:29 vmcore-dmesg.txt
```

2、crash，用于分析系统coredump文件

分析dump文件需要内核vmlinux，安装对应内核的dbgsym包（没有则手动下载rmp安装：http://debuginfo.centos.org）

内核调试符号包：kernel-debuginfo、kernel-debuginfo-common。可以到阿里云的镜像站下载对应内核版本，比较快。

`rpm -ivh`手动安装，会安装到：`/usr/lib/debug/lib/modules`

**分析方法：**

1、加载：

```sh
[CentOS-root@xdlinux ➜ download ]$ crash /var/crash/127.0.0.1-2025-03-30-10\:29\:58/vmcore /usr/lib/debug/lib/modules/`uname -r`/vmlinux

crash 7.3.0-2.el8
...
This GDB was configured as "x86_64-unknown-linux-gnu"...

WARNING: kernel relocated [324MB]: patching 103007 gdb minimal_symbol values

      KERNEL: /usr/lib/debug/lib/modules/4.18.0-348.7.1.el8_5.x86_64/vmlinux
    DUMPFILE: /var/crash/127.0.0.1-2025-03-30-10:29:58/vmcore  [PARTIAL DUMP]
        CPUS: 16
        DATE: Sun Mar 30 10:29:39 CST 2025
      UPTIME: 7 days, 01:25:30
LOAD AVERAGE: 0.00, 0.00, 0.00
       TASKS: 340
    NODENAME: xdlinux
     RELEASE: 4.18.0-348.7.1.el8_5.x86_64
     VERSION: #1 SMP Wed Dec 22 13:25:12 UTC 2021
     MACHINE: x86_64  (3792 Mhz)
      MEMORY: 31.4 GB
       PANIC: "sysrq: SysRq : Trigger a crash"
         PID: 35261
     COMMAND: "zsh"
        TASK: ffff9a25a9511800  [THREAD_INFO: ffff9a25a9511800]
         CPU: 2
       STATE: TASK_RUNNING (SYSRQ)

crash> 
```

2、常用命令：ps、bt、log

```sh

crash> ps
   PID    PPID  CPU       TASK        ST  %MEM     VSZ    RSS  COMM
>     0      0   0  ffffffff96a18840  RU   0.0       0      0  [swapper/0]
>     0      0   1  ffff9a2403880000  RU   0.0       0      0  [swapper/1]
      0      0   2  ffff9a2403884800  RU   0.0       0      0  [swapper/2]
>     0      0   3  ffff9a24038ab000  RU   0.0       0      0  [swapper/3]
>     0      0   4  ffff9a24038a9800  RU   0.0       0      0  [swapper/4]
>     0      0   5  ffff9a24038ae000  RU   0.0       0      0  [swapper/5]
...

crash> bt
PID: 35261  TASK: ffff9a25a9511800  CPU: 2   COMMAND: "zsh"
 #0 [ffffb694057a3b98] machine_kexec at ffffffff954641ce
 #1 [ffffb694057a3bf0] __crash_kexec at ffffffff9559e67d
 #2 [ffffb694057a3cb8] crash_kexec at ffffffff9559f56d
 #3 [ffffb694057a3cd0] oops_end at ffffffff9542613d
 #4 [ffffb694057a3cf0] no_context at ffffffff9547562f
 #5 [ffffb694057a3d48] __bad_area_nosemaphore at ffffffff9547598c
 #6 [ffffb694057a3d90] do_page_fault at ffffffff95476267
 #7 [ffffb694057a3dc0] page_fault at ffffffff95e0111e
    [exception RIP: sysrq_handle_crash+18]
    RIP: ffffffff959affd2  RSP: ffffb694057a3e78  RFLAGS: 00010246
    RAX: ffffffff959affc0  RBX: 0000000000000063  RCX: 0000000000000000
    RDX: 0000000000000000  RSI: ffff9a2afe296858  RDI: 0000000000000063
    RBP: 0000000000000004   R8: 0000000000000456   R9: ffff9a2400057460
    R10: ffffffff959136f0  R11: ffffb694057a3d30  R12: 0000000000000000
    R13: 0000000000000000  R14: ffffffff962af240  R15: 0000000000000000
    ORIG_RAX: ffffffffffffffff  CS: 0010  SS: 0018

crash> log
[    0.000000] Linux version 4.18.0-348.7.1.el8_5.x86_64 (mockbuild@kbuilder.bsys.centos.org) (gcc version 8.5.0 20210514 (Red Hat 8.5.0-4) (GCC)) #1 SMP Wed Dec 22 13:25:12 UTC 2021
[    0.000000] Command line: BOOT_IMAGE=(hd0,gpt6)/vmlinuz-4.18.0-348.7.1.el8_5.x86_64 root=/dev/mapper/cl_desktop--mme7h3a-root ro crashkernel=auto resume=/dev/mapper/cl_desktop--mme7h3a-swap rd.lvm.lv=cl_desktop-mme7h3a/root rd.lvm.lv=cl_desktop-mme7h3a/swap rhgb quiet
[    0.000000] x86/fpu: Supporting XSAVE feature 0x001: 'x87 floating point registers'

crash> kmem -i
                 PAGES        TOTAL      PERCENTAGE
    TOTAL MEM  8013423      30.6 GB         ----
         FREE  7215135      27.5 GB   90% of TOTAL MEM
         USED   798288         3 GB    9% of TOTAL MEM
       SHARED    32189     125.7 MB    0% of TOTAL MEM
      BUFFERS      915       3.6 MB    0% of TOTAL MEM
       CACHED   481884       1.8 GB    6% of TOTAL MEM
         SLAB    27734     108.3 MB    0% of TOTAL MEM

   TOTAL HUGE        0            0         ----
    HUGE FREE        0            0    0% of TOTAL HUGE

   TOTAL SWAP   262143      1024 MB         ----
    SWAP USED        0            0    0% of TOTAL SWAP
```

