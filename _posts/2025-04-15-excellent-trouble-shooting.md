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

里面有一些实际案例和场景介绍，对理解大佬开发的火焰图、bcc、perf-tools等一些工具的使用和应用场景很有帮助，否则只是停留于第一个层面。

#### 2.1.1. page占用很高

[Analyzing a High Rate of Paging](https://www.brendangregg.com/blog/2021-08-30/high-rate-of-paging.html)

问题：微服务管理上传大小文件（100 Gbytes、40 Gbytes），page页占用一直很高

* iostat
* biolatency（bcc）
* bitesize
* free（缓存）
* cachestat（bcc）

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

问题：redis有毛刺

* 发现 rx missed_errors 高，
* ethtool -G 修改网卡ring buffer
* 软中断线程收包阻塞，rx drop 是因为软中断线程收包慢导致的
    * 使用字节跳动团队的 [trace-irqoff](https://github.com/bytedance/trace-irqoff)
* 可perf record -e skb:kfree_skb检查丢包
    * 腾讯、字节等厂在此基础上进行了更加友好的封装：nettrace、netcap

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