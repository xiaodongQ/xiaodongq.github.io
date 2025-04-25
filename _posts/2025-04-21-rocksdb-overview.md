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

> 后续准备梳理的ceph版本为：[ceph v17.2.8](https://github.com/ceph/ceph/tree/v17.2.8)，所以此处RocksDB的源码版本基于其对应的git子模块版本：[rocksdb v6.15.5](https://github.com/facebook/rocksdb/tree/v6.15.5) （源于子模块对应的RocksDB version头文件：[version.h]（https://github.com/ceph/rocksdb/blob/c540de6f709b66efd41436694f72d6f7986a325b/include/rocksdb/version.h）
{: .prompt-info }

## 2. 总体说明

RocksDB 由 Facebook 数据库工程团队开发和维护，建立在早期的 LevelDB 工作之上。提供了快速的键值存储功能，尤其适合在闪存上存储数据。采用日志结构合并数据库 (`LSM`，Log-Structured-Merge-Database) 设计，在写放大因子 (`WAF`，Write-Amplification-Factor)、读放大因子 (`RAF`，Read-Ampification-Factor) 和空间放大因子 (`SAF`，Space-Ampification-Factor) 之间进行了灵活的权衡。

* 以**C++库**的形式（内嵌数据库，没有独立进程），提供任意字节流大小（arbitrarily-sized byte）的键值存储、支持单点查询和范围查询、支持多种类型的ACID事务保证。
* RocksDB在可定制性（customizability）和自适应性（self-adaptability）之间取得了平衡，可基于`SSDs`, `hard disks`, `ramfs`, 或 `remote storage`灵活配置；提供了多种压缩算法；并提供了一些用于生产支持和调试（production support and debugging）的优秀工具。
* RocksDB初始代码基于 **leveldb 1.5** 进行fork，并借鉴了**HBase**的一些灵感，当然也有部分Facebook在开发RocksDB之前的一些代码和设计。
* 详情可见：[RocksDB-Overview](https://github.com/facebook/rocksdb/wiki/RocksDB-Overview)

RocksDB优点很多，但也有些缺点，上面提到在几个放大因素上做了权衡，其中一大问题就是**写放大**。每个RocksDB为了提高读性能，都会进行`Compaction`，而似这样的多份（一般3份）写入RocksDB，等于CPU消耗确定会*3，并且写放大由于提高了写的次数，即提高SSD的擦写次数，会显著减少SSD的寿命，提高系统的成本。可了解：[RocksDB的缺点](https://zhuanlan.zhihu.com/p/162052214)。

RocksDB基本结构如下，即典型的LSM结构（也可见：[LevelDB学习笔记（一） -- 整体架构和基本操作](https://xiaodongq.github.io/2024/07/10/leveldb-learn-first)）：

![rocksdb-constructs-lsm](/images/rocksdb-constructs-lsm.png)

说明：

* 写数据前先追加写`WAL`，而后写内存态的`Memtable`，一个`Memtable`满之后就成为不可写的`Immutable Memtable`
* 从`L0`开始就是刷写到硬盘的`SST`文件，每层间进行`Compaction`合并

简图如下（最近折腾了一下draw.io的配置，后续多画画图找找感觉）：

![rocksdb_lsm_flow](/images/rocksdb_lsm_flow.svg)

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

## 4. 小结


## 5. 参考

* [RocksDB-Wiki](https://github.com/facebook/rocksdb/wiki)
* [facebook/rocksdb](https://github.com/facebook/rocksdb/)