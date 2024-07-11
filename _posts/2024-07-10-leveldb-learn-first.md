---
layout: post
title: leveldb学习笔记（一） -- 整体架构和概念
categories: 存储
tags: 存储 leveldb
---

* content
{:toc}

leveldb学习笔记，整体架构和概念



## 1. 背景

之前学习了一些网络的内容，本打算把网络相关TODO先了结完再去啃存储、CPU、内存等基础和相关领域内容，但扩展开的话点有点多，就先留部分坑了，穿插学习。换一点新的东西，先学习梳理下[leveldb](https://github.com/google/leveldb)这个优秀的存储引擎。

这里先参考 [官网](https://github.com/google/leveldb) 和 [leveldb-handbook](https://leveldb-handbook.readthedocs.io/zh/latest/index.html)，并结合一些博客文章学习，自己再动手做些实验，以此为出发点正好把内核存储栈、涉及的数据结构和算法带着场景再过一遍。

从官网仓库 fork [一份](https://github.com/xiaodongQ/leveldb)，便于代码学习注释、修改调试。（另外会用到benchmark、googletest，`git submodule update --init --recursive`）

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## LevelDB说明和总体架构

LevelDB是一个由Google开源的、快速的键值存储库，提供了`string key`到`string value`的有序映射。

作者是 Sanjay Ghemawat 和 Jeff Dean 两位Google大佬。可以见这篇杂志译文了解：[揭秘 Google 两大超级工程师：AI 领域绝无仅有的黄金搭档](https://www.leiphone.com/category/industrynews/yV1namFFdTlXc6bx.html)，这两位后续还发表了`MapReduce`论文（"三驾马车"之一），Jeff Dean还主导打造了谷歌大脑、TensorFlow等等。

特性：

- 键和值可以是任意的字节数组。
- 数据按照键的顺序进行存储。
- 调用者可以提供自定义的比较函数来覆盖排序顺序。
- 基本操作包括：`Put(key, value)`（插入键值对）、`Get(key)`（获取键对应的值）、`Delete(key)`（删除键及其对应的值）。
- 支持在单个原子批处理中进行多处更改。
- 用户可以创建临时快照，以获得数据的一致视图。
- 支持数据的正向和反向迭代。
- 数据自动使用[Snappy](https://google.github.io/snappy/)压缩库进行压缩。
- 外部活动（如文件系统操作等）通过虚拟接口传递，以便用户可以自定义操作系统交互。


## 小结


## 参考

1、[leveldb](https://github.com/google/leveldb)

2、[leveldb-handbook](https://leveldb-handbook.readthedocs.io/zh/latest/index.html)

3、[LevelDB数据结构解析](https://www.qtmuniao.com/categories/源码阅读/leveldb/)

4、GPT
