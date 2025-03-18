---
layout: post
title: CPU及内存调度（一） -- 进程、线程、系统调用、协程上下文切换
categories: CPU
tags: CPU 线程
---

* content
{:toc}

CPU和内存调度相关学习实践系列开篇，学习进程、线程、系统调用、协程上下文切换。



## 1. 背景

之前投入 [网络](https://xiaodongq.github.io/category/#%E7%BD%91%E7%BB%9C) 相关的学习实践更多一点，虽然还有很多TODO项，以及存储方面待深入梳理，但最近碰到的问题有不少还是跟内存和CPU相关。本篇开始梳理CPU、内存方面的学习记录，并基于上篇 [并发与异步编程（一） -- 实现一个简单线程池](https://xiaodongq.github.io/2025/03/08/threadpool/) 进行观察。

参考博客系列：

* [开发内功修炼之CPU篇](https://mp.weixin.qq.com/mp/appmsgalbum?__biz=MjM5Njg5NDgwNA==&action=getalbum&album_id=1372643250460540932&scene=126&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=0&fontScale=100)
* [plantegg CPU系列](https://plantegg.github.io/categories/CPU/)
* [Linux 服务器功耗与性能管理（一）：CPU 硬件基础（2024）](https://arthurchiao.art/blog/linux-cpu-1-zh/)
* 以及早前“**看过**”的[极客时间：系统性能调优必知必会](https://time.geekbang.org/column/intro/308)

又一点想法（最近感慨稍微多一点）：

当时池老师他们的极客时间APP刚出来时，很多课程刚出来就买得看，笔记记了一堆，比如 [Linux性能优化实践.md](https://github.com/xiaodongQ/devNoteBackup/blob/master/%E5%90%84%E5%88%86%E7%B1%BB%E8%AE%B0%E5%BD%95/Linux%E6%80%A7%E8%83%BD%E4%BC%98%E5%8C%96%E5%AE%9E%E8%B7%B5.md)，却是低效学习，时间越长，内化越少。去年走通了一点：看书、学英语、写博客、软考，而且基本都在工作之余，跟以往有所不同，虽然也有内耗但多了一点渴望和热情。

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
（不用去记，`perf list`可查看事件列表）

* `dTLB-loads`：`数据TLB（Data Translation Lookaside Buffer）`加载次数，即CPU尝试从 `数据TLB` 中获取`虚拟地址`到`物理地址`映射的次数
* `dTLB-load-misses`：数据TLB 加载未命中次数，也就是在 数据TLB 中没有找到所需映射，需要进行额外查找（如访问页表）的次数。
* `iTLB-loads`：`指令TLB（Instruction Translation Lookaside Buffer）`加载次数，即CPU尝试从 `指令TLB` 中获取虚拟地址到物理地址映射的次数，主要用于指令的取指操作。
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

若TLB miss率比较高，可考虑开启 `内存大页（Huge Page）`，大大减少页表项来增加命中率。页大小一般为4KB，而常见的大页大小有`2MB`、`1GB`。比如：[为什么HugePage能让Oracle数据库如虎添翼？](https://mp.weixin.qq.com/s/3Lb7-KuAlN6NnfFPL5RDdQ)。

## 3. 上下文切换的开销

[开发内功修炼之CPU篇](https://mp.weixin.qq.com/mp/appmsgalbum?__biz=MjM5Njg5NDgwNA==&action=getalbum&album_id=1372643250460540932&scene=126&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=0&fontScale=100) 里面对下面几种情况都做了实验对比，此处暂只说明结论。

开销实验的结论放一起便于对比参考（实验数据限于具体硬件，参考数量级即可）：

* 进程上下文切换：`2.7us到5.48us之间`
* 线程上下文切换：`3.8us`左右（TODO 数据和进程差不多，但实际应该更小？）
* 系统调用：`200ns`
* 协程切换：`120ns`（用户态）

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

测试方法：1）[lmbench](https://lmbench.sourceforge.net/) 2）写demo，使用`管道`进行父子进程间通信，触发上下文切换

**结论（参考结论）**：lmbench显示的进程上下文切换耗时从`2.7us到5.48us之间`

另外还有`间接开销`：切换后由于各种缓存并不热，速度运行会慢一些。如果跨CPU的话，之前热起来的TLB、L1、L2、L3因为运行的进程已经变了，所以局部性原理cache起来的代码、数据也都没有用了，导致新进程穿透到内存的IO会变多。

4、实验

1）上面测试进程上下文切换的代码，可见：[process_ctxswitch.c](https://github.com/xiaodongQ/prog-playground/blob/main/cpu/cswch_demo/process_ctxswch.c)，以及同级目录的统计平均脚本

TODO：自己运行demo统计的耗时基本都在 `0.8 us`左右

2）lmbench 要手动编译

```sh
# 一些依赖问题
bench.h:39:10: fatal error: rpc/rpc.h: No such file or directory
    yum install libtirpc-devel
    cp -rf /usr/include/tirpc/rpc/* /usr/include/rpc/
```

详情见：[进程/线程切换究竟需要多少开销？](https://mp.weixin.qq.com/s/uq5s5vwk5vtPOZ30sfNsOg) （或者[这里](https://zhuanlan.zhihu.com/p/79772089)，有demo代码链接）

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

**参考结论**：`3.8us`左右，切换耗时和进程差不多

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

参考开销：`200ns`

详情见：[一次系统调用开销到底有多大？](https://mp.weixin.qq.com/s/2nIDLeMR984_Sdgh01BHIQ)

### 3.4. 协程切换开销

1、切换时机

* 主动让出执行权
* 协程执行完成
* 调度策略触发

2、保存内容

* 局部变量和栈状态
* 寄存器状态
* 程序计数器

参考开销：`120ns`

详情见：[协程究竟比线程牛在什么地方？](https://mp.weixin.qq.com/s/N4W0-0cP1wlxtLILx3oXpg)

## 4. 线程池demo开销

上篇的demo代码：[thread_pool.cpp](https://github.com/xiaodongQ/prog-playground/blob/main/thread_pool/thread_pool.cpp)

```sh
[CentOS-root@xdlinux ➜ thread_pool git:(main) ✗ ]$ perf stat ./thread_pool
start:0, end:1250000, chunk sum:2500000, total:2500000, done count:1, task:8
start:1250000, end:2500000, chunk sum:2500000, total:5000000, done count:2, task:8
start:2500000, end:3750000, chunk sum:2500000, total:7500000, done count:3, task:8
start:3750000, end:5000000, chunk sum:2500000, total:10000000, done count:4, task:8
start:5000000, end:6250000, chunk sum:2500000, total:12500000, done count:5, task:8
start:6250000, end:7500000, chunk sum:2500000, total:15000000, done count:6, task:8
start:7500000, end:8750000, chunk sum:2500000, total:17500000, done count:7, task:8
start:8750000, end:10000000, chunk sum:2500000, total:20000000, done count:8, task:8
result: 20000000

 Performance counter stats for './thread_pool':

            # CPU利用率
             73.52 msec task-clock                #    1.335 CPUs utilized          
            # 上下文切换，频率为 0.299 K/sec
                22      context-switches          #    0.299 K/sec                  
                 0      cpu-migrations            #    0.000 K/sec                  
            # 缺页中断
             5,243      page-faults               #    0.071 M/sec                  
            # 时钟周期数，且对应的 CPU频率 4.503 GHz
       331,064,675      cycles                    #    4.503 GHz                      (82.47%)
         1,873,975      stalled-cycles-frontend   #    0.57% frontend cycles idle     (82.32%)
         2,876,154      stalled-cycles-backend    #    0.87% backend cycles idle      (80.14%)
            # 指令数，且每周期指令数 1.19
       393,566,861      instructions              #    1.19  insn per cycle         
                                                  #    0.01  stalled cycles per insn  (82.84%)
        68,372,865      branches                  #  929.930 M/sec                    (84.75%)
            # 分支预测错误次数，及占比
            49,859      branch-misses             #    0.07% of all branches          (87.48%)
            # 程序从开始到结束的实际经过时间
       0.055079000 seconds time elapsed
            # 程序在用户空间执行所花费的时间
       0.056267000 seconds user
            # 程序在内核空间执行系统调用等操作所花费的时间
       0.017682000 seconds sys
```

说下3个时间指标的关系：

* 一般情况下，`time elapsed`等于`user time`与`sys time`之和再加上可能存在的其他开销时间，在不考虑其他因素的理想情况下，有`time elapsed ≈ user time + sys time`。
    * time elapsed：也叫墙上时间（Wall Clock Time），是指从程序开始运行到结束所经过的实际时间，包括用户、内核、等待调度等方面的时间
    * user time：程序代码本身在CPU上运行所消耗的时间，不包括系统调用和等待其他资源的时间
    * sys time：程序在内核空间执行系统调用等操作所花费的时间
* 上面的`time elapsed`小于两者之和，这可能是因为在多线程或多进程环境下，程序在运行过程中有部分时间处于等待状态，或者存在多个线程 / 进程并行执行，使得实际经过的时间小于用户时间和系统时间的简单累加。
    * user time和sys time是将每个线程或进程在用户空间和内核空间执行的时间分别进行累加，所以会出现user time与sys time之和大于time elapsed的情况
    * 比如：一个程序有两个线程，线程 A 在用户空间执行了 `0.03` 秒，线程 B 在用户空间执行了 `0.04` 秒，它们是并行执行的，那么`user time`就是 `0.07` 秒，但实际从程序开始到结束的`time elapsed`可能只需要 `0.04` 秒，因为两个线程是同时进行的。

## 5. 源码跟踪：Linux进程是如何创建出来的？

TODO

跟着下文跟踪内核代码：

* [Linux进程是如何创建出来的？](https://mp.weixin.qq.com/s/ftrSkVvOr6s5t0h4oq4I2w)
* [进程和线程之间有什么根本性的区别？](https://mp.weixin.qq.com/s/--S94B3RswMdBKBh6uxt0w)

## 6. 小结

梳理学习进程、线程、系统调用、协程上下文切换相关开销，建立体感。

TODO项：内核代码跟踪、工具实验。

## 7. 参考

* [开发内功修炼之CPU篇](https://mp.weixin.qq.com/mp/appmsgalbum?__biz=MjM5Njg5NDgwNA==&action=getalbum&album_id=1372643250460540932&scene=126&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=0&fontScale=100)
* [听说你只知内存，而不知缓存？CPU表示很伤心！](https://mp.weixin.qq.com/s/PQTuFZO51an6OAe3WX4BVw)
* [TLB缓存是个神马鬼，如何查看TLB miss？](https://mp.weixin.qq.com/s/mssTS3NN7-w2df1vhYSuYw)
* [为什么HugePage能让Oracle数据库如虎添翼？](https://mp.weixin.qq.com/s/3Lb7-KuAlN6NnfFPL5RDdQ)
* [进程/线程切换究竟需要多少开销？](https://mp.weixin.qq.com/s/uq5s5vwk5vtPOZ30sfNsOg)
* [协程究竟比线程牛在什么地方？](https://mp.weixin.qq.com/s/N4W0-0cP1wlxtLILx3oXpg)
* [Linux进程是如何创建出来的？](https://mp.weixin.qq.com/s/ftrSkVvOr6s5t0h4oq4I2w)
* [进程和线程之间有什么根本性的区别？](https://mp.weixin.qq.com/s/--S94B3RswMdBKBh6uxt0w)
