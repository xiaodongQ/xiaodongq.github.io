---
layout: post
title: leveldb学习笔记（七） -- 布隆过滤器
categories: 存储
tags: 存储 leveldb
---

* content
{:toc}

leveldb学习笔记，本篇学习其布隆过滤器实现。



## 1. 背景

继续学习梳理leveldb中具体的流程，本篇来看下布隆过滤器实现。

之前学习记录中虽然有涉及但未展开：

[leveldb学习笔记（二） -- 读写操作流程](https://xiaodongq.github.io/2024/07/20/leveldb-io-implement/)里面的读写流程，没有展开说明

[leveldb学习笔记（五） -- sstable实现](https://xiaodongq.github.io/2024/08/07/leveldb-sstable/)里提到`filter block`是基于布隆过滤器实现的。

主要参考如下文章并映证leveldb代码：

* [漫谈 LevelDB 数据结构（二）：布隆过滤器（Bloom Filter）](https://www.qtmuniao.com/2020/11/18/leveldb-data-structures-bloom-filter/)
* [leveldb-handbook bloomfilter](https://leveldb-handbook.readthedocs.io/zh/latest/bloomfilter.html)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. Why

先看看leveldb为什么要用布隆过滤器？

对于 LevelDB 的一次读取操作，需要首先去 `memtable`、`immutable memtable` 查找，然后依次去`文件系统`(`sstable`文件)中各层查找。可以看出，相比写入操作，读取操作实在有点效率低下。我们这种客户端进行一次读请求，进入系统后被变成多次读请求的现象为**读放大**。

为了减小读放大，LevelDB 采取了几方面措施：

* 通过 `major compaction` 尽量减少 sstable 文件
* 使用快速筛选的办法，快速判断 key 是否在某个 sstable 文件中

而快速判断某个 key 是否在某个 key 集合中，LevelDB 用的正是**布隆过滤器**。

## 3. 布隆过滤器原理

Bloom Filter([wiki](https://en.wikipedia.org/wiki/Bloom_filter)) 是 Burton Howard Bloom于 1970 年 提出，相关论文为： [Space/time trade-offs in hash coding with allowable errors](https://dl.acm.org/doi/pdf/10.1145/362686.362692)。

Bloom Filter是一种空间效率很高的随机数据结构，它利用`位数组`很简洁地表示一个集合，并能判断一个元素是否属于这个集合。

Bloom Filter的这种高效是有一定代价的：在判断一个元素是否属于某个集合时，有可能会把不属于这个集合的元素误认为属于这个集合（false positive）。

因此，Bloom Filter不适合那些“零错误”的应用场合。而在能容忍低错误率的应用场合下，Bloom Filter通过极少的错误换取了存储空间的极大节省。

### 3.1. 结构

* bloom过滤器底层是一个位数组，初始时每一位都是0
* 插入：当插入值x后，分别利用k个哈希函数，利用x的值进行散列，并将散列得到的值与bloom过滤器的容量进行取余，将取余结果所代表的那一位值置为1。
* 查找：同样利用k个哈希函数对所需要查找的值进行散列，只有散列得到的每一个位的值均为1，才表示该值“有可能”真正存在；反之若有任意一位的值为0，则表示该值一定不存在。
    * 例如y1一定不存在；而y2可能存在。

示意图如下：

![布隆过滤器插入查找示意图](/images/2024-08-12-bloomfilter-case.png)

### 3.2. 相关参数

与布隆过滤器准确率有关的参数有：

* 哈希函数的个数k；
* 布隆过滤器位数组的容量m;
* 布隆过滤器插入的数据数量n;

并有如下结论：

* 为了获得最优的准确率，当`k = (ln2) * (m/n)`时，布隆过滤器获得最优的准确性；
* 在哈希函数的个数取到最优时，要让错误率不超过`ε`，m至少需要取到错判率最小值的`1.44`倍；
    * bloom filter中错判的概率叫 `false postive`，记为`ε`

可进一步查看：[经典论文解读——布隆过滤器](https://cloud.tencent.com/developer/article/2255688)，有基本的概率论知识就可以看懂里面的参数和概率证明。（里面还提到几种优化点和对应论文、redis中的扩展实现、golang中的实现等）

参考链接里提到`Murmur3`作为哈希函数，随机性很好。leveldb里自己实现的也是类murmur哈希(util/hash.cc中的`Hash`函数)

## 4. leveldb中的布隆过滤器

leveldb中利用布隆过滤器判断指定的key值是否存在于`sstable`中，若过滤器表示不存在，则该key一定不存在，由此加快了查找的效率。



## 5. 小结

学习梳理布隆过滤器实现逻辑。

## 6. 参考

1、[leveldb](https://github.com/google/leveldb)

2、[漫谈 LevelDB 数据结构（二）：布隆过滤器（Bloom Filter）](https://www.qtmuniao.com/2020/11/18/leveldb-data-structures-bloom-filter/)

3、[leveldb-handbook bloomfilter](https://leveldb-handbook.readthedocs.io/zh/latest/bloomfilter.html)

4、[经典论文解读——布隆过滤器](https://cloud.tencent.com/developer/article/2255688)

