---
layout: post
title: leveldb学习笔记（二） -- 读写操作流程
categories: 存储
tags: 存储 leveldb
---

* content
{:toc}

leveldb学习笔记，本篇学习其读写操作流程。



## 1. 背景

[leveldb学习笔记（一） -- 整体架构和基本操作](https://xiaodongq.github.io/2024/07/10/leveldb-learn-first/)里做了基本介绍和简单demo功能测试，本篇具体看下对应的实现流程，为了达到性能效果做了哪些设计。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## UML类图

根据代码，画一下leveldb相关类图，如下：

![leveldb类图](/images/2024-07-21-leveldb-class-graph.svg)

## 写操作流程

leveldb对外提供的写入接口有：（1）`Put`（2）`Delete`两种。

**这两种本质对应同一种操作，`Delete`操作同样会被转换成一个value为空的`Put`操作。**



## 5. 小结


## 6. 参考

1、[leveldb](https://github.com/google/leveldb)

2、[leveldb-handbook](https://leveldb-handbook.readthedocs.io/zh/latest/index.html)

3、[LevelDB数据结构解析](https://www.qtmuniao.com/categories/源码阅读/leveldb/)

4、GPT
