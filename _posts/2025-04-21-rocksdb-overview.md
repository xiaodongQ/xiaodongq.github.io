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
* 文档：[RocksDB-Overview](https://github.com/facebook/rocksdb/wiki/RocksDB-Overview)

一些其他文章：

* TiDB ⼀些关于 RocksDB 的博客：
    - https://cn.pingcap.com/blog/?tag=RocksDB
    - https://github.com/pingcap/blog/blob/master/rocksdb-in-tikv.md
* CRDB 关于 RocksDB 的博客：
    - https://www.cockroachlabs.com/blog/cockroachdb-on-rocksd/
    - https://www.cockroachlabs.com/blog/pebble-rocksdb-kv-store/

## 总体说明

RocksDB 由 Facebook 数据库工程团队开发和维护，建立在早期的 LevelDB 工作之上。采用日志结构的合并数据库 (`LSM`，`Log-Structured-Merge-Database`) 设计，在写放大因子 (`WAF`，`Write-Amplification-Factor`)、读放大因子 (`RAF`，`Read-Ampification-Factor`) 和空间放大因子 (`SAF`，`Space-Ampification-Factor`) 之间进行了灵活的权衡。

## 2. 小结


## 3. 参考

