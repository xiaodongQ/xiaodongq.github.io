---
title: RocksDB学习笔记（三） -- RocksDB中的一些特性设计和高性能相关机制
description: 通过官方博客了解RocksDB的一些特性设计，并梳理下高性能相关的机制。
categories: [存储和数据库, RocksDB]
tags: [存储, RocksDB]
---


## 1. 引言

前两篇中梳理了RocksDB的总体结构和基本流程，本篇学习 [RocksDB Blog](https://rocksdb.org/blog/) 中的部分文章，了解下RocksDB的一些特性设计，并梳理RocksDB中的相关高性能机制。

此外，也梳理下其他C++和Linux相关的一些高性能机制，比如 **<mark>coroutine</mark>** 和 **<mark>io_uring</mark>**。

1、官网博客文章（按时间顺序，早期文章在前面）：

* [Indexing SST Files for Better Lookup Performance](https://rocksdb.org/blog/2014/04/21/indexing-sst-files-for-better-lookup-performance.html)
* [Reducing Lock Contention in RocksDB](https://rocksdb.org/blog/2014/05/14/lock.html)
* [Improving Point-Lookup Using Data Block Hash Index](https://rocksdb.org/blog/2018/08/23/data-block-hash-index.html)
* [RocksDB Secondary Cache](https://rocksdb.org/blog/2021/05/27/rocksdb-secondary-cache.html)
* [Asynchronous IO in RocksDB](https://rocksdb.org/blog/2022/10/07/asynchronous-io-in-rocksdb.html)
* [Reduce Write Amplification by Aligning Compaction Output File Boundaries](https://rocksdb.org/blog/2022/10/31/align-compaction-output-file.html)

2、RocksDB调优（当做文章索引，后续按需检索）

* [RocksDB Tuning Guide](https://github.com/facebook/rocksdb/wiki/RocksDB-Tuning-Guide)
    * wiki里面`Performance`分组下的一些文章，比如 [Write Stalls](https://github.com/facebook/rocksdb/wiki/Write-Stalls)
* [Rocksdb 调优指南](https://www.cnblogs.com/lygin/p/17158774.html)

3、另外的一些性能相关博客和文章：

* [Rocksdb加SPDK改善吞吐能力建设](https://chenxu14.github.io/2021/02/04/rocksdb-perfomance-improve.html)
* [从 C++20 协程，到 Asio 的协程适配](https://www.bluepuni.com/archives/cpp20-coroutine-and-asio-coroutine)
    * PS：发现之前也看过该博主相关文章，[梳理存储io栈](https://xiaodongq.github.io/2024/08/26/linux-io-stack-block/) 时看过的 [Linux 内核的 blk-mq（Block IO 层多队列）机制](https://www.bluepuni.com/archives/linux-blk-mq/)
* 还是上面博客中的一些文章
    * [从无栈协程，到 Asio 的协程实现](https://www.bluepuni.com/archives/stackless-coroutine-and-asio-coroutine/)
    * [实现一个简单的协程](https://www.bluepuni.com/archives/implements-coroutine/)
    * [Linux 内核的 io_uring 任务调度](https://www.bluepuni.com/archives/linux-io-uring-task-scheduling/)
    * [实现一个短至 200 行的 io_uring 协程](https://www.bluepuni.com/archives/io-uring-coroutine-example-in-200-lines/)
    * 博客里很多其他历史文章也值得一读，暂列几篇
        * [Linux 内核的 CFS 任务调度](https://www.bluepuni.com/archives/cfs-basic/)
        * [[论文阅读] A Top-Down Method for Performance Analysis](https://www.bluepuni.com/archives/paper-reading-a-top-down-method-for-performance-analysis/)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. RocksDB相关博客

### 2.1. 索引SST文件以提升查找性能

1、可以先了解下 **`LevelDB`**中的`SST`文件结构（可见：[LevelDB学习笔记（五） -- sstable实现](https://xiaodongq.github.io/2024/08/07/leveldb-sstable)）：

![leveldb-sstable-overview](/images/leveldb-sstable-overview.svg)  
[出处](https://leveldb-handbook.readthedocs.io/zh/latest/sstable.html)，在此基础上添加说明

2、**`RocksDB`**中的SST结构：

除了`meta block 2`对应的`index block`的位置不同外，`RocksDB`中还新增了另外几种元数据：3-`compression dictionary block`、4-`range deletion block`、5-`stats block`，以及预留的元数据block扩展。

```sh
<beginning_of_file>
[data block 1]
[data block 2]
...
[data block N]
[meta block 1: filter block]                  (see section: "filter" Meta Block)
[meta block 2: index block]
[meta block 3: compression dictionary block]  (see section: "compression dictionary" Meta Block)
[meta block 4: range deletion block]          (see section: "range deletion" Meta Block)
[meta block 5: stats block]                   (see section: "properties" Meta Block)
...
[meta block K: future extended block]  (we may add more meta blocks in the future)
[metaindex block]
[Footer]                               (fixed size; starts at file_size - sizeof(Footer))
<end_of_file>
```

3、[Indexing SST Files for Better Lookup Performance](https://rocksdb.org/blog/2014/04/21/indexing-sst-files-for-better-lookup-performance.html) 该篇文章中的设计：

* 由于各SST文件的数据范围是**有序**的，本层文件和其下一层文件的**相对位置不会变化**，
* 那么可以在SST文件进行`compaction`时，对每个文件预先构造2个指向下一级SST文件的指针，分别指向下一层中左侧和右侧SST文件（并作为SST文件的一部分），用来**加速二分查找**。
    * 这样就避免了本层没找到符合条件的key时，下一层再对**所有**SST文件再做二分查找
* 这个设计方式类似`分数级联`，可了解 [Fractional cascading](https://en.wikipedia.org/wiki/Fractional_cascading)

比如下面要查找key为`80`的记录，`level1`中没有符合的SST，找`level2`中处于`level1里file1`左侧的3个文件即可：

```
                                         file 1                                          file 2
                                      +----------+                                    +----------+
level 1:                              | 100, 200 |                                    | 300, 400 |
                                      +----------+                                    +----------+
           file 1     file 2      file 3      file 4       file 5       file 6       file 7       file 8
         +--------+ +--------+ +---------+ +----------+ +----------+ +----------+ +----------+ +----------+
level 2: | 40, 50 | | 60, 70 | | 95, 110 | | 150, 160 | | 210, 230 | | 290, 300 | | 310, 320 | | 410, 450 |
         +--------+ +--------+ +---------+ +----------+ +----------+ +----------+ +----------+ +----------+
```

### 2.2. 减少锁竞争

[Reducing Lock Contention in RocksDB](https://rocksdb.org/blog/2014/05/14/lock.html)

RocksDB在**内存态**使用时，`锁`更容易成为瓶颈。RocksDB中的一些优化锁使用的措施：

* 1、对于**读**操作，引入 **<mark>`super version`</mark>（`SuperVersion`类）** 来整合`memtable`、`immutable memtables`和`version`的引用计数，避免需频繁各自加锁进行引用计数的增减
* 2、使用 <mark>std::atomic</mark> 替换了部分 `引用计数`（通常需要锁保护），减少 `mutex` 的使用
* 3、在`读`查询中，获取`super version`和引用计数是 <mark>lock-free</mark> 操作
* 4、避免在`mutex`中进行磁盘IO，包含事务日志、日志信息打印。事务日志记录调整到锁外；日志信息打印则先记录到`log buffer`，内容中带时间戳，再在 <mark>锁外**延迟写**</mark>
* 5、减少在`mutex`中进行对象创建。在RocksDB的部分场景中，对象创建会涉及`malloc`操作，需要lock一些共享数据结构
    * `std::vector`内部会使用`malloc`，RocksDB中引入了 **<mark>autovector</mark>**，其中会`预分配`一些数据，很适合操作元数据信息
    * 创建`iterator`通常需要**加锁**且涉及`malloc`、合并`iterator`还可能涉及排序，开销比较昂贵。RocksDB中调整为仅增加引用计数，并在`iterator`创建前就**释放锁**。
* 6、LRU缓存（用于`block cache`和`table cache`）中的锁处理：
    * 读查询时，引入 <mark>**旁路（`bypass`）** table cache</mark> 模式，通过`options.max_open_files=-1`开启该模式，并由用户负责`SST`文件的缓存和读取，而不通过LRU缓存
    * 对于<mark>内存文件系统（ramfs/tmpfs）</mark>，则引入 [PlainTable Format](https://github.com/facebook/rocksdb/wiki/PlainTable-Format) 格式来优化`SST`，不通过`block`的方式组织数据，当然也没有`block cache`

经过上述优化后，锁不再是瓶颈。内存负载下的性能数据，可见：[RocksDB In Memory Workload Performance Benchmarks](https://github.com/facebook/rocksdb/wiki/RocksDB-In-Memory-Workload-Performance-Benchmarks)。


## 3. 小结


## 4. 参考

* [facebook/rocksdb](https://github.com/facebook/rocksdb/)
* [RocksDB Blog](https://rocksdb.org/blog/)
* [Caturra's Blog](https://www.bluepuni.com/)
* [RocksDB-Wiki](https://github.com/facebook/rocksdb/wiki)
