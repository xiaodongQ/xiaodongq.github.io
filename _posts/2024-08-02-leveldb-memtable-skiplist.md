---
layout: post
title: leveldb学习笔记（四） -- memtable结构实现
categories: 存储
tags: 存储 leveldb
---

* content
{:toc}

leveldb学习笔记，本篇学习memtable结构实现，学习其基于的跳表实现细节。



## 1. 背景

前面跟踪学习了读写实现的基本流程，继续学习梳理其中具体的流程实现。本篇memtable结构实现，尤其是其中的跳表实现细节。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 跳表

跳表利用`概率均衡`技术，加快简化插入、删除操作，且保证*绝大多数操作*均拥有`O(log n)`的良好效率。

> 跳表由 William Pugh 在 1990 年提出，相关论文为：[Skip Lists: A Probabilistic Alternative to Balanced Trees](https://15721.courses.cs.cmu.edu/spring2018/papers/08-oltpindexes1/pugh-skiplists-cacm1990.pdf)。

* 跳表底层是一个普通的`有序`链表
* 按层建造，对于第i层（底层是1）每隔`2^i`个节点，新增一个辅助指针（或者说每`2^i`新增一个辅助节点），最终一次节点的查询效率为`O(log n)`
* 跳表的特征就是链表加`多级索引`的结构。

![跳表示意图](/images/skiplist_intro.jpeg)

* `a`为初始的有序链表，查找复杂度为`O(n)`（最多需要查n次，n为节点数）
* `b`在`a`的基础上每隔2个节点（跳步采样）新增一个辅助指针，即建立索引，查找至多只需要`n/2 + 1`次
* `c`在`b`的基础上再跳步采样新增辅助指针，查找至多只需要`n/4 + 2`次
* 同理，`d`在`c`、`e`在`d`的基础上跳步采样新增辅助指针

基于上述的简单推导，各层新增辅助索引后，查找的时间复杂度级别为`O(log n)`

### 2.1. 时间复杂度分析

这里参考：[跳表：为什么Redis一定要用跳表来实现有序集合？](https://time.geekbang.org/column/article/42896)

1、分析查找复杂度之前，先看这个辅助问题：**如果链表里有 n 个节点，会有多少级索引呢？**

每两个节点会抽出一个节点作为上一级索引的节点，那第一级索引的节点个数大约就是 `n/2`，第二级索引的节点个数大约就是 `n/4`，第三级索引的节点个数大约就是 `n/8`，依次类推，也就是说，第 `k` 级索引的节点个数是第 `k-1` 级索引的节点个数的 `1/2`，那第 `k`级索引节点的个数就是 `n/(2^k)`

假设索引有 `h` 级，最高级的索引有 `2` 个节点。通过上面的公式，我们可以得到 `n/(2^h)=2`，从而求得 `h=log2(n)-1`。如果包含原始链表这一层，整个跳表的**高度**就是 `log2(n)`。

所以解答上面的问题：**如果链表里有n个节点，会有`log2(n) - 1`级索引。**

示例：一个包含 64 个节点的链表，建立了五级索引  
![跳表建立索引示例](/images/2024-08-04-skiplist-index-case.png)

2、各操作的时间复杂度

1）查找：`O(logn)`

2）插入：先查找（`O(logn)`），再执行插入（`O(1)`），总体复杂度`O(logn)`

**跳表索引的动态更新：**

* 当我们不停地往跳表中插入数据时，如果我们不更新索引，就有可能出现某 2 个索引节点之间数据非常多的情况。极端情况下，跳表还会退化成单链表。
* 作为一种动态数据结构，我们需要某种手段来维护索引与原始链表大小之间的`平衡`，也就是说，如果链表中节点多了，索引节点就相应地增加一些，避免复杂度退化，以及查找、插入、删除操作性能下降。
* 跳表是通过`随机函数`来维护前面提到的“平衡性”
    * 通过一个随机函数，来决定将这个节点插入到哪几级索引中，比如随机函数生成了值 K，那我们就将这个节点添加到第一级到第 K 级这 K 级索引中。
    * 随机函数的选择很有讲究，从概率上来讲，能够保证跳表的索引大小和数据大小平衡性，不至于性能过度退化。（即上面提到的`概率均衡`）

3）删除：先查找（`O(logn)`），再删除（`O(1)`），总体复杂度`O(logn)`

注意：如果这个节点在索引中也有出现，我们除了要删除原始链表中的节点，还要删除索引中的。

### 2.2. 空间复杂度

假设原始链表大小为 n，那第一级索引大约有 n/2 个节点，第二级索引大约有 n/4 个节点，以此类推，每上升一级就减少一半，直到剩下 2 个节点。如果我们把每层索引的节点数写出来，就是一个等比数列。

这几级索引的节点总和就是 `n/2 + n/4 + n/8 … + 8 + 4 + 2 = n-2`。所以，**跳表的空间复杂度是 `O(n)`**。

也就是说，如果将包含 `n` 个节点的单链表构造成跳表，我们需要额外再用接近 `n` 个节点的存储空间。

上述等比数列求和过程如下：

* 等比数列求和 n/2, n/4, ... , 2 这个数列中一共有`log2(n/2)`项，等比数列求和公式 `S = a0(1-q^n) / (1-q)`, 其中`a0`表示首项，`n`表示项数。
* 这里的`a0=n/2`, `项数n=log2(n/2)`, `q=1/2`，则`S = (n/2)*(1-2/n) / (1-1/2) = n-2` (其中`q^n`对应`(1/2)^( log2(n/2) ) = 2/n`)

通过每3个或者每5个节点采样，可进一步减少空间占用。比如间隔3个节点采样，总的索引节点大约就是 `n/3+n/9+n/27+...+9+3+1=n/2`

实际上，在软件开发中，我们不必太在意索引占用的额外空间。在讲数据结构和算法时，我们习惯性地把要处理的数据看成整数，但是在实际的软件开发中，原始链表中存储的有可能是很大的对象，而索引节点只需要存储关键值和几个**指针**，并不需要存储对象，所以当对象比索引节点大很多时，那索引占用的额外空间就可以忽略了。

## 3. leveldb中的跳表实现

### 3.1. memtable类定义

leveldb中的`memtable`，key-value是有序的，底层基于`跳表(skiplist)`实现。绝大多数操作（读／写）的时间复杂度均为`O(log n)`，有着与`平衡树`相媲美的操作效率，但是从实现的角度来说简单许多。

看下内存数据库memtable的定义，可看到MemTable中的实现为：`SkipList<const char*, KeyComparator>`

```cpp
// db/memtable.h
class MemTable {
    ...
    // 跳表
    typedef SkipList<const char*, KeyComparator> Table;

    ~MemTable();  // Private since only Unref() should be used to delete it

    KeyComparator comparator_;
    int refs_;
    Arena arena_;
    // Table是跳表结构
    Table table_;
};
```

### 3.2. `SkipList`实现

看下leveldb里面的跳表定义和大致实现。

```cpp
// db/skiplist.h
template <typename Key, class Comparator>
class SkipList {
 private:
  struct Node;

 public:
  explicit SkipList(Comparator cmp, Arena* arena);

  SkipList(const SkipList&) = delete;
  SkipList& operator=(const SkipList&) = delete;

  void Insert(const Key& key);

  bool Contains(const Key& key) const;

  class Iterator {
   public:
    ...
    const Key& key() const;
    void Next();
    void Prev();
    void Seek(const Key& target);
    ...
   private:
    const SkipList* list_;
    Node* node_;
  };

 private:
  enum { kMaxHeight = 12 };

  inline int GetMaxHeight() const {
    return max_height_.load(std::memory_order_relaxed);
  }

  Node* NewNode(const Key& key, int height);
  int RandomHeight();
  bool Equal(const Key& a, const Key& b) const { return (compare_(a, b) == 0); }

  bool KeyIsAfterNode(const Key& key, Node* n) const;

  Node* FindGreaterOrEqual(const Key& key, Node** prev) const;

  Node* FindLessThan(const Key& key) const;

  Node* FindLast() const;

  // Immutable after construction
  Comparator const compare_;
  Arena* const arena_;  // Arena used for allocations of nodes

  Node* const head_;

  std::atomic<int> max_height_;  // Height of the entire list

  Random rnd_;
};
```

## 4. 小结

学习memtable的实现细节和跳表。

## 5. 参考

1、[leveldb](https://github.com/google/leveldb)

2、[leveldb-handbook](https://leveldb-handbook.readthedocs.io/zh/latest/index.html)

3、[漫谈 LevelDB 数据结构（一）：跳表（Skip List）](https://www.qtmuniao.com/2020/07/03/leveldb-data-structures-skip-list/)

4、[跳表：为什么Redis一定要用跳表来实现有序集合？](https://time.geekbang.org/column/article/42896)

5、GPT
