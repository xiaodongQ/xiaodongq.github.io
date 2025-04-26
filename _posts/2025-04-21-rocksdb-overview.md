---
title: RocksDB学习笔记（一） -- 总体架构和流程
description: RocksDB梳理实践，介绍总体架构和流程。
categories: [存储和数据库, RocksDB]
tags: [存储, RocksDB]
---


## 1. 背景

前面梳理了基于LSM的LevelDB，本篇开始梳理学习RocksDB，后续进一步看将其作为存储引擎的Ceph等开源项目。

相关链接：

* 仓库地址：[facebook/rocksdb](https://github.com/facebook/rocksdb/)
* 文档：[RocksDB-Wiki](https://github.com/facebook/rocksdb/wiki) （右侧有很多内容分类）

一些其他文章：

* TiDB ⼀些关于 RocksDB 的博客：
    - [TiDB博客 -- RocksDB标签](https://cn.pingcap.com/blog/?tag=RocksDB)
    - [rocksdb-in-tikv](https://github.com/pingcap/blog/blob/master/rocksdb-in-tikv.md)
* CockroachDB 关于 RocksDB 的博客：
    - [Why we built CockroachDB on top of RocksDB](https://www.cockroachlabs.com/blog/cockroachdb-on-rocksd/)
    - [Introducing Pebble: A RocksDB-inspired key-value store written in Go](https://www.cockroachlabs.com/blog/pebble-rocksdb-kv-store/)

> 后续准备梳理的ceph版本为：[ceph v17.2.8](https://github.com/ceph/ceph/tree/v17.2.8)，所以此处RocksDB的源码版本基于其对应的git子模块版本：[rocksdb v6.15.5](https://github.com/facebook/rocksdb/tree/v6.15.5) （源于子模块对应的RocksDB version头文件：[version.h](https://github.com/ceph/rocksdb/blob/c540de6f709b66efd41436694f72d6f7986a325b/include/rocksdb/version.h)
{: .prompt-info }

## 2. 总体说明

### 2.1. 基本介绍

RocksDB 由 Facebook 数据库工程团队开发和维护，建立在早期的 LevelDB 工作之上。提供了快速的键值存储功能，尤其适合在闪存上存储数据。采用日志结构合并数据库 (`LSM`，Log-Structured-Merge-Database) 设计，在写放大因子 (`WAF`，Write-Amplification-Factor)、读放大因子 (`RAF`，Read-Ampification-Factor) 和空间放大因子 (`SAF`，Space-Ampification-Factor) 之间进行了灵活的权衡。

* 以**C++库**的形式（内嵌数据库，没有独立进程），提供任意字节流大小（arbitrarily-sized byte）的键值存储、支持单点查询和范围查询、支持多种类型的ACID事务保证。
* RocksDB在可定制性（customizability）和自适应性（self-adaptability）之间取得了平衡，可基于`SSDs`, `hard disks`, `ramfs`, 或 `remote storage`灵活配置；提供了多种压缩算法；并提供了一些用于生产支持和调试（production support and debugging）的优秀工具。
* RocksDB初始代码基于 **leveldb 1.5** 进行fork，并借鉴了**HBase**的一些灵感，当然也有部分Facebook在开发RocksDB之前的一些代码和设计。
* 详情可见：[RocksDB-Overview](https://github.com/facebook/rocksdb/wiki/RocksDB-Overview)

使用RocksDB作为存储引擎的项目很多，比如：MyRocks、MongoRocks、CockroachDB、Netflix、TiKV、Flink、Nebula Graph等等。

RocksDB优点很多，但也有些缺点，上面提到在几个放大因素上做了权衡，其中一大问题就是**写放大**。每个RocksDB为了提高读性能，都会进行`Compaction`，而似这样的多份（一般3份）写入RocksDB，等于CPU消耗确定会*3，并且写放大由于提高了写的次数，即提高SSD的擦写次数，会显著减少SSD的寿命，提高系统的成本。可了解：[RocksDB的缺点](https://zhuanlan.zhihu.com/p/162052214)。

### 2.2. 架构

RocksDB基本结构如下，即典型的LSM结构（也可见：[LevelDB学习笔记（一） -- 整体架构和基本操作](https://xiaodongq.github.io/2024/07/10/leveldb-learn-first)）：

![rocksdb-constructs-lsm](/images/rocksdb-constructs-lsm.png)

说明：

* 写数据前先追加写`WAL`，而后写内存态的`Memtable`，一个`Memtable`满之后就成为不可写的`Immutable Memtable`
* 从`L0`开始就是刷写到硬盘的`SST`（`Sorted String Table`）文件，每层间进行`Compaction`合并

简图如下（最近折腾了一下draw.io的配置，后续多画画图找找感觉）：

![rocksdb_lsm_flow](/images/rocksdb_lsm_flow.svg)

RocksDB中的SST文件叫`BlockBasedTable`，具体可见：[Rocksdb BlockBasedTable Format](https://github.com/facebook/rocksdb/wiki/Rocksdb-BlockBasedTable-Format)。文件格式如下，相较于LevelDB里面的SStable文件格式，多了3、4、5对应的`compression dictionary block`、`range deletion block`、`stats block`。

```
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

LevelDB里面的SStable文件格式示意图如下（可见 [LevelDB学习笔记（五） -- sstable实现](https://xiaodongq.github.io/2024/08/07/leveldb-sstable) 和 [leveldb-handbook](https://leveldb-handbook.readthedocs.io/zh/latest/sstable.html)）：

![SSTable文件结构示意图](/images/sstable_logic.jpeg)

### 2.3. 特性

具体见上面的 RocksDB-Overview 参考链接，这里只列出几个特性。

* 支持配置多线程Compaction
* 避免停顿（Avoiding Stalls）
    * 当所有后台compaction线程都在忙于处理合并，此时外部突发的大量`write`请求可能会快速写满memtable，进而导致新请求出现**停顿**，RocksDB支持配置一小组线程专门用于刷写memtable到硬盘
* Block缓存（`Block Cache`）
    * 通过一个Block数据的**LRU缓存**来提升读取性能，支持两种缓存类型：`非压缩block` 和 `压缩block`。如果配置了压缩block缓存，一般会使用**直接IO**，以避免文件系统重复缓存数据（page cache）
* Table缓存（`Table Cache`）
    * 缓存打开的`sstfile`文件（即sstable）
* IO控制
    * 允许用户配置和SST文件不同的IO读写方式，用户IO可以配置成直接IO，让RocksDB来完全控制cache，比如定期进行批量sync
* 此外，还有 合并过滤（Compaction Filter）、只读模式、数据压缩、支持多个嵌入式数据库 等

### 2.4. 和 LevelDB 的对比

此处贴一下LLM对两者的部分对比：

1、背景与开发

* LevelDB 由 Google 的 Jeff Dean 和 Sanjay Ghemawat 开发，`2011`年开源。
    * 设计目标是提供一个轻量级、高效的嵌入式存储引擎，适用于**单机场景**。
    * 代码简洁，但功能较为基础，扩展性有限
* RocksDB 由 Facebook 基于 LevelDB 改进而来，`2013`年开源。
    * 面向**现代硬件**（多核 CPU、SSD）和**高并发场景**，强化了企业级需求。
    * 社区活跃，持续迭代更新，功能丰富

2、核心差异

（1）性能优化：

| **特性**       | **LevelDB**                     | **RocksDB**                                         |
| -------------- | ------------------------------- | --------------------------------------------------- |
| **多线程支持** | 单线程写入，Compaction 可能阻塞 | 多线程 Compaction、写入、读取                       |
| **写入优化**   | 简单 MemTable/SSTable 结构      | 支持 Pipeline 写入、多 MemTable（向量 MemTable）    |
| **Compaction** | 单线程 Leveled Compaction       | 支持并行 Compaction、Universal Compaction、分层调优 |
| **延迟控制**   | 高负载下延迟波动大              | 通过限流和优先级调度降低尾部延迟                    |
| **内存管理**   | 固定 Block Cache                | 可定制化的 Block Cache（LRU、Clock 等）             |

（2）功能扩展

| **特性**       | **LevelDB**   | **RocksDB**                                     |
| -------------- | ------------- | ----------------------------------------------- |
| **事务支持**   | 不支持        | 支持 ACID 事务（悲观/乐观锁）                   |
| **备份与恢复** | 无内置工具    | 支持增量备份、快照                              |
| **数据压缩**   | 仅支持 Snappy | 支持多种压缩算法（ZSTD、LZ4、Zlib 等）          |
| **监控与统计** | 无内置指标    | 内置 Metrics（Prometheus 兼容）、统计信息       |
| **自定义扩展** | 有限          | 支持 Merge Operator、自定义 Compaction 过滤器等 |

（3）可扩展性

- **RocksDB** 支持动态调整参数（如 `max_open_files`、`write_buffer_size`），而 LevelDB 需重启生效。
- **RocksDB** 提供更灵活的内存管理（可分配不同大小的 `Block Cache` 和 `MemTable`）。

兼容性：RocksDB 兼容 LevelDB 的 API，可以无缝替换 LevelDB。反向则不成立。

小结：RocksDB 是 LevelDB 的“全面升级版”，在性能、功能和可扩展性上均有显著提升，尤其适合现代数据密集型应用。而 LevelDB 更适合轻量级场景或学习 LSM-Tree 的入门工具。

## 3. 编译

按 INSTALL.md 里推荐的`make static_lib`以release模式编译静态库。编译出来的静态库很大，有**698MB**，`strip`后只有**8.6MB**了。

```sh
# Makefile编译
[CentOS-root@xdlinux ➜ rocksdb-v6.15.5 git:(rocksdb-v6.15.5) ]$ make static_lib
$DEBUG_LEVEL is 0
  GEN      util/build_version.cc
$DEBUG_LEVEL is 0
  GEN      util/build_version.cc
  CC       cache/cache.o
...
  CC       third-party/folly/folly/synchronization/WaitOptions.o
  AR       librocksdb.a
/usr/bin/ar: creating librocksdb.a

# 大小有点大，698MB。。。
[CentOS-root@xdlinux ➜ rocksdb-v6.15.5 git:(rocksdb-v6.15.5) ]$ ls -ltrh
...
-rw-r--r--  1 root root 698M Apr 25 19:10 librocksdb.a

# strip后只有 8.6MB 了
[CentOS-root@xdlinux ➜ rocksdb-v6.15.5 git:(rocksdb-v6.15.5) ]$ strip librocksdb.a
[CentOS-root@xdlinux ➜ rocksdb-v6.15.5 git:(rocksdb-v6.15.5) ]$ ls -ltrh
...
-rw-r--r--  1 root root 8.6M Apr 25 20:16 librocksdb.a
```

安装gflags（注意启用下`-fPIC`：`cmake -B build -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_INSTALL_PREFIX=/usr/local/gflags`，RocksDB的动态库会链接该.a），并cmake编译一下RocksDB所有内容。

```sh
# 这里指定了Release模式，不指定则单元测试的bin也可一并编译，且库带的调试信息会比较多，.a 500多MB、.so 100多MB
[CentOS-root@xdlinux ➜ build git:(rocksdb-v6.15.5) ]$ cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local/rocksdb
[CentOS-root@xdlinux ➜ build git:(rocksdb-v6.15.5) ]$ make -j8
...
[100%] Linking CXX executable db_bench
[100%] Built target db_bench
[100%] Linking CXX executable db_stress
[100%] Built target db_stress
# 编译出来的库，相比Makefile编译的做了strip，已经比较小了（Makefile虽然可指定release编译，但是产物还是特别大）
[CentOS-root@xdlinux ➜ build git:(rocksdb-v6.15.5) ]$ ls -ltrh
lrwxrwxrwx   1 root root   20 Apr 26 16:44 librocksdb.so.6 -> librocksdb.so.6.15.5
lrwxrwxrwx   1 root root   15 Apr 26 16:44 librocksdb.so -> librocksdb.so.6
-rwxr-xr-x   1 root root 9.5M Apr 26 16:44 librocksdb.so.6.15.5
-rwxr-xr-x   1 root root  35K Apr 26 16:44 cache_bench
-rwxr-xr-x   1 root root  40K Apr 26 16:44 hash_table_bench
-rwxr-xr-x   1 root root 104K Apr 26 16:44 filter_bench
-rwxr-xr-x   1 root root  67K Apr 26 16:44 range_del_aggregator_bench
-rwxr-xr-x   1 root root  99K Apr 26 16:44 memtablerep_bench
-rwxr-xr-x   1 root root 457K Apr 26 16:44 table_reader_bench
-rwxr-xr-x   1 root root 539K Apr 26 16:44 db_bench

# 下面是一些不指定Release时编译的单元测试程序
# [CentOS-root@xdlinux ➜ build git:(rocksdb-v6.15.5) ]$ ls *_test|wc -l
# 172
# -rwxr-xr-x   1 root root 7.4M Apr 26 17:24 db_table_properties_test
# -rwxr-xr-x   1 root root 4.2M Apr 26 17:24 checkpoint_test
# -rwxr-xr-x   1 root root 4.6M Apr 26 17:24 compact_files_test
# -rwxr-xr-x   1 root root 4.1M Apr 26 17:24 blob_file_reader_test
# -rwxr-xr-x   1 root root 3.6M Apr 26 17:24 memory_test
# -rwxr-xr-x   1 root root 6.9M Apr 26 17:24 option_change_migration_test
# -rwxr-xr-x   1 root root  13M Apr 26 17:25 db_test

# tools目录
[CentOS-root@xdlinux ➜ build git:(rocksdb-v6.15.5) ]$ ll tools -ltrh
-rwxr-xr-x  1 root root  50K Apr 26 16:44 rocksdb_undump
-rwxr-xr-x  1 root root  22K Apr 26 16:44 sst_dump
-rwxr-xr-x  1 root root  23K Apr 26 16:44 ldb
-rwxr-xr-x  1 root root  50K Apr 26 16:44 rocksdb_dump
-rwxr-xr-x  1 root root  61K Apr 26 16:44 write_stress
-rwxr-xr-x  1 root root 107K Apr 26 16:44 db_sanity_test
-rwxr-xr-x  1 root root  33K Apr 26 16:44 db_repl_stress
...
[CentOS-root@xdlinux ➜ build git:(rocksdb-v6.15.5) ]$ ll db_stress_tool
-rwxr-xr-x 1 root root 519K Apr 26 16:44 db_stress
...
```

部分编译结果物说明：

* 工具
    * **sst_dump**：把一个sst文件中的所有键值对都dump（转储）出来
    * **ldb**：可向一个数据库进行 `put`、`get`、`scan` 操作，也可以把`MANIFEST`的内容dump出来
    * 使用说明可见：[Administration and Data Access Tool](https://github.com/facebook/rocksdb/wiki/Administration-and-Data-Access-Tool)
* 压力测试：`db_stress`
    * 使用方式见：[Stress test](https://github.com/facebook/rocksdb/wiki/Stress-test)，`tools/db_crashtest.py`脚本里面会用到该bin
* 性能测试：`db_bench`
    * 使用方式见：[Performance-Benchmarks](https://github.com/facebook/rocksdb/wiki/Performance-Benchmarks)，`tools/benchmark.sh`会用到该bin

## 4. db_bench 性能测试

使用 `tools/run_flash_bench.sh` 进行性能测试，其中会调用`benchmark.sh`，里面用到`db_bench`

```sh
./db_bench --benchmarks=fillseq --use_existing_db=0 --sync=0 --db=/tmp/rocksdb/ --wal_dir=/tmp/rocksdb/ --num=1073741824 --num_levels=6 --key_size=20 --value_size=400 --block_size=8192 --cache_size=1073741824 --cache_numshardbits=6 --compression_max_dict_bytes=0 --compression_ratio=0.5 --compression_type=none --level_compaction_dynamic_level_bytes=true --bytes_per_sync=8388608 --cache_index_and_filter_blocks=0 --pin_l0_filter_and_index_blocks_in_cache=1 --benchmark_write_rate_limit=0 --hard_rate_limit=3 --rate_limit_delay_max_milliseconds=1000000 --write_buffer_size=134217728 --target_file_size_base=134217728 --max_bytes_for_level_base=1073741824 --verify_checksum=1 --delete_obsolete_files_period_micros=62914560 --max_bytes_for_level_multiplier=8 --statistics=0 --stats_per_interval=1 --stats_interval_seconds=60 --histogram=1 --memtablerep=skip_list --bloom_bits=10 --open_files=-1 --level0_file_num_compaction_trigger=4 --level0_stop_writes_trigger=20 --max_background_compactions=16 --max_write_buffer_number=8 --max_background_flushes=7 --allow_concurrent_memtable_write=false --min_level_to_compress=0 --threads=1 --memtablerep=vector --allow_concurrent_memtable_write=false --disable_wal=1 --seed=1745662974 2>&1 | tee -a /tmp/output/benchmark_fillseq.wal_disabled.v400.log
RocksDB:    version 6.15
Date:       Sat Apr 26 18:22:56 2025
CPU:        16 * AMD Ryzen 7 5700G with Radeon Graphics
CPUCache:   512 KB
2025/04/26-18:23:56  ... thread 0: (12421000,12421000) ops and (207004.0,207004.0) ops/second in (60.003671,60.003671) seconds

** Compaction Stats [default] **
Level    Files   Size     Score Read(GB)  Rn(GB) Rnp1(GB) Write(GB) Wnew(GB) Moved(GB) W-Amp Rd(MB/s) Wr(MB/s) Comp(sec) CompMergeCPU(sec) Comp(cnt) Avg(sec) KeyIn KeyDrop
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  L0      3/0   370.22 MB   0.8      0.0     0.0      0.0       4.8      4.8       0.0   1.0      0.0    104.2     47.39             46.57        40    1.185       0      0
  L4      8/0   987.26 MB   1.0      0.0     0.0      0.0       0.0      0.0       3.4   0.0      0.0      0.0      0.00              0.00         0    0.000       0      0
  L5     29/0    3.49 GB   0.0      0.0     0.0      0.0       0.0      0.0       3.5   0.0      0.0      0.0      0.00              0.00         0    0.000       0      0
 Sum     40/0    4.82 GB   0.0      0.0     0.0      0.0       4.8      4.8       6.9   1.0      0.0    104.2     47.39             46.57        40    1.185       0      0
 Int      0/0    0.00 KB   0.0      0.0     0.0      0.0       4.7      4.7       6.9   1.0      0.0    104.4     46.09             45.38        39    1.182       0      0

** Compaction Stats [default] **
Priority    Files   Size     Score Read(GB)  Rn(GB) Rnp1(GB) Write(GB) Wnew(GB) Moved(GB) W-Amp Rd(MB/s) Wr(MB/s) Comp(sec) CompMergeCPU(sec) Comp(cnt) Avg(sec) KeyIn KeyDrop
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
High      0/0    0.00 KB   0.0      0.0     0.0      0.0       4.8      4.8       0.0   0.0      0.0    104.2     47.39             46.57        40    1.185       0      0
Uptime(secs): 60.0 total, 57.0 interval
Flush(GB): cumulative 4.821, interval 4.700
AddFile(GB): cumulative 0.000, interval 0.000
AddFile(Total Files): cumulative 0, interval 0
AddFile(L0 Files): cumulative 0, interval 0
AddFile(Keys): cumulative 0, interval 0
Cumulative compaction: 4.82 GB write, 82.25 MB/s write, 0.00 GB read, 0.00 MB/s read, 47.4 seconds
Interval compaction: 4.70 GB write, 84.43 MB/s write, 0.00 GB read, 0.00 MB/s read, 46.1 seconds
Stalls(count): 0 level0_slowdown, 0 level0_slowdown_with_compaction, 0 level0_numfiles, 0 level0_numfiles_with_compaction, 0 stop for pending_compaction_bytes, 0 slowdown for pending_compaction_bytes, 0 memtable_compaction, 0 memtable_slowdown, interval 0 total count

** File Read Latency Histogram By Level [default] **

** DB Stats **
Uptime(secs): 60.0 total, 57.0 interval
Cumulative writes: 0 writes, 12M keys, 0 commit groups, 0.0 writes per commit group, ingest: 5.04 GB, 86.06 MB/s
Cumulative WAL: 0 writes, 0 syncs, 0.00 writes per sync, written: 0.00 GB, 0.00 MB/s
Cumulative stall: 00:00:0.000 H:M:S, 0.0 percent
Interval writes: 0 writes, 11M keys, 0 commit groups, 0.0 writes per commit group, ingest: 4910.02 MB, 86.13 MB/s
Interval WAL: 0 writes, 0 syncs, 0.00 writes per sync, written: 0.00 MB, 0.00 MB/s
Interval stall: 00:00:0.000 H:M:S, 0.0 percent
...
```

## 5. 基本使用

wiki里有基本使用示例：[Basic Operations](https://github.com/facebook/rocksdb/wiki/Basic-Operations)。

demo如下（代码也可见 [这里](https://github.com/xiaodongQ/prog-playground/tree/main/storage/rocksdb)）：

```cpp
// test_rocksdb_ops.cpp
#include <iostream>
#include <string>
#include <cstdio>
#include <cassert>
#include "rocksdb/db.h"

void test() {
    rocksdb::DB* db;
    rocksdb::Options options;
    options.create_if_missing = true;
    // open数据库，不存在则创建
    rocksdb::Status status = rocksdb::DB::Open(options, "/tmp/testdb", &db);
    assert(status.ok());

    std::string value;
    std::string key1 = "xdkey1";
    // 临时新增
    db->Put(rocksdb::WriteOptions(), key1, "test12345");
    // 读取key1
    rocksdb::Status s = db->Get(rocksdb::ReadOptions(), key1, &value);
    if (s.ok()) {
        std::cout << "key:" << key1 << ", value:" << value << std::endl;
    } else if(s.code() == rocksdb::Status::kNotFound) {
        std::cout << "key:" << key1 << " not found" << std::endl;
    } else {
        std::cout << "key:" << key1 << " get error:" << s.code() << std::endl;
    }

    // 读取到key1，则将其value写入key2，并删除key1。可用rocksdb::WriteBatch来实现原子更新。
    std::string key2 = "xdkey2";
    if (s.ok()) {
        s = db->Put(rocksdb::WriteOptions(), key2, value);
        std::cout << "put key:" << key2 << " value:" << value << std::endl;
        // 而后删除key1
        if (s.ok()) {
            s = db->Delete(rocksdb::WriteOptions(), key1);
            std::cout << "delete key:" << key1 << std::endl;
        }
    }
    // 读取key2
    s = db->Get(rocksdb::ReadOptions(), key2, &value);
    if (s.ok()) {
        std::cout << "get key:" << key2 << ", value:" << value << std::endl;
    }

    // 关闭数据库
    status = db->Close();
    delete db;
}

int main(int argc, char *argv[])
{
    printf("====== begin... =====\n");
    test();
    printf("====== end ======\n");
    return 0;
}
```

### 5.1. Makefile

Makefile也贴一下，一些内建函数和通配符经常忘记，需要时不时敲一下加强印象，而后就用现代一些的CMake去做项目了：

```makefile
MODE ?= debug
INCLUDE_PATH = /usr/local/rocksdb/include

# 进一步支持debug/release模式区分
ifeq ($(MODE), release)
	CXX_FLAGS = -O2 -g -Wall
else ifeq ($(MODE), debug)
	CXX_FLAGS = -g -Wall
else
	$(error invalid MODE:$(MODE))
endif

# =========== begin ==============
# gcc默认情况下，会优先选择动态库
# 链接静态库方式1：
# -Wl,-Bstatic 显式指定链接静态库，但注意会影响其他库，它后面的所有库都是静态方式链接。需要 -Wl,-Bdynamic 恢复默认行为
#LD_FLAGS = -Wl,-Bstatic -lrocksdb -L/usr/local/rocksdb/lib64 -Wl,-Bdynamic -pthread

# 链接静态库方式2：直接指定静态库路径，显式指定.a，不用-l（绕过了动态库搜索机制）
LD_FLAGS = /usr/local/rocksdb/lib64/librocksdb.a -pthread
# =========== end ==============

TARGET = test_rocksdb_ops
SRCS = test_rocksdb_ops.cpp
# 方式1
# OBJS = $(SRCS:.cpp=.o)
# 方式2
OBJS = $(patsubst %.cpp, %.o, $(SRCS))

# 默认目标
all: $(TARGET)
#all:
#g++ test_rocksdb_ops.cpp -o test_rocksdb_ops -I/usr/local/rocksdb/include ${LD_FLAGS}

# 生成可执行文件
$(TARGET): $(OBJS)
	g++ $(OBJS) -o $@ -I$(INCLUDE_PATH) $(LD_FLAGS)
ifeq ($(MODE), release)
	objcopy --only-keep-debug $@ $@.debug
# 和 strip --strip-debug 效果相当，移除调试信息但保留符号表，strip --strip-all（默认模式）则移除所有符号表和调试信息，大小显著减小
	objcopy --strip-debug $@
	objcopy --add-gnu-debuglink=$@.debug $@
endif

# 生成目标文件
%.o:%.cpp
	g++ $(CXX_FLAGS) -c $< -o $@ -I$(INCLUDE_PATH)

clean:
	rm -f $(OBJS) $(TARGET) $(TARGET).debug

.PHONY: all clean
```

编译并运行：

```sh
# 编译
[CentOS-root@xdlinux ➜ rocksdb git:(main) ✗ ]$ make
g++ -g -Wall -c test_rocksdb_ops.cpp -o test_rocksdb_ops.o -I/usr/local/rocksdb/include
g++  test_rocksdb_ops.o -o test_rocksdb_ops -I/usr/local/rocksdb/include /usr/local/rocksdb/lib64/librocksdb.a -pthread
# 运行
[CentOS-root@xdlinux ➜ rocksdb git:(main) ✗ ]$ ./test_rocksdb_ops
====== begin... =====
key:xdkey1, value:test12345
put key:xdkey2 value:test12345
delete key:xdkey1
get key:xdkey2, value:test12345
====== end ======
```

### 5.2. CMake

对应的CMake规则文件如下。

```makefile
# CMakeLists.txt
# 设置 CMake 最低版本要求
cmake_minimum_required(VERSION 3.10)

# 定义项目名称
project(test_rocksdb_ops)

# 设置 C++ 标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 定义编译模式（默认为 Debug）
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug CACHE STRING "Choose the type of build." FORCE)
endif()

# 包含路径
set(INCLUDE_PATH /usr/local/rocksdb/include)

# 库路径
set(LIB_PATH /usr/local/rocksdb/lib64)

# 根据编译模式设置编译选项
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O2 -Wall")
elseif(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g -Wall")
else()
    message(FATAL_ERROR "Invalid build type: ${CMAKE_BUILD_TYPE}")
endif()

# 添加可执行文件
add_executable(${PROJECT_NAME} test_rocksdb_ops.cpp)

# 包含头文件目录
target_include_directories(${PROJECT_NAME} PRIVATE ${INCLUDE_PATH})

# 链接静态库：显式指定 .a 文件
target_link_libraries(${PROJECT_NAME} PRIVATE
    ${LIB_PATH}/librocksdb.a
    pthread
)

# 如果是 Release 模式，添加调试信息分离的后处理步骤
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    # 提取调试信息到单独的文件
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND objcopy --only-keep-debug $<TARGET_FILE:${PROJECT_NAME}> $<TARGET_FILE:${PROJECT_NAME}>.debug
        COMMENT "Extracting debug information to $<TARGET_FILE:${PROJECT_NAME}>.debug"
    )

    # 移除主文件中的调试信息
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND objcopy --strip-debug $<TARGET_FILE:${PROJECT_NAME}>
        COMMENT "Stripping debug information from $<TARGET_FILE:${PROJECT_NAME}>"
    )

    # 添加调试链接到主文件
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND objcopy --add-gnu-debuglink=$<TARGET_FILE:${PROJECT_NAME}>.debug $<TARGET_FILE:${PROJECT_NAME}>
        COMMENT "Adding debug link to $<TARGET_FILE:${PROJECT_NAME}>"
    )
endif()

# 清理规则
set_directory_properties(PROPERTIES ADDITIONAL_CLEAN_FILES "${PROJECT_NAME}.debug")
```

构建并运行：

```sh
# 构建生成
[CentOS-root@xdlinux ➜ rocksdb git:(main) ✗ ]$ cmake -B build -DCMAKE_BUILD_TYPE=Release
-- Configuring done
-- Generating done
-- Build files have been written to: /home/workspace/prog-playground/storage/rocksdb/build
[CentOS-root@xdlinux ➜ rocksdb git:(main) ✗ ]$ cd build
# 编译
[CentOS-root@xdlinux ➜ build git:(main) ✗ ]$ make
[ 50%] Building CXX object CMakeFiles/test_rocksdb_ops.dir/test_rocksdb_ops.cpp.o
[100%] Linking CXX executable test_rocksdb_ops
Extracting debug information to $<TARGET_FILE:test_rocksdb_ops>.debug
Stripping debug information from $<TARGET_FILE:test_rocksdb_ops>
Adding debug link to $<TARGET_FILE:test_rocksdb_ops>
[100%] Built target test_rocksdb_ops
# 产物
[CentOS-root@xdlinux ➜ build git:(main) ✗ ]$ ls -ltrh
total 6.6M
-rw-r--r-- 1 root root  14K Apr 26 22:22 CMakeCache.txt
-rw-r--r-- 1 root root 1.7K Apr 26 22:22 cmake_install.cmake
-rw-r--r-- 1 root root 5.5K Apr 26 22:25 Makefile
-rwxr-xr-x 1 root root 1.2M Apr 26 22:25 test_rocksdb_ops.debug
-rwxr-xr-x 1 root root 5.5M Apr 26 22:25 test_rocksdb_ops
drwxr-xr-x 5 root root  276 Apr 26 22:25 CMakeFiles
# 运行
[CentOS-root@xdlinux ➜ build git:(main) ✗ ]$ ./test_rocksdb_ops
====== begin... =====
key:xdkey1, value:test12345
put key:xdkey2 value:test12345
delete key:xdkey1
get key:xdkey2, value:test12345
====== end ======
```

## 6. 小结

RocksDB总体介绍和基本API使用，并对比了和LevelDB的大致区别。手动编写Makefile、`objcopy`剥离符号加强肌肉记忆，并对比更为现代的CMake使用。

## 7. 参考

* [RocksDB-Wiki](https://github.com/facebook/rocksdb/wiki)
* [RocksDB-Overview](https://github.com/facebook/rocksdb/wiki/RocksDB-Overview)
* [facebook/rocksdb](https://github.com/facebook/rocksdb/)
* [LevelDB学习笔记（五） -- sstable实现](https://xiaodongq.github.io/2024/08/07/leveldb-sstable)
* [Basic Operations](https://github.com/facebook/rocksdb/wiki/Basic-Operations)
