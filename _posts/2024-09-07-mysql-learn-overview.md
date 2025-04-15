---
title: MySQL学习实践（一） -- 整体架构和基本操作的流程
categories: [存储和数据库, MySQL]
tags: [存储, MySQL]
---

MySQL学习实践，本篇介绍整体架构和基本操作的流程。

## 1. 背景

MySQL没太系统深入地学习梳理，前面梳理学习了一下基于`LSM-Tree`的leveldb，此篇开始，深入学习下基于`B树/B+树`的MySQL。

学习过程中正好结合场景，对相关联的Linux存储、CPU、内存管理、进程管理等模块知识查漏补缺。

说明：

* 学习代码基于mysql-server的 [5.7.44 tag](https://github.com/mysql/mysql-server/tree/mysql-5.7.44)，由于仓库比较大，clone下来去掉log后单独创建一个自己的学习repo：[mysql-server_5.7.44](https://github.com/xiaodongQ/mysql-server_5.7.44.git)。
    * [8.0.26 tag的学习repo](https://github.com/xiaodongQ/mysql-server_8.0.26)
* 对应的官方文档：[MySQL 5.7 Reference Manual](https://dev.mysql.com/doc/refman/5.7/en/introduction.html)
    * [MySQL 8.0文档](https://dev.mysql.com/doc/refman/8.0/en/introduction.html)
* 网上资料很多，部分参考：
    * [MySQL 实战 45 讲](https://time.geekbang.org/column/intro/100020801)
    * [图解MySQL](https://www.xiaolincoding.com/mysql/)

9.7更新：之前（8月）此篇开篇后只写了一小部分，而后投入6.824学习，一直没继续，调整下日期重新续上。

9.10更新：学习调整为基于8.0.26 tag，和本地CentOS8上yum安装的MySQL保持一致。

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
[出处](https://www.xiaolincoding.com/mysql/base/how_select.html)

MySQL总体分为 `Server层` 和 `存储引擎层`。

* **Server层** 包含：连接器、查询缓存、解析器（词法分析、语法分析）、优化器、执行器等
    * 涵盖 MySQL 的大多数核心服务功能，以及所有的内置函数（如日期、时间、数学和加密函数等），
    * 所有跨存储引擎的功能都在这一层实现，比如存储过程、触发器、视图等。
* **存储引擎层**负责数据的存储和提取。
    * 其架构模式是`插件式`的，支持 InnoDB、MyISAM、Memory 等多个存储引擎。
    * 现在最常用的存储引擎是 InnoDB，它从 MySQL 5.5.5 版本开始成为了默认存储引擎。

下面通过 SQL查询语句 和 SQL更新语句 的示例，结合上述的架构示意图看下流程。

## 4. 查询语句的执行流程

查询语句示例：`select * from T where ID=10；`，其执行流程如下：

* 1、执行上述语句前，客户端通过 **连接器** 连接到数据库
    * 连接命令：`mysql -h$ip -P$port -u$user -p`，此处就会通过MySQL连接器建立连接
    * 连接器负责跟客户端建立连接、获取权限、维持和管理连接
* 2、连接建立后，会 **查询缓存**
    * MySQL收到一个查询请求后，会先到查询缓存(Query Cache)中查看之前是不是执行过这条语句。之前执行过的语句及其结果可能会以 key-value 对的形式，被直接缓存在内存中
    * 若命中缓存则直接返回
* 3、而后，**分析器**对 SQL 语句做解析
    * 分析器对SQL语句进行`词法分析`（别出里面的字符串分别是什么，代表什么）和`语法分析`（SQL语句是否满足 MySQL 语法）
* 4、开始执行前，需经过 **预处理器** 和 **优化器** 处理，确定SQL查询语句的执行方案
    * 预处理阶段：检查表或字段是否存在；将 `select *` 中的 `*` 符号扩展为表上的所有列
    * 不同方案执行效率可能不同，比如选择哪个索引、表的连接顺序
* 5、通过分析器知道了要做什么，通过优化器知道了该怎么做，于是就进入了 **执行器** 阶段，开始执行语句
    * 开始执行时，会检查对表是否有执行查询的`权限`（若前面命中缓存，则会在查询缓存结果时检查权限）
    * 执行器会调用 **存储引擎**（如`InnoDB`）的接口，进行交互操作，流程如下
        * 调用 InnoDB 引擎接口取表T的第一行，判断 ID 值是不是 10，如果不是则跳过，如果是则将这行存在结果集中；
        * 调用引擎接口取“下一行”，重复相同的判断逻辑，直到取到这个表的最后一行
        * 执行器将上述遍历过程中所有满足条件的行组成的记录集作为结果集返回给客户端

`执行器`和`存储引擎`的交互中，还涉及`主键索引查询`、`全表扫描`、`索引下推`等过程，后续篇幅再学习其流程。

## 5. 更新语句的执行流程

查询语句处理过程的那些模块，更新语句也会经历一遍。

更新语句示例：`update T set c=c+1 where ID=2;`（对应的建表语句`create table T(ID int primary key, c int);`）

流程：通过**连接器**连接数据库；表更新时**查询缓存**会失效；而后**分析器**进行词法分析和语法分析；**优化器**判定使用`ID`这个字段索引；而后**执行器**负责执行。

### 5.1. redo log 和 binlog

相比于查询流程，更新流程还涉及两个重要的日志模块：

* `redo log`（重做日志）
    * `redo log`是**InnoDB引擎**特有的日志
    * 当有记录要更新时，**InnoDB引擎**就会先记一条记录到`redo log`里，并更新内存，这次更新就结束了。InnoDB 引擎会在适当的时候，将这个操作记录更新到磁盘里面。
        * InnoDB的redo log大小是固定的（类似循环缓冲区），到一定长度就会通过`checkpoint`机制把记录刷写到数据文件里
    * 有了`redo log`，InnoDB 就可以保证即使数据库发生异常重启，之前提交的记录都不会丢失，这个能力称为`crash-safe`。
* `binlog`（归档日志）
    * `binlog`是**Server层**的日志，所有引擎都可以使用
    * MySQL 自带的引擎是 MyISAM，但是 MyISAM 没有 crash-safe 的能力，binlog 日志只能用于归档

两者差异点：

* redo log是InnoDB引擎层特有；而binlog是Server层日志，所有引擎均可使用
* redo log是物理日志，记录“在某个数据页上做了什么修改”；binlog是逻辑日志，记录SQL语句的原始逻辑，如给某字段加1
* redo log是循环写的，空间固定会用完；binlog是追加写入的，写到一定大小会切新文件进行写入，不会覆盖原以前的日志

### 5.2. 执行流程

执行器和存储引擎的交互，上面一笔带过了，此处结合上述两个日志说明下流程（语句：`update T set c=c+1 where ID=2;`）

* 1、**执行器**向**存储引擎**查找`ID=2`这行的记录。ID是主键，**存储引擎**(InnoDB)根据`树搜索`找到这一行记录。
    * 若记录所在的`数据页`本来就在内存，则直接返回给执行器；否则，先从磁盘读入内存，再返回给执行器
* 2、执行器拿到引擎返回的行记录，对`c`值+1得到新的行数据，再调用引擎接口**写入**这行新数据
* 3、引擎将这行数据更新到`内存`，同时将这个`更新操作`记录到 **`redo log`** 中（此时log处于`prepare`状态），然后告知执行器执行完成了，随时可以提交事务
* 4、而后 **执行器** 生成这个操作的 **`binlog`**，并把`binlog`写入磁盘
* 5、最后 **执行器** 调用引擎的`提交事务接口`，**存储引擎**把刚写入的`redo log`改成`提交（commit）`状态，更新完成。

处理流程示意图如下：  
![server层和引擎层更新处理流程](/images/2024-09-10-mysql-server-engine-layer.png)

上面更新流程中，存储引擎将`redo log`的操作分为了两个步骤：`prepare`和`commit`，这就是 **`两阶段提交`**，目的是为了让两份日志（`redo log`和`binlog`）保持一致，出现异常时能正确地恢复数据。

## 6. MySQL目录结构和启动流程

在本地CentOS8.5机器上安装MySQL用于实验跟踪：`yum install mysql-server mysql`

查看默认存储引擎，可知其为`InnoDB`。

```sh
mysql> show variables like "%storage_engine%";
+---------------------------------+-----------+
| Variable_name                   | Value     |
+---------------------------------+-----------+
| default_storage_engine          | InnoDB    |
| default_tmp_storage_engine      | InnoDB    |
| disabled_storage_engines        |           |
| internal_tmp_mem_storage_engine | TempTable |
+---------------------------------+-----------+
```

### 6.1. 目录结构

查看MySQL的数据目录：

```sh
mysql> show variables like "datadir";
+---------------+-----------------+
| Variable_name | Value           |
+---------------+-----------------+
| datadir       | /var/lib/mysql/ |
+---------------+-----------------+
```

该目录下相关文件目录的用途说明：

```sh
[root@xdlinux ➜ mysql ]$ ls -lh /var/lib/mysql/
total 185M
# 这是一个自动生成的配置文件，通常包含MySQL实例的唯一标识符（UUID）
-rw-r----- 1 mysql mysql   56 Sep 10 14:50  auto.cnf
# binlog文件，记录了所有对数据库的更改，主要用于数据恢复和主从复制
-rw-r----- 1 mysql mysql  156 Sep 10 14:50  binlog.000001
# 记录binlog文件的索引
-rw-r----- 1 mysql mysql   16 Sep 10 14:50  binlog.index
# *.pem 为SSL证书和密钥文件，用于加密MySQL客户端与服务器之间的通信
# `ca-key.pem`, `ca.pem`: 自签名 Certificate Authority (CA) 的密钥和证书
-rw------- 1 mysql mysql 1.7K Sep 10 14:50  ca-key.pem
-rw-r--r-- 1 mysql mysql 1.1K Sep 10 14:50  ca.pem
# `client-cert.pem`, `client-key.pem`: 客户端使用的 SSL 证书和密钥
-rw-r--r-- 1 mysql mysql 1.1K Sep 10 14:50  client-cert.pem
-rw------- 1 mysql mysql 1.7K Sep 10 14:50  client-key.pem
# 双写缓冲区（Doublewrite Buffer）日志，保存数据被写入到缓冲池和磁盘上的副本，以防系统崩溃后确保数据一致性
-rw-r----- 1 mysql mysql 192K Sep 10 14:52 '#ib_16384_0.dblwr'
-rw-r----- 1 mysql mysql 8.2M Sep 10 14:50 '#ib_16384_1.dblwr'
# InnoDB 缓冲池的状态文件，用于在 MySQL 重启后快速恢复缓冲池的状态
-rw-r----- 1 mysql mysql 5.9K Sep 10 14:50  ib_buffer_pool
# InnoDB 系统表空间文件，包含元数据、数据字典、Undo 日志等信息
-rw-r----- 1 mysql mysql  12M Sep 10 14:50  ibdata1
# ib_logfile0和ib_logfile1是redo log（重做日志）文件
# 记录了未完成事务的修改操作。系统崩溃后可以通过这些日志恢复数据变化
-rw-r----- 1 mysql mysql  48M Sep 10 14:52  ib_logfile0
-rw-r----- 1 mysql mysql  48M Sep 10 14:50  ib_logfile1
# InnoDB 用于临时数据的表空间文件
-rw-r----- 1 mysql mysql  12M Sep 10 14:50  ibtmp1
# 该目录用于 存储临时数据表的信息
drwxr-x--- 2 mysql mysql  187 Sep 10 14:50 '#innodb_temp'
# mysql目录和mysql.ibd，存储 MySQL 系统数据库的信息，如权限和用户信息
drwxr-x--- 2 mysql mysql  143 Sep 10 14:50  mysql
-rw-r----- 1 mysql mysql  24M Sep 10 14:50  mysql.ibd
# 服务器和本地主机上客户端进程之间的套接字文件
srwxrwxrwx 1 mysql mysql    0 Sep 10 14:50  mysql.sock
# 套接字文件的锁文件，用于管理访问
-rw------- 1 mysql mysql    6 Sep 10 14:50  mysql.sock.lock
# 存储 MySQL 升级过程中相关的信息
-rw-r--r-- 1 mysql mysql    7 Sep 10 14:50  mysql_upgrade_info
# MySQL X协议的套接字文件及其锁文件
srwxrwxrwx 1 mysql mysql    0 Sep 10 14:50  mysqlx.sock
-rw------- 1 mysql mysql    7 Sep 10 14:50  mysqlx.sock.lock
# 目录，该数据库包含性能模式相关的表，用于监控和诊断 MySQL 服务器的性能
drwxr-x--- 2 mysql mysql 8.0K Sep 10 14:50  performance_schema
# `private_key.pem`, `public_key.pem`: 私钥和公钥文件
-rw------- 1 mysql mysql 1.7K Sep 10 14:50  private_key.pem
-rw-r--r-- 1 mysql mysql  452 Sep 10 14:50  public_key.pem
# `server-cert.pem`, `server-key.pem`: 服务器使用的 SSL 证书和密钥
-rw-r--r-- 1 mysql mysql 1.1K Sep 10 14:50  server-cert.pem
-rw------- 1 mysql mysql 1.7K Sep 10 14:50  server-key.pem
# 目录，该数据库包含系统视图，提供更高级别的监控和诊断功能
drwxr-x--- 2 mysql mysql   28 Sep 10 14:50  sys
# undo文件，用于事务的回滚和多版本并发控制（MVCC）
-rw-r----- 1 mysql mysql  16M Sep 10 14:52  undo_001
-rw-r----- 1 mysql mysql  16M Sep 10 14:52  undo_002
```

每创建一个数据库，都会在数据目录（此处为`/var/lib/mysql/`）。如下建库建表示例：

```sh
# 建库
mysql> create database xdtestdb;
Query OK, 1 row affected (0.07 sec)

mysql> show databases;
+--------------------+
| Database           |
+--------------------+
| information_schema |
| mysql              |
| performance_schema |
| sys                |
| xdtestdb           |
+--------------------+

# 建表
mysql> create table test1(id int primary key, name varchar(32));
mysql> show tables;
+--------------------+
| Tables_in_xdtestdb |
+--------------------+
| test1              |
+--------------------+
```

数据目录多了：`/var/lib/mysql/xdtestdb`，其中包含**表数据**文件`test1.ibd`

```sh
[root@xdlinux ➜ ~ ]$ ll /var/lib/mysql/xdtestdb -ltrh
total 112K
-rw-r----- 1 mysql mysql 112K Sep 11 14:43 test1.ibd
```

### 6.2. 启动流程

看下启动流程，入口代码在`sql/main.cc`。`main` -> `mysqld_main`，单函数有点长，`mysqld_main`实现有1000多行。

```cpp
// mysql-server_8.0.26/sql/main.cc
int main(int argc, char **argv) { return mysqld_main(argc, argv); }
```

启动流程部分内容：

```cpp
// mysql-server_8.0.26/sql/mysqld.cc
int mysqld_main(int argc, char **argv)
{
  ...
  // 初始化线程环境pthread，锁资源
  // my_init函数中设置了创建新文件、新目录的权限。mysql默认创建新文件、新目录的权限为0640、0750（UMASK和UMASK_DIR）
  if (my_init())  // init my_sys library & pthreads
  {
    LogErr(ERROR_LEVEL, ER_MYINIT_FAILED);
    flush_error_log_messages();
    return 1;
  }
  ...
  // 处理配置文件及启动参数
  if (load_defaults(MYSQL_CONFIG_NAME, load_default_groups, &argc, &argv,
                    &argv_alloc)) {
    flush_error_log_messages();
    return 1;
  }
  ...
  /* Determine default TCP port and unix socket name */
  set_ports();
  // 初始化核心组件，包括众多核心模块的初始化，如innodb启动、插件初始化、error log启动等
  if (init_server_components()) unireg_abort(MYSQLD_ABORT_EXIT);
  ...
  if (!opt_initialize && (dd::upgrade::no_server_upgrade_required() ||
                        opt_upgrade_mode == UPGRADE_MINIMAL))
    // 从 mysql数据库 表中初始化结构数据
    servers_init(nullptr);
  ...
  // 这里就完成了mysqld的启动过程，在此处开始循环接受客户端连接
  mysqld_socket_acceptor->connection_event_loop();
  ...

  if (signal_thread_id.thread != 0)
    ret = my_thread_join(&signal_thread_id, nullptr);
  signal_thread_id.thread = 0;
  if (0 != ret)
    LogErr(WARNING_LEVEL, ER_CANT_JOIN_SHUTDOWN_THREAD, "signal_", ret);

  clean_up(true);
  sysd::notify("STATUS=Server shutdown complete");
  mysqld_exit(signal_hand_thr_exit_code);
}
```

## 7. 小结

通过SQL查询和更新语句的处理流程，了解MySQL的基本架构。

## 8. 参考

1、[what-is-mysql](https://dev.mysql.com/doc/refman/5.7/en/what-is-mysql.html)

2、[The Main Features of MySQL](https://dev.mysql.com/doc/refman/5.7/en/features.html)

3、[专访“MySQL 之父”：我曾创造 MySQL，也将颠覆 MySQL](https://www.infoq.cn/article/3xtSDtHUgTKRsyw3kZXH)

4、[MySQL实战45讲-01 基础架构：一条SQL查询语句是如何执行的？](https://time.geekbang.org/column/article/68319)

5、[执行一条 select 语句，期间发生了什么？](https://www.xiaolincoding.com/mysql/base/how_select.html)

6、[MySQL 一行记录是怎么存储的？](https://www.xiaolincoding.com/mysql/base/row_format.html)

7、[MySQL实例启动过程（上）：server层](https://developer.aliyun.com/article/1205737)

8、GPT
