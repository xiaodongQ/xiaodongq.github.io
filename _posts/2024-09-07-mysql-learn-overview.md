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

* **Server层** 包含：连接器、查询缓存、解析器（词法分析、语法分析）、优化器、执行器等
    * 涵盖 MySQL 的大多数核心服务功能，以及所有的内置函数（如日期、时间、数学和加密函数等），
    * 所有跨存储引擎的功能都在这一层实现，比如存储过程、触发器、视图等。
* **存储引擎层**负责数据的存储和提取。
    * 其架构模式是`插件式`的，支持 InnoDB、MyISAM、Memory 等多个存储引擎。
    * 现在最常用的存储引擎是 InnoDB，它从 MySQL 5.5.5 版本开始成为了默认存储引擎。

下面通过 SQL查询语句 和 SQL更新语句 的示例，结合上述的架构示意图看下流程。

### 3.1. 一条查询语句的执行流程

查询语句示例：`select * from T where ID=10；`，其执行流程如下：

* 1、执行上述语句前，客户端通过`连接器`连接到数据库
    * 连接命令：`mysql -h$ip -P$port -u$user -p`，此处就会通过MySQL连接器建立连接
    * 连接器负责跟客户端建立连接、获取权限、维持和管理连接
* 2、连接建立后，会`查询缓存`
    * MySQL收到一个查询请求后，会先到查询缓存(Query Cache)中查看之前是不是执行过这条语句。之前执行过的语句及其结果可能会以 key-value 对的形式，被直接缓存在内存中
    * 若命中缓存则直接返回
* 3、而后，`分析器`对 SQL 语句做解析
    * 分析器对SQL语句进行`词法分析`（别出里面的字符串分别是什么，代表什么）和`语法分析`（SQL语句是否满足 MySQL 语法）
* 4、开始执行前，需经过`预处理`和`优化器`处理，确定SQL查询语句的执行方案
    * 预处理阶段：检查表或字段是否存在；将 `select *` 中的 `*` 符号扩展为表上的所有列
    * 不同方案执行效率可能不同，比如选择哪个索引、表的连接顺序
* 5、通过分析器知道了要做什么，通过优化器知道了该怎么做，于是就进入了`执行器`阶段，开始执行语句
    * 开始执行时，会检查对表是否有执行查询的`权限`（若前面命中缓存，则会在查询缓存结果时检查权限）
    * 执行器会调用`存储引擎`（如`InnoDB`）的接口，进行交互操作，流程如下
        * 调用 InnoDB 引擎接口取表T的第一行，判断 ID 值是不是 10，如果不是则跳过，如果是则将这行存在结果集中；
        * 调用引擎接口取“下一行”，重复相同的判断逻辑，直到取到这个表的最后一行
        * 执行器将上述遍历过程中所有满足条件的行组成的记录集作为结果集返回给客户端

`执行器`和`存储引擎`的交互过程，还涉及`主键索引查询`、`全表扫描`、`索引下推`

## 4. 小结


## 5. 参考

1、[what-is-mysql](https://dev.mysql.com/doc/refman/5.7/en/what-is-mysql.html)

2、[The Main Features of MySQL](https://dev.mysql.com/doc/refman/5.7/en/features.html)

3、[专访“MySQL 之父”：我曾创造 MySQL，也将颠覆 MySQL](https://www.infoq.cn/article/3xtSDtHUgTKRsyw3kZXH)

4、[MySQL45讲-01 基础架构：一条SQL查询语句是如何执行的？](https://time.geekbang.org/column/article/68319)

5、[执行一条 select 语句，期间发生了什么？](https://www.xiaolincoding.com/mysql/base/how_select.html)
