---
title: RocksDB学习笔记（三） -- RocksDB中的一些特性设计和高性能相关机制
description: 通过官方博客了解RocksDB的一些特性设计，并梳理下高性能相关的机制。
categories: [存储和数据库, RocksDB]
tags: [存储, RocksDB]
---


## 1. 引言

前两篇中梳理了RocksDB的总体结构和基本流程，本篇学习 [RocksDB Blog](https://rocksdb.org/blog/) 中的部分文章，了解下RocksDB的一些特性设计，并梳理RocksDB中的一些高性能机制。

此外，也梳理下其他C++和Linux相关的一些高性能机制，比如 **<mark>coroutine</mark>** 和 **<mark>io_uring</mark>**。

1、官网博客文章（按时间顺序，早期文章在前面）：

* [Indexing SST Files for Better Lookup Performance](https://rocksdb.org/blog/2014/04/21/indexing-sst-files-for-better-lookup-performance.html)
* [Reducing Lock Contention in RocksDB](https://rocksdb.org/blog/2014/05/14/lock.html)
* [Improving Point-Lookup Using Data Block Hash Index](https://rocksdb.org/blog/2018/08/23/data-block-hash-index.html)
* [RocksDB Secondary Cache](https://rocksdb.org/blog/2021/05/27/rocksdb-secondary-cache.html)
* [Asynchronous IO in RocksDB](https://rocksdb.org/blog/2022/10/07/asynchronous-io-in-rocksdb.html)
* [Reduce Write Amplification by Aligning Compaction Output File Boundaries](https://rocksdb.org/blog/2022/10/31/align-compaction-output-file.html)

2、另外的一些性能相关博客和文章：

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

## RocksDB相关博客

### 索引SST文件以提升查找性能



## 2. 小结


## 3. 参考

* [facebook/rocksdb](https://github.com/facebook/rocksdb/)
* [RocksDB Blog](https://rocksdb.org/blog/)
* [Caturra's Blog](https://www.bluepuni.com/)
