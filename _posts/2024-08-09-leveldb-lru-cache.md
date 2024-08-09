---
layout: post
title: leveldb学习笔记（五） -- LRU缓存
categories: 存储
tags: 存储 leveldb
---

* content
{:toc}

leveldb学习笔记，本篇学习其LRU缓存实现。



## 1. 背景

继续学习梳理leveldb中具体的流程，本篇来看下LRU缓存实现。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## leveldb缓存结构说明

leveldb中使用的缓存（cache）主要用于读取场景，使得读取热数据时尽量在缓存中命中，减少读取`sstable`文件导致的磁盘io。

是一种LRUcache，其结构由两部分内容组成：

* Hash table：用来存储数据；
* LRU：用来维护数据项的新旧信息；

其中Hash table是基于Yujie Liu等人的论文《Dynamic-Sized Nonblocking Hash Table》实现的，用来存储数据。论文可见：[Dynamic-Sized-Nonblocking-Hash-Tables](https://lrita.github.io/images/posts/datastructure/Dynamic-Sized-Nonblocking-Hash-Tables.pdf)。

## 5. 小结

学习梳理LRU缓存实现逻辑。

## 6. 参考

1、[leveldb](https://github.com/google/leveldb)

2、[leveldb-handbook cache](https://leveldb-handbook.readthedocs.io/zh/latest/cache.html)

3、[漫谈 LevelDB 数据结构（三）：LRU 缓存（ LRUCache）](https://www.qtmuniao.com/2021/05/09/levedb-data-structures-lru-cache/)
