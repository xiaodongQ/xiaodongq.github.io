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

## 2. MySQL介绍和整体架构

MySQL和MariaDB背景了解：

* `MySQL` 是以联合创始人 [Monty Widenius](https://en.wikipedia.org/wiki/Michael_Widenius) 的女儿 `My` 命名的。
* 2008 年 1 月，Monty 和其他几位创始人决定将`MySQL AB`公司出售给 Sun Microsystems。一年后，甲骨文收购了 Sun，把 MySQL 也收归麾下。2009 年 2 月 5 日，Monty 宣布离开 Sun 公司，在 MySQL 代码库的一个分支上开发出了一款数据库 `MariaDB`，以他最小的女儿的名字命名。同时，Monty 创办了 Monty Program AB 公司。
* （[参考](https://www.infoq.cn/article/3xtSDtHUgTKRsyw3kZXH)）

一些基本介绍：

* 基于C和C++开发，用`CMake`来管理构建
* 使用各种不同的编译器进行测试
* 使用 `Purify` (一个商业内存泄漏检测器)以及`Valgrind`进行测试
* 使用具有独立模块的多层服务设计
* 

参考：

* [what-is-mysql](https://dev.mysql.com/doc/refman/5.7/en/what-is-mysql.html)
* [The Main Features of MySQL](https://dev.mysql.com/doc/refman/5.7/en/features.html)



有人纠结读音，官方并不具体要求，语境对齐即可：

> The official way to pronounce “MySQL” is “My Ess Que Ell” (not “my sequel”), but we do not mind if you pronounce it as “my sequel” or in some other localized way.

### 2.2. 整体架构



## 5. 小结


## 6. 参考

1、[what-is-mysql](https://dev.mysql.com/doc/refman/5.7/en/what-is-mysql.html)
