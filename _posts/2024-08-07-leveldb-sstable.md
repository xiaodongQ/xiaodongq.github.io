---
layout: post
title: leveldb学习笔记（五） -- sstable实现
categories: 存储
tags: 存储 leveldb
---

* content
{:toc}

leveldb学习笔记，本篇学习sstable实现。



## 1. 背景

继续学习梳理leveldb中具体的流程，本篇来看下sstable（`Sorted String Table`）实现。

跟着 [leveldb-handbook sstable](https://leveldb-handbook.readthedocs.io/zh/latest/sstable.html) 映证代码进行学习梳理。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. memtable 转换处理

### 2.1. DBImpl::MakeRoomForWrite：压缩任务判断入口

前面讲写流程时没展开`MakeRoomForWrite`看，对应的`memtable`写`sstable`的转换就在该接口中。先简单贴下写接口。

```cpp
// db/db_impl.cc
Status DBImpl::Write(const WriteOptions& options, WriteBatch* updates) {
    ...
    MutexLock l(&mutex_);
    // 要写入的数据，由Writer封装后先放到队列尾部
    // 这里的writers_是 std::deque 双端队列，存放Writer*
    writers_.push_back(&w);
    ...
    // 申请写入的空间，里面会检查是否需要转换memtable、是否需要压缩
    // 声明为：Status DBImpl::MakeRoomForWrite(bool force)，updates为nullptr时压缩处理
    // 调用 MakeRoomForWrite 前必定已持锁，里面会断言判断
    Status status = MakeRoomForWrite(updates == nullptr);
    uint64_t last_sequence = versions_->LastSequence();
    ...
    // 写journal、写memtable
```

```cpp
// db/db_impl.cc
Status DBImpl::MakeRoomForWrite(bool force) {
  // 要求外面肯定是持锁的，这里加了断言
  mutex_.AssertHeld();
  assert(!writers_.empty());
  bool allow_delay = !force;
  Status s;
  while (true) {
    if (!bg_error_.ok()) {
      // Yield previous error
      s = bg_error_;
      break;
    } else if (allow_delay && versions_->NumLevelFiles(0) >=
                                  config::kL0_SlowdownWritesTrigger) {
      // 若Level0的文件数超出限制（默认为8），则不延迟写
      mutex_.Unlock();
      // 等待过程不要持锁
      env_->SleepForMicroseconds(1000);
      // 由于当前在while(true)循环体中，下次就不会进入该语句块了
      allow_delay = false;  // Do not delay a single write more than once
      mutex_.Lock();
    } else if (!force &&
               (mem_->ApproximateMemoryUsage() <= options_.write_buffer_size)) {
      // 若memtable中内存还够用，则不需要申请新的memtable
      // There is room in current memtable
      break;
    } else if (imm_ != nullptr) {
      // We have filled up the current memtable, but the previous
      // one is still being compacted, so we wait.
      // 若immutable memtable还没完成压缩，则等待
      Log(options_.info_log, "Current memtable full; waiting...\n");
      background_work_finished_signal_.Wait();
    } else if (versions_->NumLevelFiles(0) >= config::kL0_StopWritesTrigger) {
      // There are too many level-0 files.
      // level0层的文件数超出限制（默认12个），等待
      Log(options_.info_log, "Too many L0 files; waiting...\n");
      background_work_finished_signal_.Wait();
    } else {
      // Attempt to switch to a new memtable and trigger compaction of old
      // 到这里才需要申请新的空间：memtable（原来的memtable移动到immutable memtable）
      assert(versions_->PrevLogNumber() == 0);
      uint64_t new_log_number = versions_->NewFileNumber();
      WritableFile* lfile = nullptr;
      s = env_->NewWritableFile(LogFileName(dbname_, new_log_number), &lfile);
      if (!s.ok()) {
        // Avoid chewing through file number space in a tight loop.
        versions_->ReuseFileNumber(new_log_number);
        break;
      }

      delete log_;
      // 关闭原来的log文件
      s = logfile_->Close();
      if (!s.ok()) {
        RecordBackgroundError(s);
      }
      delete logfile_;

      logfile_ = lfile;
      logfile_number_ = new_log_number;
      log_ = new log::Writer(lfile);
      // 原来的memtable移动到immutable memtable
      imm_ = mem_;
      has_imm_.store(true, std::memory_order_release);
      // 创建新的memtable
      mem_ = new MemTable(internal_comparator_);
      mem_->Ref();
      force = false;  // Do not force another compaction if have room
      // 检查（immutable memtable和其他level）是否需要压缩
      MaybeScheduleCompaction();
    }
  }
  return s;
}
```

继续看`MaybeScheduleCompaction`

### 2.2. MaybeScheduleCompaction：压缩任务新增

```cpp
// db/db_impl.cc
void DBImpl::MaybeScheduleCompaction() {
  mutex_.AssertHeld();
  if (background_compaction_scheduled_) {
    // 已经触发后台压缩调度，不需要再新增任务
    // Already scheduled
  } else if (shutting_down_.load(std::memory_order_acquire)) {
    // DB is being deleted; no more background compactions
  } else if (!bg_error_.ok()) {
    // Already got an error; no more changes
  } else if (imm_ == nullptr && manual_compaction_ == nullptr &&
             !versions_->NeedsCompaction()) {
    // No work to be done
  } else {
    background_compaction_scheduled_ = true;
    // 这里面会生产一个任务，并通知消费者进行线程处理
    // 具体任务处理在 DBImpl::BGWork 回调函数里，负责后台压缩 immutable memtable
    env_->Schedule(&DBImpl::BGWork, this);
  }
}
```

上面若需要压缩，则`env_->Schedule(&DBImpl::BGWork, this);`投递任务，其回调处理为`DBImpl::BGWork`。

`env_->Schedule`里面基于mutex和条件变量实现了一个生产-消费者模型，leveldb自己包装了一层`std::mutex`和`std::condition_variable`。

### 2.3. DBImpl::BGWork：压缩任务回调处理

```cpp
// db/db_impl.cc
void DBImpl::BGWork(void* db) {
  reinterpret_cast<DBImpl*>(db)->BackgroundCall();
}
```

```cpp
// db/db_impl.cc
// 负责后台压缩 immutable memtable
void DBImpl::BackgroundCall() {
  MutexLock l(&mutex_);
  assert(background_compaction_scheduled_);
  if (shutting_down_.load(std::memory_order_acquire)) {
    // No more background work when shutting down.
  } else if (!bg_error_.ok()) {
    // No more background work after a background error.
  } else {
    // 检查并进行后台压缩
    BackgroundCompaction();
  }

  // 压缩完，重置任务调度标志
  background_compaction_scheduled_ = false;

  // Previous compaction may have produced too many files in a level,
  // so reschedule another compaction if needed.
  // 再检查一次是否要压缩
  MaybeScheduleCompaction();
  background_work_finished_signal_.SignalAll();
}
```

```cpp
// db/db_impl.cc
void DBImpl::BackgroundCompaction() {
  mutex_.AssertHeld();

  // 存在immutable memtable则压缩并退出，immutable memtable压缩为level0层的sstable
  if (imm_ != nullptr) {
    CompactMemTable();
    return;
  }
  ...
}

```

```cpp
// db/db_impl.cc
void DBImpl::CompactMemTable() {
  mutex_.AssertHeld();
  assert(imm_ != nullptr);

  // Save the contents of the memtable as a new Table
  VersionEdit edit;
  // 当前version（每次压缩完都会创建一个新的version）
  Version* base = versions_->current();
  base->Ref();
  // immutable memtable 写入到 level0
  Status s = WriteLevel0Table(imm_, &edit, base);
  base->Unref();
  ...
}
```

### 2.4. DBImpl::WriteLevel0Table：写sstable具体逻辑

```cpp
// db/db_impl.cc
Status DBImpl::WriteLevel0Table(MemTable* mem, VersionEdit* edit,
                                Version* base) {
  mutex_.AssertHeld();
  const uint64_t start_micros = env_->NowMicros();
  // 文件元数据（定义在db/version_edit.h中，VersionEdit类中会有多个FileMetaData）
  FileMetaData meta;
  // version文件计数+1，该数值也用于下面新增文件的文件名： db名称/编号.ldb
  meta.number = versions_->NewFileNumber();
  pending_outputs_.insert(meta.number);
  // 获取传入 memtable(实际immutable memtable) 的迭代器
  Iterator* iter = mem->NewIterator();
  Log(options_.info_log, "Level-0 table #%llu: started",
      (unsigned long long)meta.number);

  Status s;
  {
    mutex_.Unlock();
    // 这里通过 iter 写 sstable 文件
    // 结束写入时：里面会写filter block、metaindex block、Write index block、Write footer
    // 对应： ![写入结构示意图](https://leveldb-handbook.readthedocs.io/zh/latest/_images/sstable_logic.jpeg)
    // meta作为指针传入，里面会做一些元数据设置
    s = BuildTable(dbname_, env_, options_, table_cache_, iter, &meta);
    mutex_.Lock();
  }

  Log(options_.info_log, "Level-0 table #%llu: %lld bytes %s",
      (unsigned long long)meta.number, (unsigned long long)meta.file_size,
      s.ToString().c_str());
  delete iter;
  pending_outputs_.erase(meta.number);

  // Note that if file_size is zero, the file has been deleted and
  // should not be added to the manifest.
  int level = 0;
  if (s.ok() && meta.file_size > 0) {
    const Slice min_user_key = meta.smallest.user_key();
    const Slice max_user_key = meta.largest.user_key();
    if (base != nullptr) {
      level = base->PickLevelForMemTableOutput(min_user_key, max_user_key);
    }
    edit->AddFile(level, meta.number, meta.file_size, meta.smallest,
                  meta.largest);
  }

  CompactionStats stats;
  stats.micros = env_->NowMicros() - start_micros;
  stats.bytes_written = meta.file_size;
  stats_[level].Add(stats);
  return s;
}
```

上面`BuildTable`中负责根据迭代器依次写入key-value数据，最后写入filter block、metaindex block、Write index block、Write footer等信息。

对应写入结构示意图：

![写入结构示意图](https://leveldb-handbook.readthedocs.io/zh/latest/_images/sstable_logic.jpeg)

## 3. gtest单元测试

## 4. 小结

学习梳理sstable实现逻辑。

## 5. 参考

1、[leveldb](https://github.com/google/leveldb)

2、[leveldb-handbook sstable](https://leveldb-handbook.readthedocs.io/zh/latest/sstable.html)
