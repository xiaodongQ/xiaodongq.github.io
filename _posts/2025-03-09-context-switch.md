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

* [开发内功修炼之CPU篇](https://mp.weixin.qq.com/mp/appmsgalbum?__biz=MjM5Njg5NDgwNA==&action=getalbum&album_id=1372643250460540932&scene=126&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=0&fontScale=100)
* [plantegg CPU系列](https://plantegg.github.io/categories/CPU/)
* [Linux 服务器功耗与性能管理（一）：CPU 硬件基础（2024）](https://arthurchiao.art/blog/linux-cpu-1-zh/)
* 以及早前“**看过**”的[极客时间：系统性能调优必知必会](https://time.geekbang.org/column/intro/308)

又一点想法（最近感慨稍微多一点）：

当时池老师他们的极客时间APP刚出来时，很多课程刚出来就买得看，笔记记了一堆，比如 [Linux性能优化实践.md](https://github.com/xiaodongQ/devNoteBackup/blob/master/%E5%90%84%E5%88%86%E7%B1%BB%E8%AE%B0%E5%BD%95/Linux%E6%80%A7%E8%83%BD%E4%BC%98%E5%8C%96%E5%AE%9E%E8%B7%B5.md)，却是低效学习，时间越长，内化越少。去年走通了一点：看书、学英语、写博客、软考和E类，而且基本都在工作之余，跟以往有所不同，虽然也有内耗但多了一点渴望和热情。

分享几篇时常会拎出来出来看的文章，受益匪浅：

* [如何在工作中学习](https://plantegg.github.io/2018/05/23/%E5%A6%82%E4%BD%95%E5%9C%A8%E5%B7%A5%E4%BD%9C%E4%B8%AD%E5%AD%A6%E4%B9%A0/)
* [09 -- 答疑解惑：渴望、热情和选择](https://time.geekbang.org/column/article/deb5f34148c77256cd878ebfb5458f73/share?source=app_share)
* [结束语 -- 业精于勤，行成于思](https://time.geekbang.org/column/article/15fcd54543363f3b6236c5dac4f31c20/share?source=app_share)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. CPU相关基础说明

### 2.1. CPU配置和CPU Cache

基于自己的PC电脑：

* AMD的CPU、8物理核，16线程
* CPU缓存：缓解CPU和内存速度不匹配问题，减少延迟。三级缓存结构：
    * L1缓存有两种：缓存数据（`L1d cache`） 和 缓存指令（`L1i cache`），此处各32KB。
        * L1最接近于CPU，速度也最快，但是容量最小
        * 一般每个核都有自己**独立**的data L1和code L1
    * L2一般也可以做到每个核一个**独立**，此处 512K
    * L3一般就是**整颗CPU共享**，此处 16384K
        * 超线程2个逻辑核共享L3
* CPU Cache Line：本级缓存向下一层取数据时的基本单位
    * Cacheline会导致多线程伪共享问题，可以看到很多代码里为了局部一致性问题有关于长度补齐的设计，比如Redis sds
    * 利用**局部性原理**提升数据缓存的命中率
    * 可看到此处CPU都为 `64 字节`

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

### 2.2. TLB缓存

`TLB（Translation Lookaside Buffer）`，也称**快表缓存**、**旁路转换缓冲**，用于改进`虚拟地址`到`物理地址`转换速度的`缓存`。

先说明`TLB`出现的背景：

每个进程都有自己的虚拟地址空间，虚拟地址会`映射`到实际的物理内存地址，CPU则根据`页表`来进行映射转换。页表大小一般为`4K`，可通过`getconf PAGE_SIZE`查看。

* 32位系统通过`二级页表`（页目录+页表），映射`4GB`的进程虚拟地址空间（一般用户态和内核态各2GB）
* 64位系统，则通过`四级页表`（`页全局目录PGD`+`页上级目录PUD`+`页中间目录PMD`+`页表项PTE`），映射 `2^48 = 256TB`的虚拟地址空间

`TLB`缓存就是为了避免一次内存IO需要去查4次页表，于是在CPU里把页表缓存起来。

有了TLB之后，CPU访问某个虚拟内存地址的过程如下：

* 1、CPU产生一个 **虚拟地址**
* 2、1）MMU从TLB中获取页表，翻译成 **物理地址**
    * `MMU（Memory Management Unit）`即内存管理单元，负责 虚拟内存地址 到 物理内存地址 的转换。
        * 对于多数现代通用CPU，MMU 通常是集成在 CPU 内部的
    * 2）若在TLB中没有找到相应的页表项（即`TLB未命中`），MMU就需要去`内存中的页表`查找
    * 3）若在内存页表中发现所需的页面不在物理内存中，就会触发**缺页异常**/**缺页中断**
* 3、MMU把物理地址发送给L1/L2/L3/内存
* 4、L1/L2/L3/内存将 地址对应的**数据** 返回给CPU

#### 2.2.1. 查看TLB缓存命中率

perf命令查看事件：`perf stat -e dTLB-loads,dTLB-load-misses,iTLB-loads,iTLB-load-misses -p $PID`

* `dTLB-loads`：`数据TLB（Data Translation Lookaside Buffer）`加载次数，即CPU尝试从`数据TLB`中获取`虚拟地址`到`物理地址`映射的次数
* `dTLB-load-misses`：数据TLB 加载未命中次数，也就是在 数据TLB 中没有找到所需映射，需要进行额外查找（如访问页表）的次数。
* `iTLB-loads`：`指令TLB（Instruction Translation Lookaside Buffer）`加载次数，即CPU尝试从`指令TLB`中获取虚拟地址到物理地址映射的次数，主要用于指令的取指操作。
* `iTLB-load-misses`：指令TLB 加载未命中次数，即 指令TLB 中未找到所需映射的次数。

```sh
[CentOS-root@xdlinux ➜ ~ ]$ perf stat -e dTLB-loads,dTLB-load-misses,iTLB-loads,iTLB-load-misses
^C
 Performance counter stats for 'system wide':

            32,894      dTLB-loads                                                  
            28,914      dTLB-load-misses          #   87.90% of all dTLB cache accesses
               295      iTLB-loads                                                  
            11,849      iTLB-load-misses          # 4016.61% of all iTLB cache accesses

       2.847103403 seconds time elapsed
```

> 因为TLB并不是很大，只有`4KB`，而且现在逻辑核又造成会有两个进程来共享。所以可能会有cache miss的情况出现。而且一旦TLB miss造成的后果可比物理地址cache miss后果要严重一些，最多可能需要进行5次内存IO才行。

若TLB miss率比较高，可考虑开启 `内存大页（Huge Page`，大大减少页表项来增加命中率。页大小一般为4KB，而常见的大页大小有`2MB`、`1GB`。比如：[为什么HugePage能让Oracle数据库如虎添翼？](https://mp.weixin.qq.com/s/3Lb7-KuAlN6NnfFPL5RDdQ)。

## 3. 上下文切换的开销

[开发内功修炼之CPU篇](https://mp.weixin.qq.com/mp/appmsgalbum?__biz=MjM5Njg5NDgwNA==&action=getalbum&album_id=1372643250460540932&scene=126&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=0&fontScale=100) 里面对下面几种情况都做了实验对比，此处暂只说明结论。

### 3.1. 进程上下文切换

1、切换时机

* 进程CPU时间片用完
* 有更高优先级的进程出现
* 进程执行 I/O 操作：比如从磁盘读取数据

2、保存内容

* 通用寄存器：保存CPU中通用寄存器的值，临时存储数据和操作数，以便在进程恢复执行时能够继续使用之前的数据
* 程序计数器（PC）：保存当前进程下一条要执行的指令地址
* 进程状态字（PSW）：记录进程的状态信息，如进程的优先级、是否处于中断允许状态等
* 内存管理信息：包括进程的`页表指针`、`内存段`信息等，如切换页表全局目录、刷新TLB
* 打开文件表指针：记录进程打开的文件信息

3、切换开销

测试方法：1）[lmbench](https://lmbench.sourceforge.net/) 2）写demo，使用进程间通信：管道

结论（参考结论）：lmbench显示的进程上下文切换耗时从`2.7us到5.48之间`

间接开销：切换后由于各种缓存并不热，速度运行会慢一些。如果跨CPU的话，之前热起来的TLB、L1、L2、L3因为运行的进程已经变了，所以局部性原理cache起来的代码、数据也都没有用了，导致新进程穿透到内存的IO会变多。

### 3.2. 线程上下文切换

1、切换时机

* 线程时间片用完：类似进程，线程也有自己的时间片
* 线程阻塞：如等待锁、等待 I/O 完成
* 线程优先级变化：线程的优先级发生了变化，或者系统中出现了更高优先级的线程

2、保存内容

* 通用寄存器
* 程序计数器
* 线程栈指针：线程有自己的栈空间，用于存储线程的局部变量、函数调用栈等信息
* 线程私有数据指针：如果线程有自己的私有数据，需要保存指向这些私有数据的指针

3、切换开销

测试方法：demo

参考结论：和进程差不多

观察：

```sh
# vmstat
[CentOS-root@xdlinux ➜ ~ ]$ vmstat 1
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 1  0      0 29978184   3728 1088056    0    0     0     0    8    3  0  0 100  0  0
 0  0      0 29978012   3728 1088056    0    0     0     0  210  254  0  0 100  0  0
^C

# sar -w
[CentOS-root@xdlinux ➜ ~ ]$ sar -w 1
Linux 4.18.0-348.7.1.el8_5.x86_64 (xdlinux) 	03/10/2025 	_x86_64_	(16 CPU)

06:53:53 AM    proc/s   cswch/s
06:53:54 AM      0.00    214.00
06:53:55 AM      0.00    228.00

# pidstat -w
[CentOS-root@xdlinux ➜ ~ ]$ pidstat -w 1
Linux 4.18.0-348.7.1.el8_5.x86_64 (xdlinux) 	03/10/2025 	_x86_64_	(16 CPU)

06:54:43 AM   UID       PID   cswch/s nvcswch/s  Command
06:54:44 AM     0        11      5.94      0.00  rcu_sched
06:54:44 AM     0        13      0.99      0.00  watchdog/0
06:54:44 AM     0        16      0.99      0.00  watchdog/1

# proc中观察总的切换，自愿切换和非自愿切换
[CentOS-root@xdlinux ➜ ~ ]$ grep ctxt /proc/305/status
voluntary_ctxt_switches:	2
nonvoluntary_ctxt_switches:	0
```

### 3.3. 系统调用开销

系统调用的用户态和内核态切换也属于上下文切换范畴。

1、切换时机

* 系统调用：从用户态切换到内核态来执行系统调用函数，完成后再从内核态切换回用户态
* 中断处理：当硬件设备产生中断时（硬中断和伴随的软中断），CPU需要暂停当前正在执行的任务，切换到内核态来处理中断

2、保存内容

* 内核栈指针：用于保存内核函数调用的参数、局部变量等信息
* 通用寄存器
* 程序计数器
* 进程描述符指针：指向当前进程的进程描述符，其中包含了进程的各种信息，如进程 ID、进程状态等
* 此外：用户态和内核态切换时，还会切换权限到特权指令，可以访问一些受保护的资源或执行特权操作

### 3.4. 协程切换开销

1、切换时机

* 主动让出执行权
* 协程执行完成
* 调度策略触发

2、保存内容

* 局部变量和栈状态
* 寄存器状态
* 程序计数器

## 4. 小结



## 5. 参考

* [开发内功修炼之CPU篇](https://mp.weixin.qq.com/mp/appmsgalbum?__biz=MjM5Njg5NDgwNA==&action=getalbum&album_id=1372643250460540932&scene=126&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=0&fontScale=100)
* [听说你只知内存，而不知缓存？CPU表示很伤心！](https://mp.weixin.qq.com/s/PQTuFZO51an6OAe3WX4BVw)
* [TLB缓存是个神马鬼，如何查看TLB miss？](https://mp.weixin.qq.com/s/mssTS3NN7-w2df1vhYSuYw)
* [为什么HugePage能让Oracle数据库如虎添翼？](https://mp.weixin.qq.com/s/3Lb7-KuAlN6NnfFPL5RDdQ)
* [进程/线程切换究竟需要多少开销？](https://mp.weixin.qq.com/s?__biz=MjM5Njg5NDgwNA==&mid=2247483804&idx=1&sn=f2d64fc244d381157bb0c16ff26a33bd&chksm=a6e300a7919489b1b3590369c2ff739d3e97a7191c792f43da3b361c357c2daec7e20fa1f45f&scene=178&cur_album_id=1372643250460540932#rd)
* 