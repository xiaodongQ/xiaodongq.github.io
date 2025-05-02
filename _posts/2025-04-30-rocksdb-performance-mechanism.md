---
title: RocksDB学习笔记（三） -- RocksDB中的一些特性设计和高性能相关机制
description: 通过官方博客了解RocksDB的一些特性设计，并梳理下高性能相关的机制。
categories: [存储和数据库, RocksDB]
tags: [存储, RocksDB]
---


## 1. 引言

前两篇中梳理了RocksDB的总体结构和基本流程，本篇学习 [RocksDB Blog](https://rocksdb.org/blog/) 中的部分文章，了解下RocksDB的一些特性设计，并梳理RocksDB中的相关高性能机制。

此外，也梳理下其他C++和Linux相关的一些高性能机制，比如 *<mark>coroutine</mark>* 和 *<mark>io_uring</mark>*。

1、官网博客文章（按时间顺序，早期文章在前面）：

* [Indexing SST Files for Better Lookup Performance](https://rocksdb.org/blog/2014/04/21/indexing-sst-files-for-better-lookup-performance.html)
* [Reducing Lock Contention in RocksDB](https://rocksdb.org/blog/2014/05/14/lock.html)
* [Improving Point-Lookup Using Data Block Hash Index](https://rocksdb.org/blog/2018/08/23/data-block-hash-index.html)
* [RocksDB Secondary Cache](https://rocksdb.org/blog/2021/05/27/rocksdb-secondary-cache.html)
* [Asynchronous IO in RocksDB](https://rocksdb.org/blog/2022/10/07/asynchronous-io-in-rocksdb.html)
* [Reduce Write Amplification by Aligning Compaction Output File Boundaries](https://rocksdb.org/blog/2022/10/31/align-compaction-output-file.html)

2、RocksDB调优（当做文章索引，后续按需检索）

* [RocksDB Tuning Guide](https://github.com/facebook/rocksdb/wiki/RocksDB-Tuning-Guide)
    * 还有wiki里面`Performance`分组下的一些文章，比如 [Write Stalls](https://github.com/facebook/rocksdb/wiki/Write-Stalls)
* [Rocksdb 调优指南](https://www.cnblogs.com/lygin/p/17158774.html)

3、另外的一些性能相关博客和文章：

* [z_stand -- RocksDB相关博客文章](https://vigourtyy-zhg.blog.csdn.net/category_10058454.html)
    * 作者对RocksDB的一些模块梳理和公开论文笔记值得一看，可作为后续参考
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

* 1、对于**读**操作，引入 **<mark>super version</mark>（`SuperVersion`类）** 来整合`memtable`、`immutable memtables`和`version`的引用计数，避免需频繁各自加锁进行引用计数的增减
* 2、使用 <mark>std::atomic</mark> 替换了部分 `引用计数`（通常需要锁保护），减少 `mutex` 的使用
* 3、在`读`查询中，获取`super version`和引用计数是 <mark>lock-free</mark> 操作
* 4、避免在`mutex`中进行磁盘IO，包含事务日志、日志信息打印。事务日志记录调整到锁外；日志信息打印则先记录到`log buffer`，内容中带时间戳，再在 **<mark>锁外延迟写</mark>**
* 5、减少在`mutex`中进行对象创建。在RocksDB的部分场景中，对象创建会涉及`malloc`操作，需要lock一些共享数据结构
    * `std::vector`内部会使用`malloc`，RocksDB中引入了 **<mark>autovector</mark>**，其中会`预分配`一些数据，很适合操作元数据信息
    * 创建`iterator`通常需要**加锁**且涉及`malloc`、合并`iterator`还可能涉及排序，开销比较昂贵。RocksDB中调整为仅增加引用计数，并在`iterator`创建前就**释放锁**。
* 6、LRU缓存（用于`block cache`和`table cache`）中的锁处理：
    * 读查询时，引入 **<mark>旁路（bypass）table cache</mark>** 模式，通过`options.max_open_files=-1`开启该模式，并由用户负责`SST`文件的缓存和读取，而不通过LRU缓存
    * 对于<mark>内存文件系统（ramfs/tmpfs）</mark>，则引入 [PlainTable Format](https://github.com/facebook/rocksdb/wiki/PlainTable-Format) 格式来优化`SST`，不通过`block`的方式组织数据，当然也没有`block cache`

经过上述优化后，锁不再是瓶颈。内存负载下的性能数据，可见：[RocksDB In Memory Workload Performance Benchmarks](https://github.com/facebook/rocksdb/wiki/RocksDB-In-Memory-Workload-Performance-Benchmarks)。

### 2.3. RocksDB中的异步IO

[Asynchronous IO in RocksDB](https://rocksdb.org/blog/2022/10/07/asynchronous-io-in-rocksdb.html)

`Iterator` 和 `MultiGet` 中利用异步IO优化性能。`ReadOptions`中新增了 **`async_io`选项**，使用`FSRandomAccessFile::ReadAsync`接口进行<mark>异步读</mark>。

> 注意，[6.15.5](https://github.com/xiaodongQ/rocksdb/tree/rocksdb-v6.15.5) 分支还不包含这部分，下面基于`v7.9.2`分支查看代码。  
> 从 HISTORY.md 中可看到是 `7.0.0 (02/20/2022)` 中开始新增的 `ReadAsync`。
{: .prompt-info }

这里看下`MultiGet`，其中会调用到`TableReader::MultiGet`（读取SST文件），基于 **<mark>协程（coroutine）</mark>** 实现（Facebook的`folly`库）。

```cpp
// rocksdb_v7.9.2/table/table_reader.h
class TableReader {
  ...
  // 纯虚函数，需要实现类实现
  virtual Status Get(const ReadOptions& readOptions, const Slice& key,
                     GetContext* get_context,
                     const SliceTransform* prefix_extractor,
                     bool skip_filters = false) = 0;

  virtual void MultiGet(const ReadOptions& readOptions,
                        const MultiGetContext::Range* mget_range,
                        const SliceTransform* prefix_extractor,
                        bool skip_filters = false) {
    for (auto iter = mget_range->begin(); iter != mget_range->end(); ++iter) {
      *iter->s = Get(readOptions, iter->ikey, iter->get_context,
                     prefix_extractor, skip_filters);
    }
  }

#if USE_COROUTINES
  virtual folly::coro::Task<void> MultiGetCoroutine(
      const ReadOptions& readOptions, const MultiGetContext::Range* mget_range,
      const SliceTransform* prefix_extractor, bool skip_filters = false) {
    MultiGet(readOptions, mget_range, prefix_extractor, skip_filters);
    co_return;
  }
#endif  // USE_COROUTINES
  ...
};
```

上面的`TableReader`定义了一个抽象类，可看下block结构组织场景下的实现类：`BlockBasedTable`

```cpp
// rocksdb_v7.9.2/table/block_based/block_based_table_reader.h
class BlockBasedTable : public TableReader {
  ...
  // Get 实现
  Status Get(const ReadOptions& readOptions, const Slice& key,
             GetContext* get_context, const SliceTransform* prefix_extractor,
             bool skip_filters = false) override;
  // MultiGet 重载
  DECLARE_SYNC_AND_ASYNC_OVERRIDE(void, MultiGet,
                                  const ReadOptions& readOptions,
                                  const MultiGetContext::Range* mget_range,
                                  const SliceTransform* prefix_extractor,
                                  bool skip_filters = false);
  ...
};
```

`block_based_table_reader.cc`中默认`MultiGet`实现是同步读SST，即`async_read`参数是false。RocksDB中通过 `block_based_table_reader_sync_and_async.h` 里面的宏开关，控制对`MultiGet`的重载，以支持`async_read`为true的版本。

```cpp
// Generate the regular and coroutine versions of some methods by
// including block_based_table_reader_sync_and_async.h twice
// Macros in the header will expand differently based on whether
// WITH_COROUTINES or WITHOUT_COROUTINES is defined
// clang-format off
#define WITHOUT_COROUTINES
#include "table/block_based/block_based_table_reader_sync_and_async.h"
#undef WITHOUT_COROUTINES
#define WITH_COROUTINES
#include "table/block_based/block_based_table_reader_sync_and_async.h"
#undef WITH_COROUTINES
```

```cpp
// rocksdb_v7.9.2/table/block_based/block_based_table_reader_sync_and_async.h
DEFINE_SYNC_AND_ASYNC(void, BlockBasedTable::MultiGet)
(const ReadOptions& read_options, const MultiGetRange* mget_range,
 const SliceTransform* prefix_extractor, bool skip_filters) {
    ...
}
```

## 3. RocksDB调优指南

[RocksDB Tuning Guide](https://github.com/facebook/rocksdb/wiki/RocksDB-Tuning-Guide)

RocksDB有高度的灵活性和可配置性，另外随着这些年的发展，自身也有很高的**自适应性**。

* 指南中建议：如果是运行在`SSD`上的普通应用程序，不建议再去调优。
* 可调整设置的参数：[Setup Options and Basic Tuning](https://github.com/facebook/rocksdb/wiki/Setup-Options-and-Basic-Tuning)
    * 除非碰到明显的性能问题，否则也不建议做调整，大部分保持默认参数即可
    * 参数示例，`size_t write_buffer_size = 64 << 20;`（`ColumnFamilyOptions`中）：列族Writer Buffer，默认64MB，侧重单个memtable；`size_t db_write_buffer_size = 0;`，构建在memtable中写入硬盘前跨所有列族的数据，0表示不限制
* 理解RocksDB中的基本设计
    * 公开演讲：[Talks](https://github.com/facebook/rocksdb/wiki/Talks)
    * 论文：[Publication](https://github.com/facebook/rocksdb/wiki/Publication)

### 3.1. RocksDB统计

RocksDB统计信息非常全面，单独一个小节特别说明下。（相比而言，自己前段时间刚进行一次项目的性能测试，出现瓶颈后发现<mark>缺乏各种指标！</mark>部分节点安装使用eBPF都费劲，还需要重新编译内核和配套的多个驱动）

* `statistics`介绍和使用，见：[Statistics](https://github.com/facebook/rocksdb/wiki/Statistics)
* `compaction`和`db`状态，见：[Compaction Stats and DB Status](https://github.com/facebook/rocksdb/wiki/Compaction-Stats-and-DB-Status)
    * RocksDB会定期（`stats_dump_period_sec`配置项）dump统计信息到日志文件里
    * 也可以手动获取：`db->GetProperty("rocksdb.stats")`
* Perf 上下文和 IO 统计数据上下文，见：[Perf Context and IO Stats Context](https://github.com/facebook/rocksdb/wiki/Perf-Context-and-IO-Stats-Context)
    * 包含`iostats_context.h` 和 `perf_context.h`，头文件中各自介绍了有哪些指标字段
    * 其使用示例，也可见 [这篇文章](https://vigourtyy-zhg.blog.csdn.net/article/details/108137659)

统计使用示例（完整代码可见 [这里](https://github.com/xiaodongQ/prog-playground/tree/main/storage/rocksdb)）：

```cpp
    rocksdb::Options options;
    // 创建统计
    options.statistics = rocksdb::CreateDBStatistics();
    // 默认等级是kExceptDetailedTimers，不统计锁和压缩的耗时
    // options.statistics->set_stats_level(rocksdb::StatsLevel::kAll);
    ...
    // 打印统计信息
    // 直方图，支持很多种类型，由传入参数指定，此处为获取耗时
    std::cout << "histgram:\n" << options.statistics->getHistogramString(rocksdb::Histograms::DB_GET) << std::endl;
    // 统计字段
    std::cout << "statistics:\n" << options.statistics->ToString() << std::endl;
```

执行结果：

```sh
[CentOS-root@xdlinux ➜ rocksdb git:(main) ✗ ]$ ./test_rocksdb_ops      
====== begin... =====
key:xdkey1, value:test12345
put key:xdkey2 value:test12345
delete key:xdkey1
get key:xdkey2, value:test12345
histgram:
Count: 2 Average: 59.0000  StdDev: 58.00
Min: 1  Median: 1.0000  Max: 117
Percentiles: P50: 1.00 P75: 117.00 P99: 117.00 P99.9: 117.00 P99.99: 117.00
------------------------------------------------------
[       0,       1 ]        1  50.000%  50.000% ##########
(     110,     170 ]        1  50.000% 100.000% ##########

statistics:
rocksdb.block.cache.miss COUNT : 0
rocksdb.block.cache.hit COUNT : 0
rocksdb.block.cache.add COUNT : 0
rocksdb.block.cache.add.failures COUNT : 0
rocksdb.block.cache.index.miss COUNT : 0
...
```

### 3.2. 可能的性能瓶颈

调优指南里的 [Possibilities of Performance Bottlenecks](https://github.com/facebook/rocksdb/wiki/RocksDB-Tuning-Guide#possibilities-of-performance-bottlenecks) 小节，可以作为定位类似性能问题的思路。

#### 3.2.1. 系统指标达到饱和

一些场景下性能受到限制是由于 **<mark>系统指标达到饱和</mark>**了，但又是非预期的情况，调优时需要判断这些指标是否使用率偏高

* **硬盘写入带宽**，RocksDB的`compaction`过程会写SST到硬盘，写入时可能超出硬盘驱动器的负载表现为**写入停滞/延迟（Write Stall）**，还可能导致**读取变慢**
    * Perf context的`read`相关指标，会显示当前是否有<mark>过多</mark>SST文件在读取，出现时考虑对`compaction`进行调优
* **硬盘读取IOPS**，注意硬件的持续稳定`IOPS`规格，常常会比硬件厂商提供的spec规格**更低**。建议使用工具（如`fio`）或系统指标进行基准规格测试。
    * 如果IOPS达到硬件规格的饱和值，则检查`compaction`
    * 并尝试提高`block cache`的缓存命中率
    * 问题的可能原因，有一些不同的因素：读取的索引、过滤器、大block，处理的方式也不一样
* **CPU**，通常受`compaction`的读取路径影响
    * 有很多会影响CPU的选项，比如：compaction, compression, bloom filters, block size
* **Space**（空间），在技术上一般不是瓶颈，但是当系统指标未达到饱和、性能足够好且已经几乎填满SSD空间时，通常会说性能受到空间的瓶颈影响。
    * 空间效率的调优，可见：[Space Tuning](https://github.com/facebook/rocksdb/wiki/Space-Tuning)

#### 3.2.2. 放大因子

三种放大：`write amplification`, `read amplification` and `space amplification`。

应该优化哪种放大因素，有时是比较明显的，但有时又不明显，无论哪种情况，**<mark>compaction</mark>**都是三者间做`trade-off`的关键因素。

1、**写放大**：写入数据库的数据大小 vs 写入磁盘的数据大小，比如写`10MB/s`到数据库，但写入硬盘`30MB/s`，则写放大是`3`倍。

观察写放大的2种方式：
* 1）`DB::GetProperty("rocksdb.stats", &stats)` 获取
* 2）自行计算：硬盘带宽（`iostat`统计） 除以 数据库写入速率

2、**读放大**：每次查询时硬盘的读取数据量，比如单次查询需要5个page，则读放大是`5`倍。

* 逻辑读：从缓存读取，RocksDB的`block cache` 或者 操作系统的`page cache`
* 物理读：从硬盘读

3、**空间放大**：数据库文件在硬盘上的大小 和 数据大小 的比值，比如插入`10MB`数据到数据库，但硬盘上用了`100MB`，则空间放大为`10`倍。

* 通常需要设置一个硬性的空间使用限制，避免写爆硬盘（HDD或者SSD或者内存态），可见 [Space Tuning](https://github.com/facebook/rocksdb/wiki/Space-Tuning) 中减小空间放大的调优指导

#### 3.2.3. 系统未达饱和但RocksDB慢

有时系统指标未达饱和，但RocksDB速率不及用户预期。有一些可能的场景：

* `compaction`不够快
    * SSD远未饱和，但受到`compaction`允许的资源最大使用配置的限制，或者并发限制
    * 可参考：[Parallelism options](https://github.com/facebook/rocksdb/wiki/RocksDB-Tuning-Guide#Parallelism-options)
* 无法快速写入（Cannot Write Fast Enough）
    * 写入的问题通常是由于`写IO`的瓶颈，用户可以尝试`无序写`、手动刷`WAL`、多数据库共享、并行写入
* 有时只是想要更低的读延迟（Demand Lower Read Latency ）
    * 有时没什么问题，但用户只希望读取延迟更低
    * 可通过 [Perf Context and IO Stats Context](https://github.com/facebook/rocksdb/wiki/Perf-Context-and-IO-Stats-Context) 检查每次的查询状态（query status），看是CPU 还是 I/O比较耗费时间，再调整相应选项

还有其他因素，暂不展开。

## 4. 小结


## 5. 参考

* [facebook/rocksdb](https://github.com/facebook/rocksdb/)
* [RocksDB Blog](https://rocksdb.org/blog/)
* [Caturra's Blog](https://www.bluepuni.com/)
* [RocksDB-Wiki](https://github.com/facebook/rocksdb/wiki)
