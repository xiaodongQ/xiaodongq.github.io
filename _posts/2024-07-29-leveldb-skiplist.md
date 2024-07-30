---
layout: post
title: leveldb学习笔记（三） -- 日志和memtable实现
categories: 存储
tags: 存储 leveldb
---

* content
{:toc}

leveldb学习笔记，本篇学习日志结构和memtable的实现，学习其中的跳表用法。



## 1. 背景

前面跟踪学习了读写实现的基本流程，此篇开始学习梳理其中具体的流程实现。本篇先看日志和memtable（内存数据库）对应的实现细节，尤其是其中的跳表结构。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 日志

[前面](https://xiaodongq.github.io/2024/07/20/leveldb-io-implement/)看过了写流程，这里再放一下：

![写流程](/images/2024-07-25-level-write-process.png)

如上，为了避免断电、程序崩溃等异常导致丢数据，写memtable之前会先写日志。

在leveldb中，有两个memory db，以及对应的两份日志文件。两个memory db即下面定义中的`mem_`和`imm_`；日志文件为`log_`

### 日志文件初始化

```cpp
// db/db_impl.h
class DBImpl : public DB {
    ...
    // 内存态的表
    MemTable* mem_;
    // 内存态的表，不可修改
    MemTable* imm_ GUARDED_BY(mutex_);  // Memtable being compacted
    std::atomic<bool> has_imm_;         // So bg thread can detect non-null imm_
    // 此处表示日志文件，具体内容在实现类中（linux下为PosixWritableFile）
    WritableFile* logfile_;
    uint64_t logfile_number_ GUARDED_BY(mutex_);
    // 日志文件对于的写操作对象，该对象操作都体现在 logfile_ 对应文件上
    log::Writer* log_;
    ...
};
```

上述`log_`和`logfile_`成员是在leveldb数据库`Open`时初始化的：

```cpp
// db/db_impl.cc
Status DB::Open(const Options& options, const std::string& dbname, DB** dbptr) {
    // Open的时候会初始化DBImpl相关内容
    DBImpl* impl = new DBImpl(options, dbname);
    ...
    Status s = impl->Recover(&edit, &save_manifest);
    if (s.ok() && impl->mem_ == nullptr) {
        uint64_t new_log_number = impl->versions_->NewFileNumber();
        WritableFile* lfile;
        // linux下env对应posix文件io接口，此处新建一个文件
        s = options.env->NewWritableFile(LogFileName(dbname, new_log_number), &lfile);
        if (s.ok()) {
            edit.SetLogNumber(new_log_number);
            // 初始化日志文件 logfile_
            impl->logfile_ = lfile;
            impl->logfile_number_ = new_log_number;
            // 初始化日志文件对于的写操作对象log_，该对象操作都体现在 logfile_ 对应文件上
            impl->log_ = new log::Writer(lfile);
            // mem_ 为空则new进行实例化
            impl->mem_ = new MemTable(impl->internal_comparator_);
            impl->mem_->Ref();
        }
    }
    ...
}
```

### 写流程中的日志操作

主要写流程操作如下：

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
    // 待写入数据
    Writer* last_writer = &w;
    if (status.ok() && updates != nullptr) {
        // 合并写操作，要合并的对象是 writers_ 对应的 Writer 双端队列
        WriteBatch* write_batch = BuildBatchGroup(&last_writer);
        ...
        {
            mutex_.Unlock();
            // 合并后的记录，写WAL预写日志
            // Contents 用于获取WriteBatch里面的内容，多条记录按batch格式组织
            status = log_->AddRecord(WriteBatchInternal::Contents(write_batch));
            ...
            if (status.ok()) {
                // 写memtable，write_batch写到传入的 mem_ 里
                status = WriteBatchInternal::InsertInto(write_batch, mem_);
            }
            mutex_.Lock();
            ...
        }
        ...
    }
    ...
}
```

其中涉及写日志的逻辑：

```cpp
// db/log_writer.cc
Status Writer::AddRecord(const Slice& slice) {
    const char* ptr = slice.data();
    size_t left = slice.size();
    ...
    // 循环写 dest_（定义为`WritableFile* dest_;`），并::write写物理盘
    do {
        // 小数据写buffer，大数据直接::write写盘
        dest_->Append(Slice("\x00\x00\x00\x00\x00\x00", leftover));
        ...
        // buffer写物理盘，这里只是调::write，具体操作系统的page cache等不关注
        s = EmitPhysicalRecord(type, ptr, fragment_length);
        ...
    } while(s.ok() && left > 0);
}
```

涉及日志转换和memtable/immutable memtable转换操作，逻辑在上面的`MakeRoomForWrite`中，放到memtable小节说明。

### 日志结构

为便于理解，我们把上面的`AddRecord`全部展开。

```cpp
Status Writer::AddRecord(const Slice& slice) {
  const char* ptr = slice.data();
  size_t left = slice.size();

  // Fragment the record if necessary and emit it.  Note that if slice
  // is empty, we still want to iterate once to emit a single
  // zero-length record
  Status s;
  bool begin = true;
  // 循环写 dest_（定义为`WritableFile* dest_;`），并::write写物理盘
  do {
    // kBlockSize默认为32KB
    const int leftover = kBlockSize - block_offset_;
    assert(leftover >= 0);
    if (leftover < kHeaderSize) {
      // Switch to a new block
      if (leftover > 0) {
        // Fill the trailer (literal below relies on kHeaderSize being 7)
        static_assert(kHeaderSize == 7, "");
        // 小数据写buffer，大数据直接::write写盘
        dest_->Append(Slice("\x00\x00\x00\x00\x00\x00", leftover));
      }
      block_offset_ = 0;
    }

    // Invariant: we never leave < kHeaderSize bytes in a block.
    assert(kBlockSize - block_offset_ - kHeaderSize >= 0);

    const size_t avail = kBlockSize - block_offset_ - kHeaderSize;
    const size_t fragment_length = (left < avail) ? left : avail;

    RecordType type;
    const bool end = (left == fragment_length);
    if (begin && end) {
      type = kFullType;
    } else if (begin) {
      type = kFirstType;
    } else if (end) {
      type = kLastType;
    } else {
      type = kMiddleType;
    }

    // buffer写物理盘，这里只是调::write，具体操作系统的page cache等不关注
    s = EmitPhysicalRecord(type, ptr, fragment_length);
    ptr += fragment_length;
    left -= fragment_length;
    begin = false;
  } while (s.ok() && left > 0);
  return s;
}
```



## 3. memtable

看下内存数据库memtable的定义，可看到MemTable中的实现为：`SkipList<const char*, KeyComparator>`

```cpp
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

### 写流程中的memtable转换

上述梳理日志流程的小节中，提到了`MakeRoomForWrite`，此处进行分析。


## 4. 小结

学习日志结构和memtable的实现细节。

## 5. 参考

1、[leveldb](https://github.com/google/leveldb)

2、[leveldb-handbook](https://leveldb-handbook.readthedocs.io/zh/latest/index.html)

3、[漫谈 LevelDB 数据结构（一）：跳表（Skip List）](https://www.qtmuniao.com/2020/07/03/leveldb-data-structures-skip-list/)

4、GPT
