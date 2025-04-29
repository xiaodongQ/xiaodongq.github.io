---
title: RocksDB学习笔记（二） -- MemTable、SSTfile、LogFile等基本结构代码走读
description: 梳理走读MemTable、SSTfile、LogFile等的代码和相关流程。
categories: [存储和数据库, RocksDB]
tags: [存储, RocksDB]
---


## 1. 引言

本篇快速走读一下RocksDB中的几个基本结构：MemTable、SSTFile、LogFile 对应的代码。

## 2. 基本结构说明

### 2.1. MemTable

> 介绍可见：[MemTable](https://github.com/facebook/rocksdb/wiki/MemTable)
{: .prompt-info }

RocksDB中的`MemTable`基于**跳表**实现。

`MemTable`同时提供`读`和`写`服务。

* **读取数据**时会先从MemTable读取，因为内存中的数据最新，没查找到才去查询`SST`文件；
* **写入数据**时都会先写入到MemTable，当MemTable满时就会变成immutable状态，后台线程会刷写（`flush`）其内容到`SST`文件（`SSTable`文件）
    * MemTable会根据配置的大小和数量来决定什么时候`flush`到磁盘上。一旦 MemTable 达到配置的大小，旧的 MemTable 和 WAL 都会变成`不可变`的状态（即immutable MemTable），然后会重新分配新的 MemTable 和 WAL 用来写入数据，旧的 MemTable 则会被 flush 到`SSTable`文件中，即`L0`层的数据。
    * 任何时间点，都**只有一个活跃的MemTable** 和 **0个或多个immutable MemTable**

### 2.2. SST文件

> 介绍可见：[Rocksdb BlockBasedTable Format](https://github.com/facebook/rocksdb/wiki/Rocksdb-BlockBasedTable-Format)
{: .prompt-info }

### 2.3. 日志（Journal）

> 介绍可见：[Journal](https://github.com/facebook/rocksdb/wiki/Journal)，其中包含 [WAL](https://github.com/facebook/rocksdb/wiki/Write-Ahead-Log-%28WAL%29)、[MANIFEST](https://github.com/facebook/rocksdb/wiki/MANIFEST)、[Track WAL in MANIFEST](https://github.com/facebook/rocksdb/wiki/Track-WAL-in-MANIFEST)。
{: .prompt-info }

**日志（`Journals`或`Logs`）** 是RocksDB完整性和数据恢复的关键，用来记录数据系统的历史状态。

RocksDB中包含两种类型的日志：
* 1、`Write Ahead Log (WAL)`：记录内存中数据的状态更新
* 2、`MANIFEST`：记录硬盘上的状态更新

## 3. 代码流程

写入数据的流程中会涉及上述几个基本结构，通过走读`Put`的流程来看对应的实现。

### 3.1. 类图

RocksDB读写操作的头文件入口为：`include/rocksdb/db.h`，其中定义了`class DB`抽象类。实现类为`class DBImpl`，位于`db/db_impl/db_impl.h`中，实际实现则根据不同类型的功能，可能分布在不同的文件中，文件拓扑如下：

```sh
[MacOS-xd@qxd ➜ cpp_path ]$ tree --matchdirs rocksdb_v6.15.5/db/db_impl
rocksdb_v6.15.5/db/db_impl
├── db_impl.cc
├── db_impl.h
├── db_impl_compaction_flush.cc
├── db_impl_debug.cc
├── db_impl_experimental.cc
├── db_impl_files.cc
├── db_impl_open.cc
├── db_impl_readonly.cc
├── db_impl_readonly.h
├── db_impl_secondary.cc
├── db_impl_secondary.h
├── db_impl_write.cc
└── db_secondary_test.cc
```

示意图如下：

![rocksdb-class-diagram](/images/2025-04-29-rocksdb-class-diagram.png)

### 3.2. Put流程

```cpp
// db/db_impl/db_impl.h
class DBImpl : public DB {
  // 此处using用于将基类中所有Put的重载函数（基类里有多个Put函数）引入派生类DBImpl，避免在派生类中被隐藏。
  // 使用派生类时也可以使用其他基类里的Put重载函数。
  using DB::Put;
  virtual Status Put(const WriteOptions& options,
                     ColumnFamilyHandle* column_family, const Slice& key,
                     const Slice& value) override;
};
```

## 4. 小结


## 5. 参考

* [RocksDB-Wiki](https://github.com/facebook/rocksdb/wiki)
* [facebook/rocksdb](https://github.com/facebook/rocksdb/)
* [Journal](https://github.com/facebook/rocksdb/wiki/Journal)
