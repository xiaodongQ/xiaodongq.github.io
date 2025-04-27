---
title: RocksDB学习笔记（二） -- memtable、sstfile、logfile等基本结构代码走读
description: 梳理走读memtable、sstfile、logfile等的代码和相关流程。
categories: [存储和数据库, RocksDB]
tags: [存储, RocksDB]
---


## 1. 引言

本篇快速走读一下RocksDB中的几个基本结构：memtable、sstfile、logfile 对应的代码。

## 2. memtable

> 具体可见：[MemTable](https://github.com/facebook/rocksdb/wiki/MemTable)
{: .prompt-info }

RocksDB中的`memtable`基于**跳表**实现。

## 3. 日志（Journal）

> 具体可见：[Journal](https://github.com/facebook/rocksdb/wiki/Journal)，其中包含 [WAL](https://github.com/facebook/rocksdb/wiki/Write-Ahead-Log-%28WAL%29)、[MANIFEST](https://github.com/facebook/rocksdb/wiki/MANIFEST)、[Track WAL in MANIFEST](https://github.com/facebook/rocksdb/wiki/Track-WAL-in-MANIFEST)。
{: .prompt-info }

<mark>日志（`Journals`或`Logs`）</mark> 是 RocksDB完整性和数据恢复的关键，用来记录数据系统的历史状态。RocksDB中包含两种类型的日志：

* `Write Ahead Log (WAL)`：记录内存中数据的状态更新
* `MANIFEST`：记录硬盘上的状态更新


## 4. 小结


## 5. 参考

* [RocksDB-Wiki](https://github.com/facebook/rocksdb/wiki)
* [facebook/rocksdb](https://github.com/facebook/rocksdb/)
* [Journal](https://github.com/facebook/rocksdb/wiki/Journal)
