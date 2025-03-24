---
layout: post
title: Redis学习实践（一） -- 数据结构和关键特性
categories: Redis
tags: Redis 存储
---

* content
{:toc}

Redis学习实践系列，本篇进行总体说明，说明数据结构和关键特性。



## 1. 背景

前面梳理的知识脉络中或多或少覆盖了网络、存储、内存、进程管理等，虽然不少东西还没太深入，不过已经打了一个底子，后续逐步添砖加瓦。开始基于实际的优秀产品和开源项目补充夯实技能栈，梳理并进行相关实践。

先死磕存储领域相关内容（内容很多，忌贪多嚼不烂，过程中拓展广度和深度）：

* `Redis`、`MySQL`、`Ceph`、`RocksDB`、`HDFS`
* 后续进一步梳理学习：`PostgreSQL`，以及之前关注了解的 `Curve`、`TiDB`、`JuiceFS`、`CubeFS`、`GlusterFS`，以及近期比较火热的DeepSeek开源的`3FS`（Fire-Flyer File System,萤火文件系统）等

Redis之前看过代码但未系统梳理，本篇开始，先来梳理学习其相关内容并进行部分实验。

简要介绍：

* Redis（`Remote Dictionary Server`）是一个使用ANSI C编写的支持网络、基于内存、分布式、可选持久性的**键值对**存储数据库，作者是 [Salvatore Sanfilippo（也叫 antirez）](http://invece.org/)。
* 2024年，开源许可从Redis 7.4版本开始，由`BSD-3-Clause`协议转换为 `SSPLv1` 和 `RSALv2` 双重许可证。介绍可见：[Redis](https://en.wikipedia.org/wiki/Redis)。

Redis应用场景很多，比如缓存系统、消息队列、分布式锁等，比如下述缓存系统简单示例图（主要为了试下`Follow Animation`动态箭头效果）：

![example_redis_mysql_case](/images/example_redis_mysql_case.svg)

## 2. 前置说明

梳理代码基于支持了多线程特性的6.0版本：[redis 6.0](https://github.com/redis/redis/tree/6.0)。并进行 [fork](https://github.com/xiaodongQ/redis/tree/6.0)。

几个参考：

* [Redis 核心技术与实战](https://time.geekbang.org/column/intro/100056701)
* [Redis 源码剖析与实战](https://time.geekbang.org/column/intro/100084301)
* [图解Redis](https://www.xiaolincoding.com/redis/)
* [Redis系列文章](https://mp.weixin.qq.com/mp/appmsgalbum?action=getalbum&__biz=MzIyOTYxNDI5OA==&scene=1&album_id=1699766580538032128&count=3&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=0&fontScale=100)

## 3. 支持的数据类型

### 3.1. 数据类型

5种最常用数据类型：`String`、`List`、`Hash`、`Set`、`Zset`

* `String`
* `List`
* `Hash`
* `Set`
* `Zset`

其他4种数据类型：`BitMap`、`HyperLogLog`、`GEO`、`Stream`

* `BitMap`
* `HyperLogLog`
* `GEO`
* `Stream`

### 3.2. 数据结构

上述“数据类型”用到的“数据结构”

* SDS
* 双向链表
* 压缩列表（ziplist）
* hash table
* 整数集合（intset）
* 跳表（skiplist）

### 3.3. 底层实现

1、String

## 4. 关键特性

### 4.1. 事件循环和多线程

主线程基于epoll进行IO多路复用处理，前面 [梳理Redis中的epoll机制](https://xiaodongq.github.io/2025/02/28/epoll-redis-nginx/) 中已经梳理过，此处不做展开。

## 5. 小结


## 6. 参考

* [Redis 核心技术与实战](https://time.geekbang.org/column/intro/100056701)
* [Redis 源码剖析与实战](https://time.geekbang.org/column/intro/100084301)
* [图解Redis](https://www.xiaolincoding.com/redis/)
* [Redis系列文章](https://mp.weixin.qq.com/mp/appmsgalbum?action=getalbum&__biz=MzIyOTYxNDI5OA==&scene=1&album_id=1699766580538032128&count=3&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=0&fontScale=100)
