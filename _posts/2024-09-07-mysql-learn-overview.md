---
layout: post
title: 深入学习MySQL（一） -- 整体架构和基本操作
categories: 存储
tags: 存储 MySQL
---

* content
{:toc}

深入学习MySQL，本篇介绍整体架构和基本操作。



## 1. 背景

MySQL一直没太系统地学习梳理，前面梳理学习了一下基于`LSM-Tree`的leveldb，此篇开始，深入学习下基于`B树/B+树`的MySQL。

学习过程中正好结合场景，对相关联的Linux存储、CPU、内存管理、进程管理等模块知识查漏补缺。

说明：

* 学习代码基于mysql-server的 [5.7.44 tag](https://github.com/mysql/mysql-server/tree/mysql-5.7.44)，由于仓库比较大，clone下来去掉log后单独创建一个自己的学习repo：[mysql-server_5.7.44](https://github.com/xiaodongQ/mysql-server_5.7.44.git)。
* 对应的官方文档：[MySQL 5.7 Reference Manual](https://dev.mysql.com/doc/refman/5.7/en/introduction.html)
* 网上资料很多，部分参考：
    * [MySQL 实战 45 讲](https://time.geekbang.org/column/intro/100020801)
    * [图解MySQL](https://www.xiaolincoding.com/mysql/)

9.7更新：之前（8月）此篇开篇后只写了一小部分，而后投入6.824学习，一直没继续，调整下日期重新续上。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. MySQL基本介绍

MySQL和MariaDB背景：

* `MySQL` 是以联合创始人 [Monty Widenius](https://en.wikipedia.org/wiki/Michael_Widenius) 的女儿 `My` 命名的。
* 2008 年 1 月，Monty 和其他几位创始人决定将`MySQL AB`公司出售给 Sun Microsystems。一年后，甲骨文收购了 Sun，把 MySQL 也收归麾下。2009 年 2 月 5 日，Monty 宣布离开 Sun 公司，在 MySQL 代码库的一个分支上开发出了一款数据库 `MariaDB`，以他最小的女儿的名字命名。同时，Monty 创办了 Monty Program AB 公司。
* （[参考](https://www.infoq.cn/article/3xtSDtHUgTKRsyw3kZXH)）

MySQL是开源的关系型数据库，基于客户端/服务器模式，主要特性说明：

* 基于C和C++开发，用`CMake`来管理构建
* 使用各种不同的编译器进行测试
* 使用 `Purify` (一个商业内存泄漏检测器)以及`Valgrind`进行测试
* 使用具有独立模块的多层服务设计
* 基于多线程设计
* 提供事务性和非事务性存储引擎
* 基于B树索引(MyISAM)
* 设计相对容易的方式来使用其他存储引擎
* 使用快速的线程安全的内存分配系统
* 使用优化的嵌套循环join
* 实现内存态的哈希表用于临时表
* 使用高度优化的类库实现SQL函数，在查询初始化后基本不需要再分配内存
* 提供单独的服务器程序，以便在C/S网络架构环境中使用

关于读音，官方并不具体要求，语境对齐即可：

> The official way to pronounce “MySQL” is “My Ess Que Ell” (not “my sequel”), but we do not mind if you pronounce it as “my sequel” or in some other localized way.

参考：

* [what-is-mysql](https://dev.mysql.com/doc/refman/5.7/en/what-is-mysql.html)
* [The Main Features of MySQL](https://dev.mysql.com/doc/refman/5.7/en/features.html)

## 3. 整体架构

MySQL基本架构示意图:

![MySQL基本架构示意图](/images/2024-09-08-mysql-architecture.png)

MySQL总体分为 `Server层` 和 `存储引擎层`。

参考链接里给了个示例：`select * from T where ID=10；`，通过这个查询语句的执行过程看基本架构流程。

* 连接器、查询缓存、解析器（词法分析、语法分析）、优化器、执行器、存储引擎

## 4. 小结


## 5. 参考

1、[what-is-mysql](https://dev.mysql.com/doc/refman/5.7/en/what-is-mysql.html)

2、[The Main Features of MySQL](https://dev.mysql.com/doc/refman/5.7/en/features.html)

3、[专访“MySQL 之父”：我曾创造 MySQL，也将颠覆 MySQL](https://www.infoq.cn/article/3xtSDtHUgTKRsyw3kZXH)

4、[MySQL45讲-01 基础架构：一条SQL查询语句是如何执行的？](https://time.geekbang.org/column/article/68319)

5、[执行一条 select 语句，期间发生了什么？](https://www.xiaolincoding.com/mysql/base/how_select.html)
