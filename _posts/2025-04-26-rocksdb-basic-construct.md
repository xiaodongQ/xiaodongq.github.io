---
title: RocksDB学习笔记（二） -- MemTable、SSTfile、LogFile等基本结构代码走读
description: 梳理走读MemTable、SSTfile、LogFile等的代码和相关流程。
categories: [存储和数据库, RocksDB]
tags: [存储, RocksDB]
---


## 1. 引言

本篇快速走读一下RocksDB中的几个基本结构：MemTable、SSTFile、LogFile 对应的代码。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 基本结构说明

### 2.1. MemTable

> 介绍可见：[MemTable](https://github.com/facebook/rocksdb/wiki/MemTable)
{: .prompt-info }

`MemTable`同时提供`读`和`写`服务。

1、**读取数据**时会先从MemTable读取，因为内存中的数据最新，没查找到才去查询`SST`文件；

2、**写入数据**时都会先写入到MemTable，当MemTable满时就会变成immutable状态，后台线程会刷写（`flush`）其内容到`SST`文件（`SSTable`文件）

* MemTable会根据配置的大小和数量来决定什么时候`flush`到磁盘上。一旦 MemTable 达到配置的大小，旧的 MemTable 和 WAL 都会变成`不可变`的状态（即immutable MemTable），然后会重新分配新的 MemTable 和 WAL 用来写入数据，旧的 MemTable 则会被 flush 到`SSTable`文件中，即`L0`层的数据。
* 任何时间点，都**只有一个活跃的MemTable** 和 **0个或多个immutable MemTable**

RocksDB中的`MemTable`基于**跳表**实现，可见之前梳理LevelDB时的说明：[跳表](https://xiaodongq.github.io/2024/08/02/leveldb-memtable-skiplist/#2-%E8%B7%B3%E8%A1%A8)。

`MemTable`类定义：

```cpp
// db/memtable.h
class MemTable {
 public:
  // key比较器
  struct KeyComparator : public MemTableRep::KeyComparator {
    ...
  };

  // MemTables are reference counted.  The initial reference count
  // is zero and the caller must call Ref() at least once.
  // first key is inserted into the memtable.
  // MemTable 通过引用计数，需要调用 Ref()
  // 构造函数，并禁用拷贝构造和赋值构造。
  explicit MemTable(const InternalKeyComparator& comparator,
                    const ImmutableCFOptions& ioptions,
                    const MutableCFOptions& mutable_cf_options,
                    WriteBufferManager* write_buffer_manager,
                    SequenceNumber earliest_seq, uint32_t column_family_id);
  // No copying allowed
  MemTable(const MemTable&) = delete;
  MemTable& operator=(const MemTable&) = delete;

  // Do not delete this MemTable unless Unref() indicates it not in use.
  ~MemTable();

  // Increase reference count.
  // REQUIRES: external synchronization to prevent simultaneous
  // operations on the same MemTable.
  void Ref() { ++refs_; }

  // Drop reference count.
  // If the refcount goes to zero return this memtable, otherwise return null.
  // REQUIRES: external synchronization to prevent simultaneous
  // operations on the same MemTable.
  MemTable* Unref() {
    --refs_;
    assert(refs_ >= 0);
    if (refs_ <= 0) {
      return this;
    }
    return nullptr;
  }
  ...

  // 增加记录
  bool Add(SequenceNumber seq, ValueType type, const Slice& key,
           const Slice& value, bool allow_concurrent = false,
           MemTablePostProcessInfo* post_process_info = nullptr,
           void** hint = nullptr);
  // 查找记录
  bool Get(const LookupKey& key, std::string* value, Status* s,
           MergeContext* merge_context,
           SequenceNumber* max_covering_tombstone_seq, SequenceNumber* seq,
           const ReadOptions& read_opts, ReadCallback* callback = nullptr,
           bool* is_blob_index = nullptr, bool do_merge = true) {
    return Get(key, value, /*timestamp=*/nullptr, s, merge_context,
               max_covering_tombstone_seq, seq, read_opts, callback,
               is_blob_index, do_merge);
  }
  ...

 private:
  ...
  KeyComparator comparator_;
  const ImmutableMemTableOptions moptions_;
  int refs_;
  const size_t kArenaBlockSize;
  AllocTracker mem_tracker_;
  ConcurrentArena arena_;
  std::unique_ptr<MemTableRep> table_;
  std::unique_ptr<MemTableRep> range_del_table_;
  std::atomic_bool is_range_del_table_empty_;
  // Total data size of all data inserted
  std::atomic<uint64_t> data_size_;
  std::atomic<uint64_t> num_entries_;
  std::atomic<uint64_t> num_deletes_;
  ...
};
```

如上所述，新创建的MemTable需要至少调用一次`Ref()`增加引用计数，可见`SwitchMemtable`切换MemTable流程：

```cpp
// db/db_impl/db_impl_write.cc
Status DBImpl::SwitchMemtable(ColumnFamilyData* cfd, WriteContext* context) {
  // 外部持锁
  mutex_.AssertHeld();
  WriteThread::Writer nonmem_w;
  std::unique_ptr<WritableFile> lfile;
  log::Writer* new_log = nullptr;
  MemTable* new_mem = nullptr;
  IOStatus io_s;
  ...
  // 持久化恢复状态到
  Status s = WriteRecoverableState();
  ...
  // 之前有WAL则创建新的WAL日志
  bool creating_new_log = !log_empty_;
  ...
  // 创建WAL前先解锁
  mutex_.Unlock();
  if (creating_new_log) {
    // 创建新的WAL日志
    io_s = CreateWAL(new_log_number, recycle_log_number, preallocate_block_size,
                     &new_log);
    if (s.ok()) {
      s = io_s;
    }
  }
  if (s.ok()) {
    SequenceNumber seq = versions_->LastSequence();
    // 创建新的MemTable
    new_mem = cfd->ConstructNewMemtable(mutable_cf_options, seq);
    context->superversion_context.NewSuperVersion();
  }
  ROCKS_LOG_INFO(immutable_db_options_.info_log,
                 "[%s] New memtable created with log file: #%" PRIu64
                 ". Immutable memtables: %d.\n",
                 cfd->GetName().c_str(), new_log_number, num_imm_unflushed);
  // 上述创建完新的WAL和MemTable，加锁继续后续处理
  mutex_.Lock();
  ...
  // 增加MemTable的引用计数
  new_mem->Ref();
  cfd->SetMemtable(new_mem);
  ...
}
```

调用到`SwitchMemtable`的流程：

```sh
[MacOS-xd@qxd ➜ rocksdb_v6.15.5 git:(rocksdb-v6.15.5) ✗ ]$ calltree.pl 'SwitchMemtable' '' 1 1 3
  
  SwitchMemtable
  ├── DBImpl::FlushMemTable	[vim db/db_impl/db_impl_compaction_flush.cc +1697]
  │   ├── DBImpl::ResumeImpl	[vim db/db_impl/db_impl.cc +306]
  │   ├── DBImpl::CancelAllBackgroundWork	[vim db/db_impl/db_impl.cc +445]
  │   ├── DBImpl::IngestExternalFiles	[vim db/db_impl/db_impl.cc +4323]
  │   ├── DBImpl::CompactRange	[vim db/db_impl/db_impl_compaction_flush.cc +782]
  │   ├── DBImpl::Flush	[vim db/db_impl/db_impl_compaction_flush.cc +1478]
  │   ├── DBImpl::TEST_FlushMemTable	[vim db/db_impl/db_impl_debug.cc +126]
  │   ├── DBImpl::TEST_FlushMemTable	[vim db/db_impl/db_impl_debug.cc +141]
  │   └── DBImpl::GetLiveFiles	[vim db/db_filesnapshot.cc +26]
  ├── DBImpl::AtomicFlushMemTables	[vim db/db_impl/db_impl_compaction_flush.cc +1819]
  │   ├── DBImpl::ResumeImpl	[vim db/db_impl/db_impl.cc +306]
  │   ├── DBImpl::CancelAllBackgroundWork	[vim db/db_impl/db_impl.cc +445]
  │   ├── DBImpl::IngestExternalFiles	[vim db/db_impl/db_impl.cc +4323]
  │   ├── DBImpl::CompactRange	[vim db/db_impl/db_impl_compaction_flush.cc +782]
  │   ├── DBImpl::Flush	[vim db/db_impl/db_impl_compaction_flush.cc +1478]
  │   ├── DBImpl::Flush	[vim db/db_impl/db_impl_compaction_flush.cc +1497]
  │   ├── DBImpl::TEST_AtomicFlushMemTables	[vim db/db_impl/db_impl_debug.cc +146]
  │   └── DBImpl::GetLiveFiles	[vim db/db_filesnapshot.cc +26]
  ├── DBImpl::SwitchWAL	[vim db/db_impl/db_impl_write.cc +1253]
  │   ├── DBImpl::PreprocessWrite	[vim db/db_impl/db_impl_write.cc +903]
  │   └── DBImpl::TEST_SwitchWAL	[vim db/db_impl/db_impl_debug.cc +25]
  ├── DBImpl::HandleWriteBufferFull	[vim db/db_impl/db_impl_write.cc +1348]
  │   └── DBImpl::PreprocessWrite	[vim db/db_impl/db_impl_write.cc +903]
  ├── DBImpl::ScheduleFlushes	[vim db/db_impl/db_impl_write.cc +1605]
  │   └── DBImpl::PreprocessWrite	[vim db/db_impl/db_impl_write.cc +903]
  └── DBImpl::TEST_SwitchMemtable	[vim db/db_impl/db_impl_debug.cc +105]
```

### 2.2. SST文件

> 介绍可见：[Rocksdb BlockBasedTable Format](https://github.com/facebook/rocksdb/wiki/Rocksdb-BlockBasedTable-Format)
{: .prompt-info }

RocksDB中的SST结构：

```sh
<beginning_of_file>
[data block 1]
[data block 2]
...
[data block N]
[meta block 1: filter block]                  (see section: "filter" Meta Block)
[meta block 2: index block]
[meta block 3: compression dictionary block]  (see section: "compression dictionary" Meta Block)
[meta block 4: range deletion block]          (see section: "range deletion" Meta Block)
[meta block 5: stats block]                   (see section: "properties" Meta Block)
...
[meta block K: future extended block]  (we may add more meta blocks in the future)
[metaindex block]
[Footer]                               (fixed size; starts at file_size - sizeof(Footer))
<end_of_file>
```

SST的`Compaction`合并操作，由`DBImpl::BackgroundCompaction`负责处理，看下调用栈，具体逻辑本篇暂不展开。

如下所示，调用链为：`DBImpl::BGWorkCompaction`或`DBImpl::BGWorkBottomCompaction` -> `BackgroundCallCompaction` -> `BackgroundCompaction`

```sh
[MacOS-xd@qxd ➜ rocksdb_v6.15.5 git:(rocksdb-v6.15.5) ✗ ]$ calltree.pl 'BackgroundCompaction' '' 1 1 4
  
  BackgroundCompaction
  └── DBImpl::BackgroundCallCompaction	[vim db/db_impl/db_impl_compaction_flush.cc +2503]
      ├── DBImpl::BGWorkCompaction	[vim db/db_impl/db_impl_compaction_flush.cc +2295]
      └── DBImpl::BGWorkBottomCompaction	[vim db/db_impl/db_impl_compaction_flush.cc +2307]
```

这里看下`BGWorkCompaction`的调用时机（其实`BGWorkBottomCompaction`也是在`BackgroundCompaction`中设置的回调函数），包含<mark>两个场景</mark>：

* 1、`MaybeScheduleFlushOrCompaction` 判断是否需要compaction
* 2、`RunManualCompaction` 手动触发

```cpp
// db/db_impl/db_impl_compaction_flush.cc
// 判断是否需compaction
void DBImpl::MaybeScheduleFlushOrCompaction() {
  ...
  env_->Schedule(&DBImpl::BGWorkCompaction, ca, Env::Priority::LOW, this,
                 &DBImpl::UnscheduleCompactionCallback);
  ...
}

// 手动触发compaction
Status DBImpl::RunManualCompaction( xxx ) {
  ...
  env_->Schedule(&DBImpl::BGWorkCompaction, ca, thread_pool_pri, this,
                 &DBImpl::UnscheduleCompactionCallback);
  ...
}
```

很多操作都会调用到`MaybeScheduleFlushOrCompaction`：

```sh
[MacOS-xd@qxd ➜ rocksdb_v6.15.5 git:(rocksdb-v6.15.5) ✗ ]$ calltree.pl 'MaybeScheduleFlushOrCompaction' '' 1 1 2
  
  MaybeScheduleFlushOrCompaction
  ├── DBImpl::ResumeImpl	[vim db/db_impl/db_impl.cc +306]
  ├── DBImpl::ReleaseSnapshot	[vim db/db_impl/db_impl.cc +3004]
  ├── DBImpl::CompactRange	[vim db/db_impl/db_impl_compaction_flush.cc +782]
  ├── DBImpl::CompactFilesImpl	[vim db/db_impl/db_impl_compaction_flush.cc +1058]
  ├── DBImpl::ContinueBackgroundWork	[vim db/db_impl/db_impl_compaction_flush.cc +1268]
  ├── DBImpl::FlushMemTable	[vim db/db_impl/db_impl_compaction_flush.cc +1697]
  ├── DBImpl::AtomicFlushMemTables	[vim db/db_impl/db_impl_compaction_flush.cc +1819]
  ├── DBImpl::BackgroundCallFlush	[vim db/db_impl/db_impl_compaction_flush.cc +2423]
  ├── DBImpl::BackgroundCallCompaction	[vim db/db_impl/db_impl_compaction_flush.cc +2503]
  ├── DBImpl::BackgroundCompaction	[vim db/db_impl/db_impl_compaction_flush.cc +2619]
  ├── DBImpl::InstallSuperVersionAndScheduleWork	[vim db/db_impl/db_impl_compaction_flush.cc +3255]
  ├── DBImpl::SwitchWAL	[vim db/db_impl/db_impl_write.cc +1253]
  ├── DBImpl::HandleWriteBufferFull	[vim db/db_impl/db_impl_write.cc +1348]
  ├── DBImpl::ScheduleFlushes	[vim db/db_impl/db_impl_write.cc +1605]
  └── DBImpl::SuggestCompactRange	[vim db/db_impl/db_impl_experimental.cc +23]
```

手动触发compaction可由用户手动触发，或者一些工具中触发：

![manual-compaction](/images/2025-04-30-manual-compaction.png)

### 2.3. 日志（Journal）

> 介绍可见：[Journal](https://github.com/facebook/rocksdb/wiki/Journal)，其中包含 [WAL](https://github.com/facebook/rocksdb/wiki/Write-Ahead-Log-%28WAL%29)、[MANIFEST](https://github.com/facebook/rocksdb/wiki/MANIFEST)、[Track WAL in MANIFEST](https://github.com/facebook/rocksdb/wiki/Track-WAL-in-MANIFEST)。
{: .prompt-info }

**日志（`Journals`或`Logs`）** 是RocksDB完整性和数据恢复的关键，用来记录数据系统的历史状态。

RocksDB中包含两种类型的日志：
* 1、`Write Ahead Log (WAL)`：记录内存中数据的状态更新
* 2、`MANIFEST`：记录硬盘上的状态更新

## 3. 代码流程

写入数据的流程中会涉及上述几个基本结构，通过走读`Put`的流程来看对应的实现。

### 3.1. 类图

RocksDB读写操作的头文件入口为：`include/rocksdb/db.h`，其中定义了`class DB`抽象类。实现类为`class DBImpl`，位于`db/db_impl/db_impl.h`中，实际实现则根据不同类型的功能，可能分布在不同的文件中，文件拓扑如下：

```sh
[MacOS-xd@qxd ➜ cpp_path ]$ tree --matchdirs rocksdb_v6.15.5/db/db_impl
rocksdb_v6.15.5/db/db_impl
├── db_impl.cc
├── db_impl.h
├── db_impl_compaction_flush.cc
├── db_impl_debug.cc
├── db_impl_experimental.cc
├── db_impl_files.cc
├── db_impl_open.cc
├── db_impl_readonly.cc
├── db_impl_readonly.h
├── db_impl_secondary.cc
├── db_impl_secondary.h
├── db_impl_write.cc
└── db_secondary_test.cc
```

示意类图如下：

![rocksdb-class-diagram](/images/2025-04-29-rocksdb-class-diagram.png)

### 3.2. Put流程

函数声明：

```cpp
// db/db_impl/db_impl.h
class DBImpl : public DB {
  // 此处using用于将基类中所有Put的重载函数（基类里有多个Put函数）引入派生类DBImpl，避免在派生类中被隐藏。
  // 使用派生类时也可以使用其他基类里的Put重载函数。
  using DB::Put;
  virtual Status Put(const WriteOptions& options,
                     ColumnFamilyHandle* column_family, const Slice& key,
                     const Slice& value) override;
};
```

写入时若不特别指定（比如第一篇中的demo），则`WriteOptions`为默认参数，如下：

```cpp
  WriteOptions()
      : sync(false),
        disableWAL(false),
        ignore_missing_column_families(false),
        no_slowdown(false),
        low_pri(false),
        memtable_insert_hint_per_batch(false),
        timestamp(nullptr) {}
```

`DBImpl::Put`实现如下：调用栈`DBImpl::Put` -> `DB::Put` -> `DBImpl::Write`（基类中的`Write`是纯虚函数）

```cpp
// db/db_impl/db_impl_write.cc
Status DBImpl::Put(const WriteOptions& o, ColumnFamilyHandle* column_family,
                   const Slice& key, const Slice& val) {
  // 调用基类中的 DB::Put 实现
  return DB::Put(o, column_family, key, val);
}

// 具体key-value写实现，最后调用`Write`函数，其中支持批量写。
Status DB::Put(const WriteOptions& opt, ColumnFamilyHandle* column_family,
               const Slice& key, const Slice& value) {
  // 未设置时间戳选项
  if (nullptr == opt.timestamp) {
    // 预分配WriteBatch大小，另外需要的24字节包含：8字节头 + 4字节数量 + 1字节类型 + 11字节额外数据）
    WriteBatch batch(key.size() + value.size() + 24);
    Status s = batch.Put(column_family, key, value);
    if (!s.ok()) {
      return s;
    }
    // 基类中的Write是纯虚函数，此处调用的是实现类函数 DBImpl::Write
    return Write(opt, &batch);
  }
  ...
  WriteBatch batch(key.size() + ts_sz + value.size() + 24, /*max_bytes=*/0,
                   ts_sz);
  Status s = batch.Put(column_family, key, value);
  ...
  // 基类中的Write是纯虚函数，此处调用的是实现类函数 DBImpl::Write
  return Write(opt, &batch);
}

// DBImpl::Write函数：
Status DBImpl::Write(const WriteOptions& write_options, WriteBatch* my_batch) {
  return WriteImpl(write_options, my_batch, nullptr, nullptr);
}
```

用calltree.pl跟了下`DBImpl::WriteImpl`的实现调用栈，并不大直观，增大展开层数内容比较多（可见3层展开：[WriteImpl调用栈](https://github.com/xiaodongQ/prog-playground/blob/main/storage/rocksdb/WriteImpl_calltree_depth3.txt)）：

![WriteImpl-calltree](/images/2025-04-29-calltree.png)

不过跟踪某部分子流程还是比较方便的，比如`DBImpl::WriteImpl`中写WAL的分支：`WriteToWAL`，如下所示

![calltree-writewal](/images/2025-04-29-calltree-writewal.png)

还是看代码跟踪流程：

```cpp
// db/db_impl/db_impl_write.cc
// 暂时关注前2个参数，其他参数都是默认零值（其中bool都是false）
Status DBImpl::WriteImpl(const WriteOptions& write_options,
                         WriteBatch* my_batch, WriteCallback* callback,
                         uint64_t* log_used, uint64_t log_ref,
                         bool disable_memtable, uint64_t* seq_used,
                         size_t batch_cnt,
                         PreReleaseCallback* pre_release_callback) {
  assert(!seq_per_batch_ || batch_cnt != 0);
  if (my_batch == nullptr) {
    return Status::Corruption("Batch is nullptr!");
  }
  // 部分选项参数校验
  if (write_options.sync && write_options.disableWAL) {
    return Status::InvalidArgument("Sync writes has to enable WAL.");
  }
  ...
  // immutable_db_options_是const成员变量，在 DBImpl 构造时就通过DBOptions初始化了
  // unordered_write 等默认是flase，暂时略过。可见options.h中的`struct DBOptions`
  if (immutable_db_options_.unordered_write) {
    ...
  }
  ...
  // 定义一个 PerfStepTimer 计时器并记录当前开始时间，最后返回ns耗时
  PERF_TIMER_GUARD(write_pre_and_post_process_time);
  // 定义负责写的处理类实例，此时w.state状态机状态：STATE_INIT
  WriteThread::Writer w(write_options, my_batch, callback, log_ref,
                        disable_memtable, batch_cnt, pre_release_callback);
  ...
  // RAII机制来统计耗时情况，析构时处理statistics中的指标，里面还提供了直方图
  StopWatch write_sw(env_, immutable_db_options_.statistics.get(), DB_WRITE);

  // 待写处理类实例加入到写线程
  write_thread_.JoinBatchGroup(&w);
  // Writer实例的状态，构造时是 `STATE_INIT`，可以先略过这些 w.state 语句块，以免时间线混乱，此时状态还是初始状态
  if (w.state == WriteThread::STATE_PARALLEL_MEMTABLE_WRITER) {
    ...
  }
  ...
  // 上面第一次JoinBatchGroup里，会设置 `STATE_GROUP_LEADER`
  assert(w.state == WriteThread::STATE_GROUP_LEADER);
  ...
  if (!two_write_queues_ || !disable_memtable) {
    // 写前预处理，是否需要切WAL、切MemTable、flush数据到磁盘
    status = PreprocessWrite(write_options, &need_log_sync, &write_context);
    ...
  }
  ...
  // 获取WAL写日志实例
  log::Writer* log_writer = logs_.back().writer;
  ...
  if (status.ok()) {
    auto stats = default_cf_internal_stats_;
    stats->AddDBStats(InternalStats::kIntStatsNumKeysWritten, total_count,
    if (!two_write_queues_) {
      if (status.ok() && !write_options.disableWAL) {
        PERF_TIMER_GUARD(write_wal_time);
        // 写WAL
        io_s = WriteToWAL(write_group, log_writer, log_used, need_log_sync,
                          need_log_dir_sync, last_sequence + 1);
      }
    } else {
      if (status.ok() && !write_options.disableWAL) {
        PERF_TIMER_GUARD(write_wal_time);
        // 并发写WAL
        io_s = ConcurrentWriteToWAL(write_group, log_used, &last_sequence,
                                    seq_inc);
      }
      ...
    }
    ...
  }
  if (status.ok()) {
    // 写MemTable
    if (!parallel) {
      // w.sequence will be set inside InsertInto
      w.status = WriteBatchInternal::InsertInto(xxx); // 参数很多，略
    } else {
      write_group.last_sequence = last_sequence;
      // 设置w.state `STATE_PARALLEL_MEMTABLE_WRITER`
      write_thread_.LaunchParallelMemTableWriters(&write_group);
      in_parallel_group = true;
      if (w.ShouldWriteToMemtable()) {
        ...
        w.status = WriteBatchInternal::InsertInto(xxx); // 参数很多，略
      }
    }
    ...
  }
  ...
}
```

`WriteBatchInternal::InsertInto`逻辑：

```cpp
// db/write_batch.cc
Status WriteBatchInternal::InsertInto(
    WriteThread::Writer* writer, SequenceNumber sequence,
    ColumnFamilyMemTables* memtables, FlushScheduler* flush_scheduler,
    TrimHistoryScheduler* trim_history_scheduler,
    bool ignore_missing_column_families, uint64_t log_number, DB* db,
    bool concurrent_memtable_writes, bool seq_per_batch, size_t batch_cnt,
    bool batch_per_txn, bool hint_per_batch) {
#ifdef NDEBUG
  (void)batch_cnt;
#endif
  // 到此函数表示需要写MemTable
  assert(writer->ShouldWriteToMemtable());
  MemTableInserter inserter(
      sequence, memtables, flush_scheduler, trim_history_scheduler,
      ignore_missing_column_families, log_number, db,
      concurrent_memtable_writes, nullptr /*has_valid_writes*/, seq_per_batch,
      batch_per_txn, hint_per_batch);
  SetSequence(writer->batch, sequence);
  inserter.set_log_number_ref(writer->log_ref);
  // 进行写入
  Status s = writer->batch->Iterate(&inserter);
  assert(!seq_per_batch || batch_cnt != 0);
  assert(!seq_per_batch || inserter.sequence() - sequence == batch_cnt);
  if (concurrent_memtable_writes) {
    inserter.PostProcess();
  }
  return s;
}
```

### 3.3. 代码流程图

上述流程如下：

![rocksdb-WriteImpl](/images/rocksdb-WriteImpl.svg)

### 3.4. 状态机流转

Writer对应的`w.state`状态机更新由`WriteThread::SetState`负责，看下调用到的几个位置，暂时只关注下`DBImpl::WriteImpl`中的流程：

```sh
[MacOS-xd@qxd ➜ rocksdb_v6.15.5 git:(rocksdb-v6.15.5) ✗ ]$ calltree.pl 'SetState' 'DBImpl::WriteImpl' 1 1 3
  
  SetState
  ├── WriteThread::JoinBatchGroup	[vim db/write_thread.cc +379]
  │   ├── DBImpl::WriteImpl	[vim db/db_impl/db_impl_write.cc +68]
  │   └── DBImpl::WriteImplWALOnly	[vim db/db_impl/db_impl_write.cc +664]
  ├── WriteThread::LaunchParallelMemTableWriters	[vim db/write_thread.cc +586]
  │   └── DBImpl::WriteImpl	[vim db/db_impl/db_impl_write.cc +68]
  ├── WriteThread::ExitAsBatchGroupFollower	[vim db/write_thread.cc +616]
  │   └── DBImpl::WriteImpl	[vim db/db_impl/db_impl_write.cc +68]
  └── WriteThread::ExitAsBatchGroupLeader	[vim db/write_thread.cc +628]
      ├── DBImpl::WriteImpl	[vim db/db_impl/db_impl_write.cc +68]
      └── DBImpl::WriteImplWALOnly	[vim db/db_impl/db_impl_write.cc +664]
```

## 4. 番外：vscode切换clangd插件

vscode的cpptools代码跳转不好用，切换成clangd，此处进行记录。

但 **<mark>每个</mark>**工程都需要生成一个`compile_commands.json`。

1、对于cmake项目，比较方便。在初始化时指定：`cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=1`，生成的`compile_commands.json`拷贝到项目路径即可

2、对于makefile项目，利用 [Bear](https://github.com/rizsotto/Bear) 生成
* 参考：[生成compile_commands.json文件](https://edward852.github.io/post/%E7%94%9F%E6%88%90compile_commands.json%E6%96%87%E4%BB%B6/)

简要过程记录：

```sh
[MacOS-xd@qxd ➜ repo ]$ git clone https://github.com/rizsotto/Bear.git
[MacOS-xd@qxd ➜ Bear git:(master) ]$ cmake -B xdbuild -DENABLE_UNIT_TESTS=OFF -DENABLE_FUNC_TESTS=OFF
[MacOS-xd@qxd ➜ xdbuild git:(master) ✗ ]$ make all
[  2%] Creating directories for 'grpc_dependency'
[  4%] Performing download step (git clone) for 'grpc_dependency'
Cloning into 'grpc_dependency'...
# 有些内容下载失败了
# 作者用rust重写了项目，在rust目录中，基于rust进行构建（部分包可能需要开下梯子）
[MacOS-xd@qxd ➜ rust git:(master) ✗ ]$ cargo build --release
# 成功后把工具拷贝到/usr/local/bin/下面
[MacOS-xd@qxd ➜ rust git:(master) ✗ ]$ cp target/release/bear /usr/local/bin
# 生成方式，注意加上`--`，README里也写了，RTFM！
# 到redis项目里试下。但是mac上报错了，简单看了下逻辑可能跟mac上的文件链接相关报错，暂不折腾了 TODO
[MacOS-xd@qxd ➜ redis-5.0.3 ]$ /Users/xd/Documents/workspace/repo/Bear/rust/target/debug/bear -- make
Error: Failed to create the intercept environment

Caused by:
    No such file or directory (os error 2)
```

## 5. 小结

RocksDB中的几个核心组件，并梳理写流程中相应的操作。

## 6. 参考

* [RocksDB-Wiki](https://github.com/facebook/rocksdb/wiki)
* [facebook/rocksdb](https://github.com/facebook/rocksdb/)
* [Journal](https://github.com/facebook/rocksdb/wiki/Journal)
* [MemTable](https://github.com/facebook/rocksdb/wiki/MemTable)
* [Rocksdb BlockBasedTable Format](https://github.com/facebook/rocksdb/wiki/Rocksdb-BlockBasedTable-Format)
