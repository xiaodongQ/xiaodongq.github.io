---
layout: post
title: leveldb学习笔记（二） -- 读写操作流程
categories: 存储
tags: 存储 leveldb
---

* content
{:toc}

leveldb学习笔记，本篇学习其读写操作流程。



## 1. 背景

[leveldb学习笔记（一） -- 整体架构和基本操作](https://xiaodongq.github.io/2024/07/10/leveldb-learn-first/)里做了基本介绍和简单demo功能测试，本篇具体看下对应的实现流程，为了达到性能效果做了哪些设计。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. UML类图

根据代码，画一下leveldb相关类图，如下：

![leveldb类图](/images/2024-07-21-leveldb-class-graph.svg)

## 3. 写操作流程

leveldb对外提供的写入接口有：（1）`Put`（2）`Delete`两种。

**这两种本质对应同一种操作，`Delete`操作同样会被转换成一个value为空的`Put`操作。**

如下可看到都是转换为`WriteBatch`批量写入，而后调用`DBImpl::Write`。

无论是`Put`/`Del`操作，还是批量操作，底层都会为这些操作创建一个batch实例作为一个数据库操作的最小执行单元，batch对应的操作是`原子性`的。

```cpp
// db/db_impl.cc

// Put调用流程
Status DBImpl::Put(const WriteOptions& o, const Slice& key, const Slice& val) {
  return DB::Put(o, key, val);
}

// Default implementations of convenience methods that subclasses of DB
// can call if they wish
// 基类DB的接口默认实现，子类也可直接使用，或者重写
Status DB::Put(const WriteOptions& opt, const Slice& key, const Slice& value) {
  WriteBatch batch;
  batch.Put(key, value);
  return Write(opt, &batch);
}

// Delete调用流程也是 DBImpl::Delete -> DB::Delete -> WriteBatch -> Write
Status DBImpl::Delete(const WriteOptions& options, const Slice& key) {
  return DB::Delete(options, key);
}

Status DB::Delete(const WriteOptions& opt, const Slice& key) {
  WriteBatch batch;
  batch.Delete(key);
  return Write(opt, &batch);
}
```

### 3.1. WriteBatch

`WriteBatch`类中的成员变量只有一个：`std::string rep_;`。需要从这个看似简单的`string`成员来理解leveldb的数据组织结构。

```cpp
// include/leveldb/write_batch.h
class LEVELDB_EXPORT WriteBatch {
  ...
private:
  friend class WriteBatchInternal;

  std::string rep_;
}
```

batch结构：  
![batch](https://leveldb-handbook.readthedocs.io/zh/latest/_images/batch.jpeg)

在batch中，每一条数据项都按照上图格式进行编码。每条数据项编码后的第一位是这条数据项的类型（更新还是删除），之后是数据项key的长度，数据项key的内容；若该数据项不是删除操作，则再加上value的长度，value的内容。

上面的`batch.Put(key, value)`对应的函数定义：

```cpp
// db/write_batch.cc
void WriteBatch::Put(const Slice& key, const Slice& value) {
  // 向WriteBatch实例计数加1，这里面的4字节计数会进行编码转换，计数位置从第8位开始（即跳过0-7位）
  WriteBatchInternal::SetCount(this, WriteBatchInternal::Count(this) + 1);
  // 串行新增一个字节(char)，表示操作类型。只有两种取值：kTypeDeletion = 0x0, kTypeValue = 0x1，此处为`kTypeValue`类型
  rep_.push_back(static_cast<char>(kTypeValue));

  // 向rep_追加（append）key的长度和数据
  PutLengthPrefixedSlice(&rep_, key);
  // 向rep_追加（append）value的长度和数据
  PutLengthPrefixedSlice(&rep_, value);
}
```

`Delete`只会追加key的长度和数据

```cpp
// db/write_batch.cc
void WriteBatch::Delete(const Slice& key) {
  // 向WriteBatch实例计数加1
  WriteBatchInternal::SetCount(this, WriteBatchInternal::Count(this) + 1);
  // 串行新增操作类型，此处为`kTypeDeletion`类型
  rep_.push_back(static_cast<char>(kTypeDeletion));
  // 只追加key的长度和数据
  PutLengthPrefixedSlice(&rep_, key);
}
```

### 3.2. DBImpl::Write

append追加对应的操作后，此处开始写入数据库。

里面很多内容值得好好学习一下：比如`std::deque`、leveldb自己封装的`MutexLock`和`port::CondVar`、单例类模板，学习记录直接在 [fork](https://github.com/xiaodongQ/leveldb) 的代码里添加注释。

先看下`DBImpl::Writer`这个类（`DBImpl::Write`函数里会用到）

```cpp
struct DBImpl::Writer {
  explicit Writer(port::Mutex* mu)
      : batch(nullptr), sync(false), done(false), cv(mu) {}

  Status status;
  WriteBatch* batch;
  bool sync;
  bool done;
  // 封装了 std::condition_variable，添加了线程安全
  port::CondVar cv;
};
```

`DBImpl::Write`函数代码：

```cpp
Status DBImpl::Write(const WriteOptions& options, WriteBatch* updates) {
  // 构造 Writer 实例
  Writer w(&mutex_);
  w.batch = updates;
  w.sync = options.sync;
  w.done = false;

  // RAII特性，构造时lock，析构时unlock
  MutexLock l(&mutex_);
  // 这里的writers_是 std::deque 双端队列
  writers_.push_back(&w);
  while (!w.done && &w != writers_.front()) {
    // 线程安全地等待条件变量，直到被唤醒
    w.cv.Wait();
  }
  // 到这里说明被唤醒了
  // 继续判断，若其他线程设置 Writer已结束 则返回
  if (w.done) {
    return w.status;
  }

  // May temporarily unlock and wait.
  // 声明为：Status DBImpl::MakeRoomForWrite(bool force)，若传入 WriteBatch* 为NULL则强制写，即不允许延迟写
  // 调用 MakeRoomForWrite 前必定已持锁，里面会断言判断
  Status status = MakeRoomForWrite(updates == nullptr);
  ...
}
```

#### CondVar


```cpp
// port/port_stdcxx.h

// Thinly wraps std::condition_variable.
// 封装了 std::condition_variable，确保了线程安全的等待与通知机制。
/*
  `std::condition_variable`是C++11标准库中提供的一种线程同步机制，用于多线程环境下的条件变量。它允许一个线程等待某个条件的变化，并在条件满足时进行通知。
  `std::condition_variable`与互斥锁（`std::mutex`）配合使用，以确保线程间安全地修改可共享的状态。
*/
class CondVar {
 public:
  explicit CondVar(Mutex* mu) : mu_(mu) { assert(mu != nullptr); }
  ~CondVar() = default;

  CondVar(const CondVar&) = delete;
  CondVar& operator=(const CondVar&) = delete;

  void Wait() {
    // std::adopt_lock 定义时即加锁
    std::unique_lock<std::mutex> lock(mu_->mu_, std::adopt_lock);
    // 等待条件变量，直到其他线程通过Signal或SignalAll唤醒它
    // 在等待过程中，lock会被临时释放，允许其他线程访问被保护的资源
    cv_.wait(lock);
    // 调用lock.release()是在wait返回后释放锁的一种不常见方式。
    // 实际上，在此上下文中，由于std::unique_lock会在其作用域结束时自动释放锁，这里的release调用是冗余的
    // 一般让 std::unique_lock自动管理锁的生命周期即可，无需手动调用release
    lock.release();
  }
  // 唤醒一个正在等待该条件变量的线程，哪个线程被唤醒是不确定的，由实现决定。
  void Signal() { cv_.notify_one(); }
  // 唤醒所有等待该条件变量的线程
  void SignalAll() { cv_.notify_all(); }

 private:
  std::condition_variable cv_;
  Mutex* const mu_;
};
```

## 4. 小结

读写过程代码学习。

## 5. 参考

1、[leveldb](https://github.com/google/leveldb)

2、[leveldb-handbook](https://leveldb-handbook.readthedocs.io/zh/latest/index.html)

3、[LevelDB数据结构解析](https://www.qtmuniao.com/categories/源码阅读/leveldb/)

4、GPT
