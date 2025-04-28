---
title: RocksDB学习笔记（二） -- MemTable、SSTfile、LogFile等基本结构代码走读
description: 梳理走读MemTable、SSTfile、LogFile等的代码和相关流程。
categories: [存储和数据库, RocksDB]
tags: [存储, RocksDB]
---


## 1. 引言

本篇快速走读一下RocksDB中的几个基本结构：MemTable、SSTFile、LogFile 对应的代码。

## 2. MemTable

> 介绍可见：[MemTable](https://github.com/facebook/rocksdb/wiki/MemTable)
{: .prompt-info }

RocksDB中的`MemTable`基于**跳表**实现。

`MemTable`同时提供`读`和`写`服务。

* **读取数据**时会先从MemTable读取，因为内存中的数据最新，没有才去查询`SST`文件；
* **写入数据**时都会先写入到MemTable，当MemTable满时就会变成immutable不可变，后台线程会刷写（`flush`）其内容到`SST`文件（`SSTable`文件）
    * MemTable会根据配置的大小和数量来决定什么时候`flush`到磁盘上。一旦 MemTable 达到配置的大小，旧的 MemTable 和 WAL 都会变成`不可变`的状态（即immutable MemTable）。然后会重新分配新的 MemTable 和 WAL 用来写入数据，旧的 MemTable 会被 flush 到`SSTable`文件中，即`L0`层的数据。
    * 任何时间点，都**只有一个活跃的MemTable** 和 **0个或多个immutable MemTable**

## 3. SST文件

> 介绍可见：[Rocksdb BlockBasedTable Format](https://github.com/facebook/rocksdb/wiki/Rocksdb-BlockBasedTable-Format)
{: .prompt-info }

## 4. 日志（Journal）

> 介绍可见：[Journal](https://github.com/facebook/rocksdb/wiki/Journal)，其中包含 [WAL](https://github.com/facebook/rocksdb/wiki/Write-Ahead-Log-%28WAL%29)、[MANIFEST](https://github.com/facebook/rocksdb/wiki/MANIFEST)、[Track WAL in MANIFEST](https://github.com/facebook/rocksdb/wiki/Track-WAL-in-MANIFEST)。
{: .prompt-info }

**日志（`Journals`或`Logs`）** 是RocksDB完整性和数据恢复的关键，用来记录数据系统的历史状态。

RocksDB中包含两种类型的日志：
* 1、`Write Ahead Log (WAL)`：记录内存中数据的状态更新
* 2、`MANIFEST`：记录硬盘上的状态更新


## 5. 小结


## 6. 参考

* [RocksDB-Wiki](https://github.com/facebook/rocksdb/wiki)
* [facebook/rocksdb](https://github.com/facebook/rocksdb/)
* [Journal](https://github.com/facebook/rocksdb/wiki/Journal)
