---
layout: post
title: MySQL学习实践（三） -- MySQL索引
categories: MySQL
tags: 存储 MySQL
---

* content
{:toc}

MySQL学习实践，本篇学习梳理MySQL索引。



## 1. 背景

本篇梳理学习MySQL索引。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 索引的常见数据结构

几种常见的实现索引的数据结构：

* 哈希表
    * 比较适合`等值查询`场景；但`范围/区间查询`效率较低
* 有序数组
    * 在`等值查询`和`范围查询`场景性能较好，但插入新记录需移动后续数据，效率较低
    * 适用于静态存储引擎（存好就不会修改的数据）
* 搜索树
    * 查找、插入的时间复杂度都为`O(logN)`，能有效减少搜索次数，也能较好地满足区间查询
* 跳表、LSM树
    * 跳表相较于搜索树，效率在同一个数量级（`O(logN)`），但从实现的角度来说简单许多
    * `LevelDB`就是基于LSM树结构，其中的`memtable`就是基于跳表实现，之前的学习笔记也有相关记录：[leveldb学习笔记（四） -- memtable结构实现](https://xiaodongq.github.io/2024/08/02/leveldb-memtable-skiplist/)

## 3. InnoDB引擎的索引

在MySQL中，索引是在存储引擎层实现的。

InnoDB引擎使用了`B+树`索引模型，所以数据都是存储在`B+树`中的。**每一个索引在 InnoDB 里面对应一棵 B+ 树。**



## 4. 小结


## 5. 参考

1、[MySQL实战45讲 深入浅出索引](https://time.geekbang.org/column/article/69236)

