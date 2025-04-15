---
title: Linux存储IO栈梳理（四） -- 通用块层
categories: [存储和数据库, IO栈]
tags: [存储, IO]
---

学习Linux内核存储栈中的通用块层（block layer）。

## 1. 背景

[Linux存储IO栈梳理（二） -- Linux内核存储栈流程和接口](https://xiaodongq.github.io/2024/08/13/linux-kernel-fs/) 中简单带过了一下通用块层，并在 [Linux存储IO栈梳理（三） -- eBPF和ftrace跟踪IO写流程](https://xiaodongq.github.io/2024/08/15/linux-write-io-stack) 中追踪IO写流程时追踪到对应的io调度处理相关堆栈，本篇来具体看下通用块层的对应流程。

另外，想起来之前看过的极客时间课程，回头看了下存储模块相关的系列文章：[基础篇：Linux 磁盘I/O是怎么工作的（上）](https://time.geekbang.org/column/article/77010)，发现作为概述和索引用来查漏补缺挺好的。之前更多的是对CPU/内存/存储/网络等对应有哪些观测工具和指标有个总览的了解，浮于“知道”（且容易忘）的层面，深入去看则发现有很多东西需要自己另外花心思去啃。这时再看文章有了不同的角度，收获到一些新的东西。

前段时间看别人说《代码整洁之道》常看常有新收获，还有[木鸟杂记](https://www.qtmuniao.com/)大佬对DDIA的重读分享([《DDIA 逐章精读》](https://ddia.qtmuniao.com/#/preface))，都提及在不同认知阶段看到不同的东西。最近在看CSAPP，回想~~早年~~大学时上课，大多都是浮于表面的被动接收，现在趁机会夯实基础，倒可以多思考一点，稍微深入一点。

## 2. 再看下IO栈全貌图

存储IO栈出现很多次了，贯穿整个系列学习。

此处还是放这张基于4.10内核的图，更高内核版本也可从出处中获取。

![linux存储栈_4.10内核](/images/linux-storage-stack-diagram_v4.10.svg)  
[出处](https://www.thomas-krenn.com/en/wiki/Linux_Storage_Stack_Diagram)

从图中可看到，BIO（Block I/O）有3个来源：`Page Cache`、`Direct I/O`、还有通过`网络`过来的block io，如`iscsi`。bio后面到了`通用块层（Block Layer）`。

### 2.1. 通用块层的作用

和`VFS`类似，为了减小不同`块设备`的差异带来的影响，Linux用一个统一的`通用块层`来管理各种不同的块设备。通用块层主要有两个作用：

1、第一个功能和VFS类似

* 向上，为文件系统和应用程序，提供访问块设备的标准接口；
* 向下，把各种异构的磁盘设备抽象为统一的块设备，并提供统一框架来管理这些设备的驱动程序。

2、第二个功能，通用块层还会给文件系统和应用程序发来的 I/O 请求排队（即`I/O调度`），并通过重新排序、请求合并等方式，提高磁盘读写的效率。

Linux 内核支持的几种 I/O 调度算法，分别为 `NONE`、`NOOP`、`CFQ` 以及 `DeadLine`。还有其他调度器，此处暂不展开，如mq-deadline、bfq。

* 1、`NONE`：更确切来说，并不能算 I/O 调度算法，因为它完全不使用任何 I/O 调度器，对文件系统和应用程序的 I/O 其实**不做任何处理**，常用在`虚拟机`中（此时磁盘 I/O 调度完全由物理机负责）。
* 2、`NOOP`（No-Operation）：是最简单的一种 I/O 调度算法。它实际上是一个`先入先出的队列`，只做一些最基本的请求合并，常用于 SSD 磁盘。
* 3、`CFQ`（Completely Fair Queueing），也被称为`完全公平调度器`，是现在很多发行版的**默认** I/O 调度器，它为每个进程维护了一个 I/O 调度队列，并按照`时间片`来均匀分布每个进程的 I/O 请求。
* 4、`DeadLine`调度算法：分别为读、写请求创建了不同的 I/O 队列，可以提高机械磁盘的吞吐量，并确保达到最终期限（deadline）的请求被优先处理。DeadLine 调度算法，多用在 I/O 压力比较重的场景，比如`数据库`等。

## 3. block层逻辑

先找几篇文章，进行梳理学习：

* [Linux block 层详解（3）- IO请求处理过程](https://zhuanlan.zhihu.com/p/501198341)
* [Linux 内核的 blk-mq（Block IO 层多队列）机制](https://www.bluepuni.com/archives/linux-blk-mq/)
* [linux IO Block layer 解析](https://www.cnblogs.com/Linux-tech/p/12961286.html)

### 3.1. block层框架

Linux上传统的块设备层和IO调度器（如`cfq`）主要是针对`HDD`设计的。HDD设备的随机IO性能很差，吞吐量大约是几百IOPS，延迟在毫秒级（耗时可参考[之前文章](https://xiaodongq.github.io/2024/07/11/linux-storage-io-stack/)的耗时体感图和IOPS对比），所以当时IO性能的瓶颈在硬件，而不是内核。

但是，随着高速`SSD`的出现并展现出越来越高的性能，百万级甚至千万级IOPS的数据访问已成为一大趋势，传统的块设备层已无法满足这么高的IOPS需求，逐渐成为系统IO性能的瓶颈。

为了适配现代存储设备高IOPS、低延迟的IO特征，新的块设备层框架`Block multi-queue（blk-mq）`应运而生。

block层单队列（single queue） 和 多队列（mutil-queue）架构图对比图：

![block层框架对比](/images/block-queue-framework.png)

**single-queue 框架（blk-sq）：**

在高IOPS的情况下，会有非常高的软件开销，主要体现在对锁的竞争上。使用`spinlock`来同步`请求队列（request queue）`的访问，向队列插入/删除、io提交、io排序和调度时都需要请求该锁。

**multi-queue 框架（blk-mq）：**

使用了**两层队列**，将单个请求队列锁的竞争分散多个队列中，极大的提高了Block Layer并发处理IO的能力，适用于高 IOPS 要求的多队列存储设备。

* `软件暂存队列（Software Staging Queue）`：blk-mq中为每个cpu分配一个软件队列，bio的提交/完成处理、IO请求暂存（合并、排序等）、IO请求标记、IO调度、IO记账都在这个队列上进行。
    * 由于每个cpu有单独的队列，所以每个cpu上的这些IO操作可以同时进行，而不存在锁竞争问题
    * 一般也称为 `software queue`、`software staging queue`、`ctx (context)`
    * 对应于数据结构 `blk_mq_ctx`
* `硬件派发队列（Hardware Dispatch Queue）`：blk-mq为存储器件的每个硬件队列（目前多数存储器件只有1个）分配一个硬件派发队列，负责存放软件队列往这个硬件队列派发的IO请求。
    * 在存储设备**驱动初始化时**，blk-mq会通过固定的`映射关系`将一个或多个软件队列`映射（map）`到一个硬件派发队列，之后这些软件队列上的IO请求会往对应的硬件队列上派发
    * 一般也称为 `hardware queue`、`hctx (hardware context)`、`hwq` 等
    * 对应于数据结构 `blk_mq_hw_ctx`
    * 进入该队列的 request 意味着已经经过了调度

### 3.2. 数据结构

相关的数据结构可以分成两大类：一是 IO 请求本身，二是管理 IO 请求用到的队列，理解这些数据结构是了解 block 层设计逻辑的基础。

#### 3.2.1. IO请求相关结构

按照 **`IO请求`** 的生命周期，IO请求被抽象成：

* `bio`
    * bio 是描述 `io请求` 的最小单位，bio 描述了数据的位置属性
    * 访问存储器件上相邻区域的`bio`可能会被**合并**，称为`bio merge`
    * 若bio的长度超过软件或者硬件的限制，`bio`会被**拆分**成多个，称为`bio split`
* `request`（简称 `rq`）
    * request是 `io调度` 的最小单位
    * block 层接收到一个 bio 后，这个bio将生成一个新的request，或者合并到已有的request中，所以一个request可能包含多个bio
    * 相邻区域的`request`可能会被合并，称为`request merge`
* `cmd`
    * `cmd`是`设备驱动`处理的IO请求，设备驱动程序根据器件协议，将`request`转换成`cmd`，然后发送给器件处理

上述结构和生命周期中涉及的操作示意图：

![io请求的生命周期](/images/bio-request-lifetime.png)

其中 bio2 被拆分，bio3、bio4 合并到一个 request 中，最后都由驱动转换成cmd（如`scsi_cmnd`结构），由存储设备处理。

#### 3.2.2. IO队列相关结构

上述的IO请求需要经过`多级缓冲队列`管理，包含如下队列：

* `plug list`
    * 进程私有的`plug list`，其中存放的是io请求（`request`/`rq`），引入这个缓冲队列的目的是为了性能
    * 进程提交一个`bio`后，短时间类很可能还会有新的bio，这些bio被暂存在`plug list`中，因为这个队列只有本进程能操作，所以不用加锁就可以进行`bio merge`操作
* `elevator q`
    * 其中存放的是io请求（`request`/`rq`）
    * single-queue的调度器有`noop`、`cfq`；multi-queue的调度器有`mq-deadline`、`bfq`、`kyber`。每个调度器有都实现了专门的数据结构管理`rq`（链表、红黑树等），这里统以`elevator q`称呼
        * 基本调度算法介绍，也可参考：[linux IO Block layer 解析](https://www.cnblogs.com/Linux-tech/p/12961286.html)
    * 一般情况下，调度器不会主动将`rq`移到设备分发队列中，而是由设备驱动程序`主动来取`rq。
* `device dispatch q`
    * 设备分发队列，也可以称作`hardware dispatch q`
    * 这是软件实现的队列。存储器件空闲时，其设备驱动程序主动从调度器中拉取一个rq存在设备分发队列中，分发队列中的rq按照先进先出顺序被封装成cmd下发给器件。
    * 对于multi-queue，设备分发队列包中还额外包含`per-core软件队列`，它是为硬件分发队列服务的，可以把它理解成设备分发队列中的一部分
* `hw q`
    * 硬件队列。队列中存放的是按器件协议封装的cmd，一些器件是单hw队列

上述block IO相关队列示意图如下：

![block IO相关队列](/images/block-io-queues.png)

#### 3.2.3. 内核中的结构定义

说明：数据结构相关示意图，详情可见 [linux IO Block layer 解析](https://www.cnblogs.com/Linux-tech/p/12961286.html)

`bio`结构：

```cpp
// linux-5.10.10/include/linux/blk_types.h
struct bio {
    struct bio          *bi_next;	/* request queue link */
    struct gendisk      *bi_disk;
    unsigned int        bi_opf;
    unsigned short      bi_flags;	/* status, etc and bvec pool number */
    unsigned short      bi_ioprio;
    unsigned short      bi_write_hint;
    blk_status_t        bi_status;
    u8                  bi_partno;
    atomic_t            __bi_remaining;
    struct bvec_iter    bi_iter;
    
    ...
    unsigned short      bi_vcnt;	/* how many bio_vec's */
    unsigned short      bi_max_vecs;	/* max bvl_vecs we can hold */
    atomic_t            __bi_cnt;	/* pin count */
    // 多个内存段
    struct bio_vec      *bi_io_vec;	/* the actual vec list */
    struct bio_set      *bi_pool;
    struct bio_vec      bi_inline_vecs[];
};
```

linux系统调用`readv`、`writev`支持`scatter-gather I/O`，所以bio的内存端需用多个`[ page地址， 页内偏移， 长度 ]`描述不连续的内存段，每一个[ page地址， 页内偏移， 长度 ]在linux中称为`bio_vector`（对应上面`bio`结构中的`struct bio_vec	 *bi_io_vec;`成员）。

`request`结构：

```cpp
// linux-5.10.10/include/linux/blkdev.h
struct request {
    struct request_queue    *q;
    struct blk_mq_ctx       *mq_ctx;
    struct blk_mq_hw_ctx    *mq_hctx;
    unsigned int cmd_flags; /* op and common flags */
    req_flags_t rq_flags;

    int tag;
    int internal_tag;

    /* the following two fields are internal, NEVER access directly */
    unsigned int __data_len;    /* total data len */
    sector_t __sector;          /* sector cursor */

    struct bio *bio;
    struct bio *biotail;

    struct list_head queuelist;
    ...
};
```

`scsi_cmnd`结构：

```cpp
// linux-5.10.10/include/scsi/scsi_cmnd.h
struct scsi_cmnd {
    struct scsi_request req;
    struct scsi_device *device;
    struct list_head eh_entry; /* entry for the host eh_cmd_q */
    struct delayed_work abort_work;

    struct rcu_head rcu;
    ...
    unsigned short cmd_len;
    enum dma_data_direction sc_data_direction;

    /* These elements define the operation we are about to perform */
    unsigned char *cmnd;

    /* These elements define the operation we ultimately want to perform */
    struct scsi_data_buffer sdb;
    struct scsi_data_buffer *prot_sdb;

    unsigned underflow;
    unsigned transfersize;
    struct request *request;
    ...
};
```

### 3.3. funcgraph调用栈

block层提供了`submit_bio`的接口，上层可以调用这个接口来提交请求。

在 [Linux存储IO栈梳理（三） -- eBPF和ftrace跟踪IO写流程](https://xiaodongq.github.io/2024/08/15/linux-write-io-stack) 中，通过`funcgraph`追踪到了block层的调用栈，不过层数太多，完整没贴在文章中，完整内容见：[O_DIRECT写入调用栈](/images/srcfiles/funcgragh_write_direct_stack.txt)。

这里贴一下block层相关的调用栈（去除了一些细节和其他调用，可通过括号匹配层级）：

```sh
[root@iZ2zeftv45jk9frk8u0d0rZ bin]# ./funcgraph -H -p 8016 vfs_write
Tracing "vfs_write" for PID 8016... Ctrl-C to end.
# tracer: function_graph
#
# CPU  DURATION                  FUNCTION CALLS
# |     |   |                     |   |   |   |
 0)               |  vfs_write() {
 0)               |    irq_enter_rcu() {
 0)   0.247 us    |      irqtime_account_irq();
 0)   0.808 us    |    }
                       ...
 0)               |    new_sync_write() {
 0)               |      ext4_file_write_iter() {
 0)               |        ext4_dio_write_iter() {
                             ...
 0)               |          iomap_dio_rw() {
 0)               |            __iomap_dio_rw() {
 0)               |              iomap_apply() {
                                   ...
                                   # 追踪到有多个iomap_dio_actor，这里只保留了一个
 0)               |                iomap_dio_actor() {
 0)               |                  iomap_dio_bio_actor() {
                                       ...
 0)               |                    iomap_dio_submit_bio() {
                                         # 数据提交到block层
 0)               |                      submit_bio() {
 0)               |                        submit_bio_checks() {
                                             ...
 0)   6.840 us    |                        } /* submit_bio_checks */
 0)               |                        submit_bio_noacct_nocheck() {
 0)   0.152 us    |                          blk_cgroup_bio_start();
 0)   0.194 us    |                          ktime_get();
 0)               |                          __submit_bio_noacct_mq() {
 0)               |                            blk_queue_enter() {
 0)   0.448 us    |                              rcu_read_unlock_strict();
 0)   0.156 us    |                              rcu_read_unlock_strict();
 0)   1.335 us    |                            }
                                               # 新的块设备层框架Block multi-queue（blk-mq）
 0)               |                            blk_mq_submit_bio() {
 0)   0.422 us    |                              blk_queue_bounce();
                                                 # bio 拆分（split）
 0)   0.395 us    |                              __blk_queue_split();
 0)   0.224 us    |                              bio_integrity_prep();
                                                 # bio 合并（merge）
 0)   0.152 us    |                              blk_attempt_plug_merge();
 0)               |                              __blk_mq_sched_bio_merge() {
 0)               |                                dd_bio_merge() {
 0)   0.322 us    |                                  _raw_spin_lock();
 0)               |                                  blk_mq_sched_try_merge() {
 0)               |                                    elv_merge() {
 0)   0.465 us    |                                      elv_rqhash_find();
 0)               |                                      dd_request_merge() {
 0)   0.309 us    |                                        elv_rb_find();
 0)   0.876 us    |                                      }
 0)   2.318 us    |                                    }
 0)   2.703 us    |                                  }
 0)   3.574 us    |                                }
 0)   4.205 us    |                              }
 0)               |                              __rq_qos_throttle() {
 0)   0.310 us    |                                blkcg_iolatency_throttle();
 0)   1.547 us    |                              }
                                                 # 分配request
 0)               |                              __blk_mq_alloc_request() {
                                                   ...
 0)   3.376 us    |                              }
 0)   0.146 us    |                              __rq_qos_track();
 0)               |                              blk_account_io_start() {
                                                   ...
 0)   2.892 us    |                              }
 0)   0.248 us    |                              blk_add_rq_to_plug();
 0) + 16.640 us   |                            }
 0) + 18.884 us   |                          }
 0) + 20.092 us   |                        }
 0) + 27.731 us   |                      }
 0) + 28.220 us   |                    }
 0) + 44.491 us   |                  }
 0) + 44.894 us   |                }
 0)   0.160 us    |                ext4_iomap_end();
 0) + 51.164 us   |              }
                                 ...
 0)               |              blk_finish_plug() {
 0)   0.252 us    |                flush_plug_callbacks();
 0)               |                blk_mq_flush_plug_list() {
 0)               |                  blk_mq_sched_insert_requests() {
                                        ...
 0) + 39.086 us   |                  }
 0) + 39.507 us   |                }
                                   ...
 0) + 40.725 us   |              }
                                 # bio调度
 0)               |              blk_io_schedule() {
 0)               |                io_schedule_timeout() {
 0)               |                  schedule_timeout() {
                                       ...
                                       # 调度
 0)               |                    schedule() {
                                         ...
 0)   0.164 us    |                      update_nr_uninterruptible_fair();
 0)               |                      dequeue_task_fair() {
 0)               |                        dequeue_entity() {
                                             ...
 0)   4.464 us    |                        }
 0)   0.150 us    |                        hrtick_update();
 0)   5.087 us    |                      }
                                         ...
 0) ! 859.440 us  |                    }
                                       ...
 0) ! 866.350 us  |                  }
 0) ! 866.856 us  |                }
 0) ! 867.403 us  |              }
 0)   1007.251 us |            }
 0)               |            iomap_dio_complete() {
 0)   0.373 us    |              ext4_dio_write_end_io();
 0)   0.284 us    |              wake_up_bit();
 0)   0.719 us    |              kfree();
 0)   3.587 us    |            }
 0)   1011.723 us |          }
 0)   1137.818 us |        }
 0)   1138.400 us |      }
 0)   1139.020 us |    }
 0)   0.984 us    |    __fsnotify_parent();
 0)   1168.973 us |  }
```

## 4. 扩展：blktrace 工具介绍

看了下`blktrace`这个工具，加入工具箱，后续需要定位block层问题备用。

可参考：[利用 BLKTRACE 和 BTT 分析磁盘 IO 性能](https://www.xtplayer.cn/linux/disk/blktrace-btt-test-io/#google_vignette)

* `blktrace` 提供了对通用块层（block layer）的 I/O 跟踪机制。它可以生成跟踪文件，记录每个 I/O 请求到达块层的时间戳以及请求的详细信息。
* `btt（Block Trace Tools）`是一套用于分析由 `blktrace` 生成的跟踪文件的工具，它包括多个脚本和程序，用于处理和可视化跟踪数据，以便更容易地理解 I/O 行为。

## 5. 扩展：如何查看系统block设备信息

这里提到了block层，扩展一下，说明下实际环境中如何通过`sys`文件系统，来进一步查看`/dev`下块设备（block device）和其他设备文件的信息。

### 5.1. sysfs

sysfs 是 Linux 内核中一种特殊的文件系统，它主要用于在内核和用户空间之间传递设备信息和状态。sysfs 提供了一个统一的接口，使得用户空间程序可以访问和控制内核中的各种设备和子系统，而无需直接与硬件交互或深入理解底层的设备驱动程序。

sysfs 的根目录是 /sys，从这里开始，可以浏览整个设备树，访问各种设备和子系统的相关信息。例如，/sys/class 目录包含了按类别分类的所有设备，如 `/sys/class/block` 包含所有块设备的信息，/sys/class/net 包含所有网络设备的信息。

### 5.2. /sys/block

`/sys/class/block` 和 `/sys/block`里都能看到block设备相关信息。若一个块设备有多个分区，`/sys/class/block`里是平铺的，`/sys/block`里则是每个分区作为子目录。这里先基于`/sys/block`看下。

`/sys/block`目录是Linux内核用于存储和提供`块设备`相关信息的虚拟文件系统的一部分。在这个目录下，可以找到系统中所有块设备的子目录，每个子目录代表一个具体的块设备，如硬盘、SSD、USB 存储设备等。块设备是指那些可以进行随机访问的设备，数据可以按块为单位进行读写操作。

```sh
[root@local ~]# ll /sys/block/sdg/ 
total 0
-r--r--r-- 1 root root 4096 Aug 28 16:43 alignment_offset
lrwxrwxrwx 1 root root    0 Aug 28 16:33 bdi -> ../../../../../../../../virtual/bdi/8:96
-r--r--r-- 1 root root 4096 Aug 28 16:43 capability
-r--r--r-- 1 root root 4096 Aug 28 16:33 dev
# 包含设备的硬件信息，如制造商、型号、序列号等
lrwxrwxrwx 1 root root    0 Aug 28 16:22 device -> ../../../3:0:0:0
-r--r--r-- 1 root root 4096 Aug 28 16:43 discard_alignment
-r--r--r-- 1 root root 4096 Aug 28 16:43 events
-r--r--r-- 1 root root 4096 Aug 28 16:43 events_async
-rw-r--r-- 1 root root 4096 Aug 28 16:43 events_poll_msecs
-r--r--r-- 1 root root 4096 Aug 28 16:43 ext_range
-r--r--r-- 1 root root 4096 Aug 28 16:33 hidden
drwxr-xr-x 2 root root    0 Aug 28 16:21 holders
-r--r--r-- 1 root root 4096 Aug 28 16:43 inflight
drwxr-xr-x 3 root root    0 Aug 28 16:33 mq
drwxr-xr-x 2 root root    0 Aug 28 16:33 power
# 包含设备队列的信息，如读写策略、I/O 调度算法、设备是否为旋转式磁盘（rotational 文件）等
drwxr-xr-x 3 root root    0 Aug 28 16:21 queue
-r--r--r-- 1 root root 4096 Aug 28 16:43 range
# 指示设备是否可移动（例如，USB 设备）
-r--r--r-- 1 root root 4096 Aug 28 16:33 removable
-r--r--r-- 1 root root 4096 Aug 28 16:33 ro
# 块设备可能有多个分区，每个分区子目录也包含类似的信息，如分区的大小、类型等
# 分区里有 start：显示分区起始位置的扇区号
drwxr-xr-x 5 root root    0 Aug 28 16:33 sdg1
drwxr-xr-x 5 root root    0 Aug 28 16:33 sdg2
drwxr-xr-x 5 root root    0 Aug 28 16:33 sdg3
# 设备或分区的总扇区个数
-r--r--r-- 1 root root 4096 Aug 28 16:21 size
drwxr-xr-x 2 root root    0 Aug 28 16:33 slaves
# 显示设备的统计信息，如读写操作次数、读写字节数、等待时间等
-r--r--r-- 1 root root 4096 Aug 28 16:21 stat
lrwxrwxrwx 1 root root    0 Aug 28 16:33 subsystem -> ../../../../../../../../../class/block
drwxr-xr-x 2 root root    0 Aug 28 16:33 trace
# 触发 udev 事件，通知系统设备状态的改变
-rw-r--r-- 1 root root 4096 Aug 28 16:43 uevent
```

看下uevent内容：

```sh
[root@local ~]# cat  /sys/block/sdg/uevent
MAJOR=8
MINOR=96
DEVNAME=sdg
DEVTYPE=disk
```

### 5.3. 主、次设备号

在 Linux 中，每个设备都被分配了一个`唯一的设备号`，这个设备号由`主设备号（MAJOR）`和`次设备号（MINOR）`组成。设备号是操作系统内核用于识别和管理硬件设备的一种方式。块设备，如硬盘、SSD 和 USB 存储设备，也不例外。

* 主设备号（MAJOR）：标识设备驱动程序。不同的设备类型通常对应不同的主设备号。
    * 例如，8 通常代表 IDE 硬盘，202 代表 SCSI 设备，65 代表 SD 和 MMC 卡等。
    * 主设备号帮助内核确定应该使用哪个驱动程序来与设备通信。
* 次设备号（MINOR）：在同一类设备中区分不同的物理设备或设备的不同部分（如分区）。
    * 例如，在同一个 SCSI 设备中，不同的次设备号可以代表不同的逻辑单元（LUNs）或者在同一个硬盘上，不同的次设备号代表不同的分区。

在`内核层面`，设备号用于查找和引用设备驱动程序，以及管理设备的 I/O 请求。在`用户空间`，设备号用于创建和管理设备节点，以及在编程中打开和操作设备文件。

在 Linux 中，`设备文件`（如 /dev/sda）实际上是一个特殊类型的文件，称为`设备节点`。当你在 /dev 目录下看到设备文件时，它们背后都有一个与之关联的设备号。

例如：假设有一个名为 sda 的硬盘，它是一个 SCSI 类型的设备，主设备号为 8（实际上，现代 Linux 中 SCSI 硬盘的主设备号可能是 202 或其他）。假设 sda 的次设备号为 0，那么这个设备的完整设备号就是 (8, 0) 或 (202, 0)。对于 sda 上的第一个分区 sda1，它的次设备号可能是 1，因此设备号为 (8, 1) 或 (202, 1)。

stat可以查看设备文件的主设备号和次设备号：（`Device type: 8,16`）

```sh
[root@local ~]# stat /dev/sdb
  File: /dev/sdb
  Size: 0               Blocks: 0          IO Block: 4096   block special file
Device: 0,5     Inode: 161         Links: 1     Device type: 8,16
Access: (0660/brw-rw----)  Uid: (    0/    root)   Gid: (    6/    disk)
Access: 2024-08-28 16:35:24.375317114 +0800
Modify: 2024-08-26 19:42:03.769065231 +0800
Change: 2024-08-26 19:42:03.769065231 +0800
 Birth: -
```

sys文件系统也可查看对应的设备号：

```sh
[root@local ~]# ll /sys/class/block/sdb/
-r--r--r-- 1 root root 4096 Aug 28 17:08 alignment_offset
lrwxrwxrwx 1 root root    0 Aug 28 17:08 bdi -> ../../../../../../../../../../../../../../virtual/bdi/8:16
-r--r--r-- 1 root root 4096 Aug 28 17:08 capability
...
```

### 5.4. /dev/disk/和/dev/block/

上面提到的：当你在 /dev 目录下看到设备文件时，它们背后都有一个与之关联的设备号。

* /dev/下的设备文件：

```sh
[root@local ~]# ll /dev/
drwxr-xr-x 2 root root         580 Aug 28 10:04 block
drwxr-xr-x 3 root root          60 Aug 27 03:41 bus
...
drwxr-xr-x 8 root root         180 Aug 27 03:41 cpu
brw-rw---- 1 root disk      8,   0 Aug 28 10:03 sda
brw-rw---- 1 root disk      8,  16 Aug 26 19:42 sdb
brw-rw---- 1 root disk      8,  48 Aug 26 19:42 sdd
...
```

* `/dev/block` 包含实际的设备文件，是内核用来访问硬件的接口。

可看到里面的文件软链接到外层的设备文件(如/dev/sda)，这里直接可以看到主、次设备号：

```sh
[root@local ~]# ll /dev/block/
lrwxrwxrwx 1 root root 7 Aug 26 19:42 253:0 -> ../dm-0
...
lrwxrwxrwx 1 root root 8 Aug 26 19:42 7:0 -> ../loop0
lrwxrwxrwx 1 root root 8 Aug 26 19:42 7:1 -> ../loop1
...
lrwxrwxrwx 1 root root 6 Aug 28 10:03 8:0 -> ../sda
lrwxrwxrwx 1 root root 6 Aug 26 19:42 8:112 -> ../sdh
lrwxrwxrwx 1 root root 7 Aug 26 19:42 8:113 -> ../sdh1
lrwxrwxrwx 1 root root 6 Aug 28 10:03 8:128 -> ../sdi
...
```

* `/dev/disk` 包含指向这些设备文件的符号链接，提供了更易于管理的方式。

通过使用 `/dev/disk` 下的符号链接，可以避免因设备顺序变化而导致的错误。

例如，如果你拔掉一个USB驱动器后又插入，它的设备节点可能从 /dev/sdb 变为 /dev/sdc，但使用UUID或标签作为引用则不会改变。

```sh
[root@local ~]# ll /dev/disk/
total 0
drwxr-xr-x 2 root root 800 Aug 28 10:04 by-id
drwxr-xr-x 2 root root  60 Aug 26 19:42 by-partlabel
drwxr-xr-x 2 root root 120 Aug 26 19:42 by-partuuid
drwxr-xr-x 2 root root 440 Aug 28 10:04 by-path
drwxr-xr-x 2 root root 300 Aug 28 10:04 by-uuid
```

下面看下各个维度具体的信息，都软链接到了/dev/对应的设备：

```sh
[root@local ~]# ll /dev/disk/by-uuid/
total 0
lrwxrwxrwx 1 root root  9 Aug 26 19:42 2ed88d87-0c31-4437-a477-908f06f29e14 -> ../../sdb
lrwxrwxrwx 1 root root  9 Aug 26 19:42 496980bb-989c-42ff-bd35-fe6136c5d353 -> ../../sde
lrwxrwxrwx 1 root root  9 Aug 26 19:42 4cf1a2e9-13ce-484e-a6a2-2c4bbe056103 -> ../../sdf


[root@local ~]# ll /dev/disk/by-path/
total 0
lrwxrwxrwx 1 root root  9 Aug 26 19:42 pci-0000:00:17.0-ata-3 -> ../../sdg
lrwxrwxrwx 1 root root  9 Aug 26 19:42 pci-0000:00:17.0-ata-3.0 -> ../../sdg
lrwxrwxrwx 1 root root 10 Aug 26 19:42 pci-0000:00:17.0-ata-3.0-part1 -> ../../sdg1

[root@local ~]# ll /dev/disk/by-partuuid/
total 0
lrwxrwxrwx 1 root root 10 Aug 26 19:42 01854901-bbc9-4532-9362-2c87f900e290 -> ../../sdg1
lrwxrwxrwx 1 root root 10 Aug 26 19:42 25921828-a308-48d6-b84b-d63fad62f0e5 -> ../../sdh1

[root@local ~]# ll /dev/disk/by-id
total 0
lrwxrwxrwx 1 root root  9 Aug 26 19:42 ata-ST1000NX0313_W472MP7P -> ../../sdg
lrwxrwxrwx 1 root root 10 Aug 26 19:42 ata-ST1000NX0313_W472MP7P-part1 -> ../../sdg1
lrwxrwxrwx 1 root root 10 Aug 26 19:42 ata-ST1000NX0313_W472MP7P-part2 -> ../../sdg2
lrwxrwxrwx 1 root root 10 Aug 26 19:42 ata-ST1000NX0313_W472MP7P-part3 -> ../../sdg3
lrwxrwxrwx 1 root root  9 Aug 28 10:03 ata-ST1000VX000-1CU162_S1DD1B7F -> ../../sdj


[root@local ~]# ll /dev/disk/by-partlabel/
total 0
lrwxrwxrwx 1 root root 10 Aug 26 19:42 'EFI\x20System\x20Partition' -> ../../sdg1
```

## 6. 小结

简单学习梳理了通用块层的结构，了解了其中对应的数据结构和基本操作。具体流程暂未深入，后续根据实际场景按需再具体跟踪。

## 7. 参考

1、[基础篇：Linux 磁盘I/O是怎么工作的（上）](https://time.geekbang.org/column/article/77010)

2、[利用 BLKTRACE 和 BTT 分析磁盘 IO 性能](https://www.xtplayer.cn/linux/disk/blktrace-btt-test-io/#google_vignette)

3、 [Linux block 层详解（3）- IO请求处理过程](https://zhuanlan.zhihu.com/p/501198341)

4、 [Linux 内核的 blk-mq（Block IO 层多队列）机制](https://www.bluepuni.com/archives/linux-blk-mq/)

5、 [linux IO Block layer 解析](https://www.cnblogs.com/Linux-tech/p/12961286.html)

6、GPT
