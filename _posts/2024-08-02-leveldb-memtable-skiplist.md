---
layout: post
title: leveldb学习笔记（四） -- memtable结构实现
categories: 存储
tags: 存储 leveldb
---

* content
{:toc}

leveldb学习笔记，本篇学习memtable结构实现，学习跳表实现细节。



## 1. 背景

前面跟踪学习了读写实现的基本流程，继续学习梳理其中具体的流程实现。本篇memtable结构实现，尤其是其中的跳表实现细节。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. memtable类定义

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

## 3. 跳表

跳表利用`概率均衡`技术，加快简化插入、删除操作，且保证*绝大多数操作*均拥有`O(log n)`的良好效率。

* 跳表底层是一个普通的`有序`链表
* 按层建造，对于第i层（底层是1）每隔`2^i`个节点，新增一个辅助指针，最终一次节点的查询效率为`O(log n)`

![跳表示意图](/images/skiplist_intro.jpeg)

* `a`为初始的有序链表，查找复杂度`O(n)`

## 4. leveldb里的跳表实现s

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


## 5. 小结

学习memtable的实现细节。

## 6. 参考

1、[leveldb](https://github.com/google/leveldb)

2、[leveldb-handbook](https://leveldb-handbook.readthedocs.io/zh/latest/index.html)

3、[漫谈 LevelDB 数据结构（一）：跳表（Skip List）](https://www.qtmuniao.com/2020/07/03/leveldb-data-structures-skip-list/)

4、GPT
