---
layout: post
title: leveldb学习笔记（五） -- LRU缓存
categories: 存储
tags: 存储 leveldb
---

* content
{:toc}

leveldb学习笔记，本篇学习其LRU缓存实现。



## 1. 背景

继续学习梳理leveldb中具体的流程，本篇来看下LRU缓存实现。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. leveldb缓存说明

leveldb中使用的缓存（cache）主要用于**读取**场景，使得读取热数据时尽量在缓存中命中，减少读取`sstable`文件导致的磁盘io。

其使用了一种基于LRUcache（`Least Recently Used`）的缓存机制，用于缓存：

1. 已打开的sstable文件对象和相关元数据；
2. sstable中的dataBlock的内容；

LRUcache对应的结构由两部分内容组成：

* Hash table：用来存储数据；
* LRU：用来维护数据项的新旧信息；

其中Hash table是基于Yujie Liu等人的论文《Dynamic-Sized Nonblocking Hash Table》实现的，用来存储数据。论文可见：[Dynamic-Sized-Nonblocking-Hash-Tables](https://lrita.github.io/images/posts/datastructure/Dynamic-Sized-Nonblocking-Hash-Tables.pdf)。

当hash表的数据量增大时，为了保证插入、删除、查找等操作仍保持较为理想的操作效率（`O(1)`），需要进行`resize`。基于上述文章实现的hash表可以实现`resize`过程中不阻塞其他并发请求。

## 3. 缓存类定义：TableCache

在`DBImpl`中，定义了一个`TableCache`类指针，这里就是对应的缓存类。

并且在`DBImpl`类的构造函数中，初始化列表中`new`了一个缓存类赋值给`table_cache_`。对应代码为：`table_cache_(new TableCache(dbname_, options_, TableCacheSize(options_)))`，其中第3个参数entries默认990（1000预留10个）

```cpp
// db/db_impl.h
class DBImpl : public DB {
    ...
    // 此处定义了一个缓存
    // table_cache_ provides its own synchronization
    TableCache* const table_cache_;
    ...
    // 内存态的表
    MemTable* mem_;
    // 内存态的表，不可修改
    MemTable* imm_ GUARDED_BY(mutex_);  // Memtable being compacted
    ...
}
```

看下`TableCache`类的具体定义，

```cpp
// db/table_cache.h
class TableCache {
 public:
  TableCache(const std::string& dbname, const Options& options, int entries);
  ...
  Iterator* NewIterator(const ReadOptions& options, uint64_t file_number,
                        uint64_t file_size, Table** tableptr = nullptr);

  // If a seek to internal key "k" in specified file finds an entry,
  // call (*handle_result)(arg, found_key, found_value).
  Status Get(const ReadOptions& options, uint64_t file_number,
             uint64_t file_size, const Slice& k, void* arg,
             void (*handle_result)(void*, const Slice&, const Slice&));

  // Evict any entry for the specified file number
  void Evict(uint64_t file_number);

 private:
  Status FindTable(uint64_t file_number, uint64_t file_size, Cache::Handle**);

  Env* const env_;
  const std::string dbname_;
  const Options& options_;
  // Cache本身是一个抽象类，此处抽象指针用作多态
  Cache* cache_;
};
```

并且在其构造函数中，初始化了`Cache* cache_;`，通过`NewLRUCache`创建了对应的实现类实例。

传入的`entries`即上面的`990`。

```cpp
// db/table_cache.cc
// 构造函数，这里cache_初始化为了一个 LRUCache（ShardedLRUCache类）
// DBImpl()构造函数初始化列表中，传进来的entries默认为990
TableCache::TableCache(const std::string& dbname, const Options& options,
                       int entries)
    : env_(options.env),
      dbname_(dbname),
      options_(options),
      cache_(NewLRUCache(entries)) {}
```

## 4. 缓存实现类：ShardedLRUCache 和 LRUCache

```cpp
// util/cache.cc
// 传入上面的entries（即990）
Cache* NewLRUCache(size_t capacity) { return new ShardedLRUCache(capacity); }
```

LRU缓存实现类逻辑：实际实现为`LRUCache`类，`ShardedLRUCache`类包含了一个`LRUCache`类数组，数组成员`16`个。

```cpp
// util/cache.cc
static const int kNumShardBits = 4;
// 即16
static const int kNumShards = 1 << kNumShardBits;

class ShardedLRUCache : public Cache {
 private:
  // LRUCache 数组，此处为16个
  LRUCache shard_[kNumShards];
  port::Mutex id_mutex_;
  uint64_t last_id_;

  static inline uint32_t HashSlice(const Slice& s) {
    return Hash(s.data(), s.size(), 0);
  }

  static uint32_t Shard(uint32_t hash) { return hash >> (32 - kNumShardBits); }

 public:
  explicit ShardedLRUCache(size_t capacity) : last_id_(0) {
    const size_t per_shard = (capacity + (kNumShards - 1)) / kNumShards;
    for (int s = 0; s < kNumShards; s++) {
      shard_[s].SetCapacity(per_shard);
    }
  }
  ~ShardedLRUCache() override {}
  Handle* Insert(const Slice& key, void* value, size_t charge,
                 void (*deleter)(const Slice& key, void* value)) override {
    const uint32_t hash = HashSlice(key);
    return shard_[Shard(hash)].Insert(key, hash, value, charge, deleter);
  }
  Handle* Lookup(const Slice& key) override {
    const uint32_t hash = HashSlice(key);
    return shard_[Shard(hash)].Lookup(key, hash);
  }
  void Release(Handle* handle) override {
    LRUHandle* h = reinterpret_cast<LRUHandle*>(handle);
    shard_[Shard(h->hash)].Release(handle);
  }
  void Erase(const Slice& key) override {
    const uint32_t hash = HashSlice(key);
    shard_[Shard(hash)].Erase(key, hash);
  }
  void* Value(Handle* handle) override {
    return reinterpret_cast<LRUHandle*>(handle)->value;
  }
  uint64_t NewId() override {
    MutexLock l(&id_mutex_);
    return ++(last_id_);
  }
  void Prune() override {
    for (int s = 0; s < kNumShards; s++) {
      shard_[s].Prune();
    }
  }
  size_t TotalCharge() const override {
    size_t total = 0;
    for (int s = 0; s < kNumShards; s++) {
      total += shard_[s].TotalCharge();
    }
    return total;
  }
};
```

## 5. 小结

学习梳理LRU缓存实现逻辑。

## 6. 参考

1、[leveldb](https://github.com/google/leveldb)

2、[leveldb-handbook cache](https://leveldb-handbook.readthedocs.io/zh/latest/cache.html)

3、[漫谈 LevelDB 数据结构（三）：LRU 缓存（ LRUCache）](https://www.qtmuniao.com/2021/05/09/levedb-data-structures-lru-cache/)
