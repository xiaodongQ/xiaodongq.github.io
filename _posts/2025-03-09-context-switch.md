---
layout: post
title: CPU学习实践系列（一） -- 线程上下文切换
categories: CPU
tags: CPU 线程
---

* content
{:toc}

CPU学习实践系列开篇，并基于线程池的demo，观察上下文切换。



## 1. 背景

之前投入 [网络](https://xiaodongq.github.io/category/#%E7%BD%91%E7%BB%9C) 相关的学习实践更多一点，虽然还有很多TODO项，以及存储方面待深入梳理，但最近碰到的问题有不少还是跟内存和CPU相关。本篇开始梳理CPU、内存方面的学习记录，并基于上篇 [线程池](https://xiaodongq.github.io/2025/03/08/threadpool/) 进行实验。

参考博客系列：

* [开发内功修炼之CPU篇](https://mp.weixin.qq.com/mp/appmsgalbum?__biz=MjM5Njg5NDgwNA==&action=getalbum&album_id=1372643250460540932&scene=126&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=78&fontScale=100)
* [plantegg CPU系列](https://plantegg.github.io/categories/CPU/)
* [Linux 服务器功耗与性能管理（一）：CPU 硬件基础（2024）](https://arthurchiao.art/blog/linux-cpu-1-zh/)
* 以及早前“**看过**”的[极客时间：系统性能调优必知必会](https://time.geekbang.org/column/intro/308)

又一点想法（最近感慨稍微多一点）：

当时池老师他们的极客时间APP刚出来时，很多课程刚出来就买得看，笔记记了一堆，比如 [Linux性能优化实践.md](https://github.com/xiaodongQ/devNoteBackup/blob/master/%E5%90%84%E5%88%86%E7%B1%BB%E8%AE%B0%E5%BD%95/Linux%E6%80%A7%E8%83%BD%E4%BC%98%E5%8C%96%E5%AE%9E%E8%B7%B5.md)，却是低效学习，时间越长，内化越少。去年走通了一点：看书、学英语、写博客、软考和E类，而且基本都在工作之余，跟以往有所不同，渴望和热情。

分享几篇时常会拎出来出来看的文章，受益匪浅：

* [如何在工作中学习](https://plantegg.github.io/2018/05/23/%E5%A6%82%E4%BD%95%E5%9C%A8%E5%B7%A5%E4%BD%9C%E4%B8%AD%E5%AD%A6%E4%B9%A0/)
* [09 -- 答疑解惑：渴望、热情和选择](https://time.geekbang.org/column/article/deb5f34148c77256cd878ebfb5458f73/share?source=app_share)
* [结束语 -- 业精于勤，行成于思](https://time.geekbang.org/column/article/15fcd54543363f3b6236c5dac4f31c20/share?source=app_share)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. CPU相关说明

### 2.1. 配置

基于自己的PC电脑：

* AMD的CPU、8物理核，16线程
* CPU缓存：缓解CPU和内存速度不匹配问题。三级缓存结构：
    * L1缓存有两种：缓存数据（`L1d cache`） 和 缓存指令（`L1i cache`），此处各32KB。
        * L1最接近于CPU，速度也最快，但是容量最小
        * 一般每个核都有自己**独立**的data L1和code L1
    * L2一般也可以做到每个核一个**独立**，此处 512K
    * L3一般就是**整颗CPU共享**，此处 16384K
        * 超线程2个逻辑核共享L3
* CPU Cache Line：本级缓存向下一层取数据时的基本单位
    * Cacheline伪共享问题，可以看到代码里为了局部一致性各种长度补齐相关设计，比如Redis sds
    * 提升数据缓存的命中率
    * 可看到都为 `64 字节`

```sh
[CentOS-root@xdlinux ➜ bcc ]$ lscpu 
Architecture:        x86_64
CPU op-mode(s):      32-bit, 64-bit
Byte Order:          Little Endian
CPU(s):              16
On-line CPU(s) list: 0-15
Thread(s) per core:  2
Core(s) per socket:  8
Socket(s):           1
NUMA node(s):        1
Vendor ID:           AuthenticAMD
BIOS Vendor ID:      AMD
CPU family:          25
Model:               80
Model name:          AMD Ryzen 7 5700G with Radeon Graphics
BIOS Model name:     AMD Ryzen 7 5700G with Radeon Graphics         
Stepping:            0
CPU MHz:             3800.000
CPU max MHz:         4672.0698
CPU min MHz:         1400.0000
BogoMIPS:            7586.32
Virtualization:      AMD-V
L1d cache:           32K
L1i cache:           32K
L2 cache:            512K
L3 cache:            16384K
NUMA node0 CPU(s):   0-15
...

# CPU 各级缓存的 cacheline
[CentOS-root@xdlinux ➜ bcc ]$ cat /sys/devices/system/cpu/cpu0/cache/index0/coherency_line_size
64
[CentOS-root@xdlinux ➜ bcc ]$ cat /sys/devices/system/cpu/cpu*/cache/index*/coherency_line_size|uniq
64
```

了解各厂商CPU，可参考 [plantegg CPU系列](https://plantegg.github.io/categories/CPU/) 下的几篇文章：

* [Intel、海光、鲲鹏920、飞腾2500 CPU性能对比](https://plantegg.github.io/2021/06/18/%E5%87%A0%E6%AC%BECPU%E6%80%A7%E8%83%BD%E5%AF%B9%E6%AF%94/)
* [AMD Zen CPU 架构以及不同CPU性能大PK](https://plantegg.github.io/2021/08/13/AMD_Zen_CPU%E6%9E%B6%E6%9E%84/)



## 3. 小结



## 4. 参考

