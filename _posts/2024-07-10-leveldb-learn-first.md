---
layout: _post
title: leveldb学习笔记（一） -- 整体架构和基本操作
categories: 存储
tags: 存储 leveldb
---

* content
{:toc}

leveldb学习笔记，本篇说明整体架构和基本操作，并进行代码验证。



## 1. 背景

之前学习了一些网络的内容，本打算把网络相关TODO先了结完再去啃存储、CPU、内存等基础和相关领域内容，但扩展开的话点有点多，就先留部分坑了，穿插学习。换一点新的东西，先学习梳理下[leveldb](https://github.com/google/leveldb)这个优秀的存储引擎。

这里先参考 [官网](https://github.com/google/leveldb) 和 [leveldb-handbook](https://leveldb-handbook.readthedocs.io/zh/latest/index.html)，并结合一些博客文章学习，自己再动手做些实验，以此为出发点正好把Linux内核存储栈、涉及的数据结构和算法带着场景再过一遍。

从官网仓库 [fork](https://github.com/xiaodongQ/leveldb) 一份，便于代码学习注释、修改调试。（另外会用到benchmark、googletest，`git submodule update --init --recursive`）

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. leveldb说明和整体架构

### 2.1. 项目说明

LevelDB是一个由Google开源的、快速的键值存储库，提供了`string key`到`string value`的有序映射。

作者是 Sanjay Ghemawat 和 Jeff Dean 两位Google大佬。可以见这篇杂志译文了解：[揭秘 Google 两大超级工程师：AI 领域绝无仅有的黄金搭档](https://www.leiphone.com/category/industrynews/yV1namFFdTlXc6bx.html)，这两位后续还发表了`MapReduce`论文（"三驾马车"之一），Jeff Dean还主导打造了谷歌大脑、TensorFlow等等。

特性：

- 键和值可以是任意的字节数组。
- 数据按照键的顺序进行存储。
- 调用者可以提供自定义的比较函数来覆盖排序顺序。
- 基本操作包括：`Put(key, value)`（插入键值对）、`Get(key)`（获取键对应的值）、`Delete(key)`（删除键及其对应的值）。
- 支持在单个原子批处理中进行多处更改。
- 用户可以创建临时快照，以获得数据的一致视图。
- 支持数据的正向和反向迭代。
- 数据自动使用[Snappy](https://google.github.io/snappy/)压缩库进行压缩。
- 外部活动（如文件系统操作等）通过虚拟接口传递，以便用户可以自定义操作系统交互。

### 2.2. 整体架构

![leveldb 整体架构](/images/leveldb_arch.jpeg)

LevelDB基于`LSM树（Log-Structured-Merge-Tree）`，翻译过来就是结构日志合并树。但是`LSM树`并不是一种严格意义上的树型数据结构，而是一种数据存储机制。

下图跟上面类似，这里看LSM流程更直观一点：

![leveldb LSM树和读写流程](/images/leveldb-lsm-tree.png)

下面介绍leveldb几个重要的构成部件：

#### 2.2.1. memtable

leveldb的一次写入操作并不是直接将数据刷新到磁盘文件，而是首先写入到内存中作为代替，memtable就是一个在内存中进行数据组织与维护的结构。

#### 2.2.2. immutable memtable

memtable的容量到达阈值时，便会转换成一个不可修改的memtable，也称为immutable memtable。

#### 2.2.3. log(journal)

leveldb在写内存之前会首先将所有的写操作写到日志文件中，也就是log文件，`预写日志（WAL，Write-Ahead Logging）`。当写log、内存、immutable memtable等异常时，均可以通过日志文件进行恢复。

#### 2.2.4. sstable

内存中的数据达到一定容量，就需要将数据**持久化**到磁盘中。除了某些元数据文件，leveldb的数据主要都是通过`sstable`来进行存储。

虽然在内存中，所有的数据都是按序排列的，但是当多个memetable数据持久化到磁盘后，对应的不同的sstable之间是存在交集的（*持久化后再写入的新数据顺序会有交叉*），在读操作时，需要对所有的sstable文件进行遍历，严重影响了读取效率。因此leveldb后台会“定期“整合这些sstable文件，该过程也称为 **`compaction`（合并）**。随着`compaction`的进行，sstable文件在逻辑上被分成若干层，由内存数据直接dump出来的文件称为`level 0`层文件，后期整合而成的文件为`level i` 层文件，**这也是leveldb这个名字的由来**。

所有的sstable文件本身的内容是**不可修改的**，这种设计哲学为leveldb带来了许多优势，简化了很多设计。

#### 2.2.5. manifest

leveldb中有个**版本（version）**的概念，一个版本中主要记录了每一层中所有文件的元数据，元数据包括（1）文件大小（2）最大key值（3）最小key值。该版本信息十分关键，除了在查找数据时，利用维护的每个文件的最大／小key值来加快查找，还在其中维护了一些进行compaction的统计值，来控制compaction的进行。

当每次`compaction`完成，leveldb都会创建一个新的`version`，创建规则：`versionNew = versionOld + versionEdit`，`versionEdit`指代的是基于旧版本的基础上，变化的内容。

**manifest文件就是用来记录这些versionEdit信息的。**一个versionEdit数据，会被编码成一条记录，写入manifest文件中。

因为每次leveldb启动时，都会创建一个新的Manifest文件。因此数据目录可能会存在多个Manifest文件。Current则用来指出哪个Manifest文件才是我们关心的那个Manifest文件。

#### 2.2.6. current

这个文件的内容只有一个信息，就是记载当前的`manifest`文件名。

## 3. 编译

### 3.1. 下载并编译

1、下载代码：`git clone --recurse-submodules https://github.com/google/leveldb.git`

(换成自己fork的仓库：`git clone --recurse-submodules https://github.com/xiaodongQ/leveldb.git`)

2、编译

截取编译过程如下，可看到里面包含了相当完备的测试内容：gtest、gmock、benchmark、db_bench等。

```sh
[root@xdlinux ➜ leveldb git:(main) ]$ mkdir -p build && cd build
[root@xdlinux ➜ build git:(main) ]$ cmake -DCMAKE_BUILD_TYPE=Release .. && cmake --build .
-- The C compiler identification is GNU 8.5.0
-- The CXX compiler identification is GNU 8.5.0
-- Detecting C compiler ABI info
...
-- Configuring done
-- Generating done
-- Build files have been written to: /home/workspace/leveldb/build
[  1%] Building CXX object CMakeFiles/leveldb.dir/db/builder.cc.o
...
[ 37%] Linking CXX static library libleveldb.a
[ 37%] Built target leveldb
...
[ 39%] Built target leveldbutil
...
[ 40%] Building CXX object third_party/googletest/googletest/CMakeFiles/gtest.dir/src/gtest-all.cc.o
[ 41%] Linking CXX static library ../../../lib/libgtest.a
[ 41%] Built target gtest
...
[ 43%] Built target gmock
...
[ 46%] Built target env_posix_test
...
[ 48%] Built target gtest_main
...
[ 72%] Built target leveldb_tests
...
[ 75%] Built target c_test
...
[ 93%] Built target benchmark
...
[ 97%] Built target db_bench
...
[ 98%] Built target gmock_main
...
[100%] Linking CXX static library libbenchmark_main.a
[100%] Built target benchmark_main
```

编译的主要成果物如下：

```sh

[root@xdlinux ➜ build git:(main) ]$ ls -ltrh
# libleveldb静态库
-rw-r--r--  1 root root 663K Jul 17 14:55 libleveldb.a
# 用于从指定文件dump内容
-rwxr-xr-x  1 root root 169K Jul 17 14:55 leveldbutil
# 包含几个测试环境中posix读写接口的gtest用例
-rwxr-xr-x  1 root root 610K Jul 17 14:55 env_posix_test
# 包含一些leveldb特性的gtest用例，比如db操作、自动compact、log、恢复、跳表、布隆过滤器等等
-rwxr-xr-x  1 root root 1.9M Jul 17 14:55 leveldb_tests
# 使用libleveldb库的几个基本测试
-rwxr-xr-x  1 root root 341K Jul 17 14:55 c_test
# 用来测试leveldb性能，直接./db_bench执行即可
-rwxr-xr-x  1 root root 345K Jul 17 14:56 db_bench
...
```

可以看到，成果物里面是没有一个服务端程序的。**LevelDB 没有设计成`C/S`模式，而是将数据库以库文件的形式提供给用户，运行时数据库需要和服务一起部署在同一台服务器上。**

下面结合各gtest用例和测试工具，来了解下leveldb功能。

### 3.2. db_bench测试工具

先用上述编译结果中的`db_bench`，简单看下本地跑的性能情况（NVME SSD）。

```sh
[root@xdlinux ➜ build git:(main) ]$ ./db_bench
LevelDB:    version 1.23
Date:       Wed Jul 17 22:30:31 2024
CPU:        16 * AMD Ryzen 7 5700G with Radeon Graphics
CPUCache:   512 KB
Keys:       16 bytes each
Values:     100 bytes each (50 bytes after compression)
Entries:    1000000
RawSize:    110.6 MB (estimated)
FileSize:   62.9 MB (estimated)
# 没有开启Snappy压缩
WARNING: Snappy compression is not enabled
------------------------------------------------
fillseq      :       0.813 micros/op;  136.0 MB/s     
fillsync     :    1590.175 micros/op;    0.1 MB/s (1000 ops)
fillrandom   :       1.555 micros/op;   71.1 MB/s     
overwrite    :       2.035 micros/op;   54.4 MB/s     
readrandom   :       2.024 micros/op; (864322 of 1000000 found)
readrandom   :       1.681 micros/op; (864083 of 1000000 found)
readseq      :       0.070 micros/op; 1586.2 MB/s    
readreverse  :       0.161 micros/op;  686.8 MB/s    
compact      :  350350.000 micros/op;
readrandom   :       1.161 micros/op; (864105 of 1000000 found)
readseq      :       0.055 micros/op; 2027.3 MB/s    
readreverse  :       0.130 micros/op;  854.0 MB/s    
fill100K     :     416.247 micros/op;  229.1 MB/s (1000 ops)
crc32c       :       0.703 micros/op; 5558.3 MB/s (4K per op)
snappycomp   :    1744.000 micros/op; (snappy failure)
snappyuncomp :    1696.000 micros/op; (snappy failure)
zstdcomp     :    1441.000 micros/op; (zstd failure)
zstduncomp   :    1448.000 micros/op; (zstd failure)
```

贴下github官网提供的数据，作为简单对比参考

```sh
LevelDB:    version 1.1
Date:       Sun May  1 12:11:26 2011
CPU:        4 x Intel(R) Core(TM)2 Quad CPU    Q6600  @ 2.40GHz
CPUCache:   4096 KB
Keys:       16 bytes each
Values:     100 bytes each (50 bytes after compression)
Entries:    1000000
Raw Size:   110.6 MB (estimated)
File Size:  62.9 MB (estimated)
# 写性能
fillseq      :       1.765 micros/op;   62.7 MB/s
fillsync     :     268.409 micros/op;    0.4 MB/s (10000 ops)
fillrandom   :       2.460 micros/op;   45.0 MB/s
overwrite    :       2.380 micros/op;   46.5 MB/s
# 读性能
readrandom  : 16.677 micros/op;  (approximately 60,000 reads per second)
readseq     :  0.476 micros/op;  232.3 MB/s
readreverse :  0.724 micros/op;  152.9 MB/s
# compactions之后的读性能
readrandom  : 11.602 micros/op;  (approximately 85,000 reads per second)
readseq     :  0.423 micros/op;  261.8 MB/s
readreverse :  0.663 micros/op;  166.9 MB/s
```

另外关于性能情况，`leveldb/doc/benchmark.html`里面还做了一下`LevelDB`、`Kyoto TreeDB`、`SQLite3`的对比说明。

## 4. 基本操作测试

跟着 `leveldb/doc/index.md`（也可见[doc/index.md](https://github.com/google/leveldb/blob/main/doc/index.md)） 的说明，写个简单[demo](https://github.com/xiaodongQ/prog-playground/blob/main/leveldb/test_leveldb.cpp)进行基本功能的试用。

leveldb公共接口为`include/leveldb/*.h`，一般不需要再依赖其他涉及内部实现的头文件了。

这里先`make install`一下，把必要的头文件和库安装到系统路径，便于后面使用。

```sh
[root@xdlinux ➜ build git:(main) ]$ make install
Consolidate compiler generated dependencies of target leveldb
[ 37%] Built target leveldb
Consolidate compiler generated dependencies of target leveldbutil
[ 39%] Built target leveldbutil
...
Consolidate compiler generated dependencies of target benchmark_main
[100%] Built target benchmark_main
Install the project...
-- Install configuration: "Release"
-- Installing: /usr/local/lib64/libleveldb.a
-- Installing: /usr/local/include/leveldb/c.h
...
# 可看到下面还会生成对应的文档，不过貌似都是benchmark性能测试相关的
-- Installing: /usr/local/share/doc/leveldb/releasing.md
-- Installing: /usr/local/share/doc/leveldb/tools.md
-- Installing: /usr/local/share/doc/leveldb/user_guide.md
```

### 4.1. 创建并打开一个数据库

```cpp
#include <cassert>
#include <iostream>
#include "leveldb/db.h"

using namespace std;
 
void test_leveldb()
{
    leveldb::DB* db;
    leveldb::Options options;
    options.create_if_missing = true;
    leveldb::Status status = leveldb::DB::Open(options, "/tmp/testdb", &db);
    assert(status.ok());
}

int main(int argc, char *argv[])
{
    test_leveldb();
    return 0;
}
```

```sh
# 编译
[root@xdlinux ➜ leveldb git:(main) ✗ ]$ g++ test_leveldb.cpp -lleveldb -lpthread -o test_leveldb
# 运行
[root@xdlinux ➜ leveldb git:(main) ✗ ]$ ./test_leveldb
# 查看上面指定的 /tmp/testdb 目录
[root@xdlinux ➜ leveldb git:(main) ✗ ]$ ll /tmp/testdb -ltrh
total 16K
-rw-r--r-- 1 root root   0 Jul 18 14:55 LOCK
-rw-r--r-- 1 root root 149 Jul 18 14:55 LOG.old
-rw-r--r-- 1 root root  50 Jul 18 14:55 MANIFEST-000004
-rw-r--r-- 1 root root   0 Jul 18 14:55 000005.log
-rw-r--r-- 1 root root  16 Jul 18 14:55 CURRENT
-rw-r--r-- 1 root root 181 Jul 18 14:55 LOG
```

可以看下上面几个非空文件的内容：

```sh
# 当前日志
[root@xdlinux ➜ leveldb git:(main) ✗ ]$ cat /tmp/testdb/LOG
2024/07/18-14:55:58.384853 140470980511552 Recovering log #3
2024/07/18-14:55:58.455339 140470980511552 Delete type=0 #3
2024/07/18-14:55:58.455378 140470980511552 Delete type=3 #2
# 历史日志
[root@xdlinux ➜ leveldb git:(main) ✗ ]$ cat /tmp/testdb/LOG.old
2024/07/18-14:55:44.266962 140622247708480 Creating DB /tmp/testdb since it was missing.
2024/07/18-14:55:44.277569 140622247708480 Delete type=3 #1
# 当前使用的MANIFEST
[root@xdlinux ➜ leveldb git:(main) ✗ ]$ cat /tmp/testdb/CURRENT        
MANIFEST-000004
# MANIFEST文件中的内容
[root@xdlinux ➜ leveldb git:(main) ✗ ]$ cat /tmp/testdb/MANIFEST-000004 
V???leveldb.BytewiseComparator??#       #   
```

选项说明（定义为`struct Options`，include/leveldb/options.h）：

|            选项             |       默认值       |               说明                |
| :-------------------------: | :----------------: | :-------------------------------: |
|   bool create_if_missing    |       false        |           不存在则创建            |
|    bool error_if_exists     |       false        |       若数据库已存在则报错        |
|    bool paranoid_checks     |       false        |         检查到出错就退出          |
|      Logger* info_log       |      nullptr       | 为nullptr则在当前目录生成日志文件 |
|  size_t write_buffer_size   |  4 * 1024 * 1024   |            写缓存大小             |
|     int max_open_files      |        1000        |        DB可以打开的文件数         |
|      size_t block_size      |       4*1024       |             block大小             |
|    size_t max_file_size     |  2 * 1024 * 1024;  |           最大文件大小            |
| CompressionType compression | kSnappyCompression |             压缩算法              |

### 4.2. 基本读写

leveldb提供3个基本操作来查询/修改：`Put`、`Delete`、`Get`

```cpp
void test_leveldb_rw()
{
    leveldb::DB* db;

    // 初始化
    leveldb::Options options;
    options.create_if_missing = true;
    // 若已存在则DB::Open会报错退出
    // options.error_if_exists = true;
    leveldb::Status status = leveldb::DB::Open(options, "/tmp/testdb", &db);
    assert(status.ok());

    // 读写操作
    std::string value = "hello-leveldb";
    string key1 = "xdkey1";
    string key2 = "xdkey2";

    // 设置key1
    // leveldb::WriteOptions()默认构造一个sync为false的选项结构体
    // 声明为：Status Put(const WriteOptions& options, const Slice& key, const Slice& value);
    // class Slice是一个简单的包含指针和数据大小的类结构，可以通过char*/string来构造初始化
    leveldb::Status s = db->Put(leveldb::WriteOptions(), key1, value);
    assert(s.ok());
    cout << "set key:" << key1 << ", value:" << value << " ok" << endl;
    // 获取key1
    value="";
    // 声明为：Status Get(const ReadOptions& options, const Slice& key, std::string* value)
    s = db->Get(leveldb::ReadOptions(), key1, &value);
    assert(s.ok());
    cout << "get key:" << key1 << ", value:" << value << endl;

    // 设置key2的value为key1对应的value
    s = db->Put(leveldb::WriteOptions(), key2, value);
    assert(s.ok());
    cout << "set key:" << key2 << ", value:" << value << " ok" << endl;

    // 删除key1
    // 声明为：Status Delete(const WriteOptions& options, const Slice& key) 
    s = db->Delete(leveldb::WriteOptions(), key1);
    assert(s.ok());
    cout << "del key:" << key1 << " ok"<< endl;

    // 尝试获取key1
    s = db->Get(leveldb::ReadOptions(), key1, &value);
    if (!s.ok()) {
        cout << "get key:" << key1 << " error! errmsg: " << s.ToString() << endl;
    }

    // 获取key2
    value = "";
    s = db->Get(leveldb::ReadOptions(), key2, &value);
    if (!s.ok()){
        cout << "get key:" << key2 << " error! errmsg: " << s.ToString() << endl;
    }else{
        cout << "get key:" << key2 << ", value:" << value << endl;
    }

    // 清理数据库
    delete db;
}
```

```sh
# 执行
[root@xdlinux ➜ leveldb git:(main) ✗ ]$ ./test_leveldb
set key:xdkey1, value:hello-leveldb ok
get key:xdkey1, value:hello-leveldb
set key:xdkey2, value:hello-leveldb ok
del key:xdkey1 ok
get key:xdkey1 error! errmsg: NotFound: 
get key:xdkey2, value:hello-leveldb
```

### 4.3. WriteBatch

场景：key1移动到key2

过程为：获取key1的value -> 设置key2的value -> 删除key1。若删除key1之前db异常，则两个key有原来相同的value

利用 `WriteBatch` 可达到原子更新的效果

```cpp
void test_leveldb_write_batch()
{
    leveldb::DB* db;
    leveldb::Options options;
    options.create_if_missing = true;
    leveldb::Status status = leveldb::DB::Open(options, "/tmp/testdb", &db);
    assert(status.ok());

    // 准备数据
    string key1 = "xdkey1";
    std::string value = "test-atomic-update";
    leveldb::Status s = db->Put(leveldb::WriteOptions(), key1, value);
    assert(s.ok());
    cout << "set key:" << key1 << ", value:" << value << endl;

    string key2 = "xdkey2";
    value = "";
    s = db->Get(leveldb::ReadOptions(), key1, &value);
    assert(s.ok());

    // 使用 WriteBatch
    leveldb::WriteBatch batch;
    batch.Delete(key1);
    batch.Put(key2, value);
    s = db->Write(leveldb::WriteOptions(), &batch);
    assert(s.ok());
    cout << "move key:" << key1 << " to key:" << key2 << endl;

    s = db->Get(leveldb::ReadOptions(), key1, &value);
    cout << "get key: " << key1 << " result:" << s.ToString() << endl;
    s = db->Get(leveldb::ReadOptions(), key2, &value);
    cout << "get key: " << key2 << " result:" << s.ToString() << ", value:" << value << endl;

    // 清理数据库
    delete db;
}
```

```sh
[root@xdlinux ➜ leveldb git:(main) ✗ ]$ ./test_leveldb
set key:xdkey1, value:test-atomic-update
move key:xdkey1 to key:xdkey2
get key: xdkey1 result:NotFound: 
get key: xdkey2 result:OK, value:test-atomic-update
```

### 4.4. Iteration

leveldb的迭代器，用于遍历key。

```cpp
void test_leveldb_iterator()
{
    leveldb::DB* db;
    leveldb::Options options;
    options.create_if_missing = true;
    leveldb::Status s = leveldb::DB::Open(options, "/tmp/testdb", &db);
    assert(s.ok());

    s = db->Put(leveldb::WriteOptions(), "xdkey1", "itv1");
    assert(s.ok());
    s = db->Put(leveldb::WriteOptions(), "xdkey2", "itv2");
    assert(s.ok());
    s = db->Put(leveldb::WriteOptions(), "xdkey3", "itv3");
    assert(s.ok());
    s = db->Put(leveldb::WriteOptions(), "xdkey4", "itv4");
    assert(s.ok());

    // 创建 Iterator
    // 创建后是未初始化的，必须先调用某种Seek再使用它
    leveldb::Iterator* it = db->NewIterator(leveldb::ReadOptions());
    // 从头开始遍历所有记录，`SeekToFirst`
    cout << "scan first to last..." << endl;
    for (it->SeekToFirst(); it->Valid(); it->Next()) {
        // 注意Slice类需要调用下ToString()才转成std::string
        cout << it->key().ToString() << ": "  << it->value().ToString() << endl;
        assert(it->status().ok());  // Check for any errors found during the scan
    }

    // 也可以从尾部开始向前遍历所有记录，`SeekToLast`
    cout << "scan last to first..." << endl;
    for (it->SeekToLast(); it->Valid(); it->Prev()) {
        cout << it->key().ToString() << ": "  << it->value().ToString() << endl;
        assert(it->status().ok());  // Check for any errors found during the scan
    }

    // 也可以指定key的范围遍历，`Seek`并给定结束条件
    string start = "xdkey2";
    string end = "xdkey3";
    cout << "scan rang [" << start << ", " << end << "]..." << endl;
    // 自行控制结束条件
    for (it->Seek(start); it->Valid() && it->key().ToString() <= end; it->Next()) {
        cout << it->key().ToString() << ": "  << it->value().ToString() << endl;
        assert(it->status().ok());  // Check for any errors found during the scan
    }

    delete it;

    // 清理数据库
    delete db;
}
```

结果：

```sh
[root@xdlinux ➜ leveldb git:(main) ✗ ]$ ./test_leveldb     
scan first to last...
xdkey1: itv1
xdkey2: itv2
xdkey3: itv3
xdkey4: itv4
scan last to first...
xdkey4: itv4
xdkey3: itv3
xdkey2: itv2
xdkey1: itv1
scan rang [xdkey2, xdkey3]...
xdkey2: itv2
xdkey3: itv3
```

### 4.5. Snapshots

快照，提供只读的全局键值记录视图。

通过`GetSnapshot`获取处理句柄，基于该句柄创建的迭代器会观察到固定快照的DB记录状态。

```cpp
// 文件位置：include/leveldb/db.h
  // Return a handle to the current DB state.  Iterators created with
  // this handle will all observe a stable snapshot of the current DB
  // state.  The caller must call ReleaseSnapshot(result) when the
  // snapshot is no longer needed.
  virtual const Snapshot* GetSnapshot() = 0;
```

查看内部实现，该接口必定会new一个成员，不会返回NULL。

示例：

```cpp
void test_snapshot()
{
    leveldb::DB* db;
    leveldb::Options options;
    options.create_if_missing = true;
    // 为防止之前记录影响观察，用个单独的数据库
    leveldb::Status s = leveldb::DB::Open(options, "/tmp/testdb_for_snapshot", &db);
    assert(s.ok());

    // 初始化数据
    s = db->Put(leveldb::WriteOptions(), "xdkey1", "itv1");
    assert(s.ok());
    s = db->Put(leveldb::WriteOptions(), "xdkey2", "itv2");
    assert(s.ok());
    s = db->Put(leveldb::WriteOptions(), "xdkey3", "itv3");
    assert(s.ok());
    s = db->Put(leveldb::WriteOptions(), "xdkey4", "itv4");
    assert(s.ok());

    // options.snapshot
    leveldb::ReadOptions options_sp;
    // GetSnapshot生成快照
    // 声明为：const Snapshot* GetSnapshot()，返回一个当前db状态的处理句柄
    // 当不再使用时，必须通过 ReleaseSnapshot(result) 释放
    options_sp.snapshot = db->GetSnapshot();
    cout << "get snapshot" << endl;

    // 快照后做些增删改之类的操作，用作对比
    db->Put(leveldb::WriteOptions(), "xdkey5", "itv5");
    cout << "[add xdkey5:itv5]" << endl;
    assert(s.ok());
    db->Put(leveldb::WriteOptions(), "xdkey1", "itv1_modify");
    cout << "[modify xdkey1:itv1_modify]" << endl;
    assert(s.ok());
    db->Delete(leveldb::WriteOptions(), "xdkey2");
    cout << "[delete xdkey2]" << endl;
    assert(s.ok());
    
    // 此处使用的ReadOptions是设置了快照的，所以只有当时snapshot的记录状态
    cout << "scan snapshot..." << endl;
    leveldb::Iterator* it = db->NewIterator(options_sp);
    for (it->SeekToFirst(); it->Valid(); it->Next()) {
        cout << it->key().ToString() << ":" << it->value().ToString() << endl;
    }

    // 使用普通ReadOptions
    cout << "scan ordinarily..." << endl;
    leveldb::Iterator* it_od = db->NewIterator(leveldb::ReadOptions());
    for (it_od->SeekToFirst(); it_od->Valid(); it_od->Next()) {
        cout << it_od->key().ToString() << ":" << it_od->value().ToString() << endl;
    }
    delete it;

    // 释放快照
    db->ReleaseSnapshot(options_sp.snapshot);

    // 清理数据库
    delete db;
}
```

结果如下：

可知**快照后新增记录是都可以看到的，只是快照时已有的记录不做变更（包括被删除的）**

```sh
[root@xdlinux ➜ leveldb git:(main) ✗ ]$ ./test_leveldb     
get snapshot
[add xdkey5:itv5]
[modify xdkey1:itv1_modify]
[delete xdkey2]
scan snapshot...
xdkey1:itv1
xdkey2:itv2
xdkey3:itv3
xdkey4:itv4
xdkey5:itv5
scan ordinarily...
xdkey1:itv1_modify
xdkey3:itv3
xdkey4:itv4
xdkey5:itv5
```

## 5. 小结

学习了leveldb的整体架构和重要构成部件，对其功能做了基本的验证测试。后续进一步看其功能实现，以及重要的数据结构。

## 6. 参考

1、[leveldb](https://github.com/google/leveldb)

2、[leveldb-handbook](https://leveldb-handbook.readthedocs.io/zh/latest/index.html)

3、[LevelDB数据结构解析](https://www.qtmuniao.com/categories/源码阅读/leveldb/)

4、[LevelDB 源代码阅读（一）：写流程](https://thumarklau.github.io/2021/07/08/leveldb-source-code-reading-1/)

5、GPT
