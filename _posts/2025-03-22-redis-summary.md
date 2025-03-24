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

Redis应用场景很多，比如缓存系统、消息队列、分布式锁等，比如下述缓存系统简单示意图（主要为了试下`Follow Animation`动态箭头效果）：

![example_redis_mysql_case](/images/example_redis_mysql_case.svg)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 前置说明

梳理代码基于支持了多线程特性的6.0版本：[redis 6.0](https://github.com/redis/redis/tree/6.0)。并进行 [fork](https://github.com/xiaodongQ/redis/tree/6.0)。

几个参考：

* [Redis 核心技术与实战](https://time.geekbang.org/column/intro/100056701)
* [Redis 源码剖析与实战](https://time.geekbang.org/column/intro/100084301)
* [图解Redis](https://www.xiaolincoding.com/redis/)
* [Redis系列文章](https://mp.weixin.qq.com/mp/appmsgalbum?action=getalbum&__biz=MzIyOTYxNDI5OA==&scene=1&album_id=1699766580538032128&count=3&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=0&fontScale=100)

## 3. 支持的数据类型

### 3.1. 数据类型和底层数据结构

5种最常用数据类型：`String`、`List`、`Hash`、`Set`、`Zset`

1、`String`

* 最大容纳`512MB`
* 底层数据结构：`SDS`，可保存文本以及二进制数据、长度获取复杂度`O(1)`、字符串操作安全（因为有了头中的长度）
* 基本命令：GET、SET、EXIST、STRLEN、DEL；MGET、MSET；SETEX、EXPIRE、TTL；INCR、INCRBY、DECR、DECRBY；SETNX等
* 应用场景
    * 缓存对象：方式1）直接缓存json 方式2）按k-v分离，通过MSET存储、MGET获取
    * 常规计数：如访问次数、点赞、转发、库存。`SET aritcle:readcount:1001 0`初始化，而后`INCR aritcle:readcount:1001`
    * 分布式锁：SET有个`NX`参数可以实现“key不存在才插入”，可以用它来实现分布式锁
        * `SET lock_key unique_value NX PX 10000`，若不存在则设置，表示加锁成功；
        * 删除key则表示解锁，需要保证删除者是加锁客户端，需要 Lua脚本 保证原子性
    * 共享Session信息：分布式系统中同用户多次请求可能分配到不同服务器，通过Redis共享统一的会话状态可避免重复登录

2、`List`

* 字符串列表，最大元素个数：`2^32-1`（40亿）
* 底层数据结构
    * 3.2版本前：双向链表 或 压缩列表（ziplist），当 `(列表元素个数<512 && 元素值<64字节)` 时，会用ziplist作底层数据结构，否则用双向链表
    * **3.2之后：只用`quicklist`，替代了双向链表和压缩列表**
* 基本命令：LPUSH、RPUSH、LPOP、RPOP、LRANGE、BLPOP、BRPOP、LLEN、LSET等
* 应用场景
    * 消息队列：LPUSH+RPOP 或者 RPUSH+LPOP 实现先进先出。为了避免没有数据时的循环POP判断，Redis提供了`BRPOP`方式；为避免重复消费，**需自行实现全局ID**，如 `LPUSH mq "111000102:stock:99"`；为避免消息消费后处理异常，Redis提供了`BRPOPLPUSH`，在消费的同时插入另一个List备份；**不能多消费者以消费组形式消费**

3、`Hash`

* 键值对
* 底层数据结构
    * 压缩列表 或 哈希表，当 `(元素个数<512 && 所有值<64字节)` 时，会使用ziplist作底层数据结构，否则使用哈希表
    * **Redis7.0中，压缩列表数据结构已经废弃，交由 `listpack` 数据结构实现**
* 常用命令：HSET、HGET、HMSET、HMGET、HDEL、HLEN、HGETALL、HINCRBY等
* 应用场景
    * 缓存对象：上面String也可以存放对象，对于频繁变化的属性可以考虑抽出来用Hash存储
    * 购物车：以用户id为 key，商品id 为 field，商品数量为 value（`HSET key field value`）

4、`Set`

* 无序集合，最大个数：`2^32-1`。除了支持集合内的增删改查，同时还支持多个集合取交集、并集、差集。
* 底层数据结构：哈希表 或 整数集合，当`(元素都是整数 && 个数<512)`，使用整数集合作底层数据结构，否则使用哈希表
* 常用命令：SADD、SREM、SMEMBERS、SCARD、SISMEMBER、SPOP；SINTER、SUNION、SDIFF等
* 应用场景
    * Set类型比较适合用来数据去重和保障数据的唯一性，还可以用来统计多个集合的交集、错集和并集等
        * 但要注意：Set的差集、并集和交集的计算复杂度较高，在数据量较大的情况下，如果直接执行这些计算，会导致 Redis 实例阻塞。
    * 点赞（一个用户只能点一个赞）、共同关注（交集运算）、抽奖活动（`SRANDMEMBER`、`SPOP`随机取元素）

5、`Zset`

* 有序集合，相比Set多了排序属性 `score`（分值）
* 底层数据结构：
    * 压缩列表 或 跳表，`(个数<128 && 每个元素值<64字节)`时，会使用ziplist作底层数据结构，否则使用跳表
    * **Redis7.0中，压缩列表数据结构已经废弃，交由 `listpack` 数据结构实现**
* 常用命令：ZADD、ZREM、ZSCORE、ZCARD、ZINCRBY、ZRANGE、ZRANGEBYSCORE、ZRANGEBYLEX；ZUNIONSTORE、ZINTERSTORE等
* 应用场景
    * 排行榜，例如学生成绩的排名榜、游戏积分排行榜、视频播放排名、电商系统中商品的销量排名
    * 电话、姓名排序，`ZRANGEBYLEX`

其他4种数据类型：`BitMap`、`HyperLogLog`、`GEO`、`Stream`

6、`BitMap`(2.2版本新增)

* 位图，是一串连续的二进制数组（0和1），可以通过偏移量（offset）定位元素
* 底层数据结构：String类型作为底层数据结构实现的一种统计二值状态的数据类型
* 常用命令：SETBIT、GETBIT、BITCOUNT；BITOP、BITPOS
* 应用场景：非常适合二值状态统计的场景
    * 签到统计
    * 判断用户登陆态
    * 连续签到用户总数

7、`HyperLogLog`(2.8版本新增)

* 统计基数，统计一个集合中不重复的元素个数。HyperLogLog是统计规则是基于概率完成的，存在误差。优点是在输入元素的数量或者体积非常非常大时，计算基数所需的内存空间总是固定的、并且是很小的

8、`GEO`(3.2版本新增)

* 存储地理位置信息，并对存储的信息进行操作
* 底层数据结构：本身并没有设计新的底层数据结构，而是直接使用了 Sorted Set 集合类型。使用 GeoHash 编码方法
* 应用场景：滴滴叫车

9、`Stream`(5.0版本新增)

* 支持消息的持久化、支持自动生成全局唯一ID、支持 ack 确认消息的模式、支持消费组模式等，让消息队列更加的稳定和可靠。
* 应用场景：消息队列

### 3.2. 数据结构实现说明

简要说明上述“数据类型”用到的“数据结构”对应的实现。

1、SDS

* 相对普通字符串，其实现中包含：长度 `len` 和分配空间长度 `alloc`，能灵活保存不同大小的字符串，从而有效**节省内存空间**
    * sdshdr8、sdshdr16、32、64，以及sdshdr5（不再使用），定义差别是`len`和`alloc`使用`uint16`、`uint32`、64等支持不同长度
* `attribute ((packed))`，告知编译器，在编译 sdshdr8 结构时，不要使用字节对齐的方式，而是采用**紧凑的方式分配内存**

```c
// redis/src/sds.h
struct __attribute__ ((__packed__)) sdshdr8 {
    // 字符数组现有长度
    uint8_t len; /* used */
    // 字符数组的已分配空间，不包括结构体和\0结束字符
    uint8_t alloc; /* excluding the header and null terminator */
    // SDS类型，低3位表示类型，和b111进行位掩码取&
    unsigned char flags; /* 3 lsb of type, 5 unused bits */
    // 字符数组数据
    char buf[];
};
```

2、双向链表

3、压缩列表（ziplist）

4、hash table

5、整数集合（intset）

6、跳表（skiplist）

## 4. 关键特性

### 4.1. 事件循环和多线程

主线程基于epoll进行IO多路复用判断处理，前面 [梳理Redis中的epoll机制](https://xiaodongq.github.io/2025/02/28/epoll-redis-nginx/) 中已经梳理过，此处不做展开。



### 4.2. RDB和AOF

### 4.3. 主从和哨兵



## 5. 小结


## 6. 参考

* [Redis 核心技术与实战](https://time.geekbang.org/column/intro/100056701)
* [Redis 源码剖析与实战](https://time.geekbang.org/column/intro/100084301)
* [图解Redis](https://www.xiaolincoding.com/redis/)
* [Redis系列文章](https://mp.weixin.qq.com/mp/appmsgalbum?action=getalbum&__biz=MzIyOTYxNDI5OA==&scene=1&album_id=1699766580538032128&count=3&uin=&key=&devicetype=iMac+MacBookPro12%2C1+OSX+OSX+12.6.4+build(21G526)&version=13080911&lang=zh_CN&nettype=WIFI&ascene=0&fontScale=100)
