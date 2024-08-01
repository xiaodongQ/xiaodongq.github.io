---
layout: post
title: leveldb学习笔记（三） -- memtable结构实现
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

## 3. 写流程中的memtable转换

上述梳理日志流程的小节中，提到了`MakeRoomForWrite`，此处进行分析。


## 4. 小结

学习memtable的实现细节。

## 5. 参考

1、[leveldb](https://github.com/google/leveldb)

2、[leveldb-handbook](https://leveldb-handbook.readthedocs.io/zh/latest/index.html)

3、[漫谈 LevelDB 数据结构（一）：跳表（Skip List）](https://www.qtmuniao.com/2020/07/03/leveldb-data-structures-skip-list/)

4、GPT
