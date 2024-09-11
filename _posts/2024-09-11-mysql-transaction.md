---
layout: post
title: 深入学习MySQL（一） -- MySQL事务
categories: MySQL
tags: 存储 MySQL
---

* content
{:toc}

深入学习MySQL，本篇学习梳理MySQL事务。



## 1. 背景

本篇梳理学习MySQL事务。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 事务特性

ACID：

* `原子性（Atomicity）`：一个事务中的所有操作，要么全部完成，要么全部不完成
* `一致性（Consistency）`：事务操作前和操作后，数据满足完整性约束，数据库保持一致性状态
* `隔离性（Isolation）`：多个事务并发执行使用相同的数据时，不会相互干扰
* `持久性（Durability）`：事务处理结束后，对数据的修改就是永久的，即便系统故障也不会丢失

InnoDB引擎通过如下技术保证事务的ACID特性：

* `持久性`通过 `redo log（重做日志）`来保证
* `原子性`通过 `undo log（回滚日志）` 来保证
* `隔离性`通过 `MVCC（多版本并发控制）` 或`锁机制`来保证
* `一致性`通过`持久性`+`原子性`+`隔离性`来保证

## 3. 事务隔离级别

隔离性(ACID中的Isolation)：多个事务同时执行的时候，可能出现脏读(dirty read)、不可重复读(non-repeatable read)、幻读(phantom read)问题，为了解决这些问题，于是有了不同的隔离级别。

SQL标准的事务隔离级别：

* **读未提交(read uncommitted)**，事务未提交时，其做的变更就能被其他事务看到
* **读提交(read committed)**，事务提交后，其变更才能被其他事务看到
* **可重复读(repeatable read)**，事务提交前，看到的数据和事务启动时一直是一致的
* **串行化(serializable)**，通过加锁(读写锁)机制，读写锁冲突时，后访问的事务必须等待前一个事务执行完成，才能继续执行

当前会话隔离级别：可看到默认级别是`可重复读`

```sh
mysql> show variables like 'transaction_isolation';
+-----------------------+-----------------+
| Variable_name         | Value           |
+-----------------------+-----------------+
| transaction_isolation | REPEATABLE-READ |
+-----------------------+-----------------+
1 row in set (0.01 sec)
```

全局隔离级别：默认也是`可重复读`

```sh
mysql> show global variables like 'transaction_isolation';
+-----------------------+-----------------+
| Variable_name         | Value           |
+-----------------------+-----------------+
| transaction_isolation | REPEATABLE-READ |
+-----------------------+-----------------+
1 row in set (0.01 sec)
```

## 4. 事务隔离的实现

事务是由MySQL的`引擎`来实现的，`InnoDB`引擎是支持事务的，而MySQL原生的`MyISAM`引擎不支持事务。

在 MySQL 中，实际上每条记录在更新的时候都会同时记录一条回滚操作。记录上的最新值，通过回滚操作，都可以得到前一个状态的值。

同一条记录在系统中可以存在多个版本，这就是数据库的`多版本并发控制（MVCC，Multi-Version Concurrency Control）`

## 5. 小结


## 6. 参考

1、[MySQL实战45讲-3 事务隔离：为什么你改了我还看不见？](https://jiketime.geekbang.org/column/article/68963)

2、[事务隔离级别是怎么实现的？](https://www.xiaolincoding.com/mysql/transaction/mvcc.html)
