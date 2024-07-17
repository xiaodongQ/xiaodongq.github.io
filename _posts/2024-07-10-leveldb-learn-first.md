---
layout: post
title: leveldb学习笔记（一） -- 整体架构和数据结构
categories: 存储
tags: 存储 leveldb
---

* content
{:toc}

leveldb学习笔记，整体架构和主要数据结构



## 1. 背景

之前学习了一些网络的内容，本打算把网络相关TODO先了结完再去啃存储、CPU、内存等基础和相关领域内容，但扩展开的话点有点多，就先留部分坑了，穿插学习。换一点新的东西，先学习梳理下[leveldb](https://github.com/google/leveldb)这个优秀的存储引擎。

这里先参考 [官网](https://github.com/google/leveldb) 和 [leveldb-handbook](https://leveldb-handbook.readthedocs.io/zh/latest/index.html)，并结合一些博客文章学习，自己再动手做些实验，以此为出发点正好把内核存储栈、涉及的数据结构和算法带着场景再过一遍。

从官网仓库 fork [一份](https://github.com/xiaodongQ/leveldb)，便于代码学习注释、修改调试。（另外会用到benchmark、googletest，`git submodule update --init --recursive`）

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

leveldb中主要由以下几个重要的部件构成：

#### 2.2.1. memtable

leveldb的一次写入操作并不是直接将数据刷新到磁盘文件，而是首先写入到内存中作为代替，memtable就是一个在内存中进行数据组织与维护的结构。

#### 2.2.2. immutable memtable

memtable的容量到达阈值时，便会转换成一个不可修改的memtable，也称为immutable memtable。

#### 2.2.3. log(journal)

leveldb在写内存之前会首先将所有的写操作写到日志文件中，也就是log文件。当以下异常情况发生时，均可以通过日志文件进行恢复。

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

### 2.3. 读写流程（LSM树）

LevelDB基于`LSM树（Log-Structured-Merge-Tree）`，翻译过来就是结构日志合并树。但是`LSM树`并不是一种严格意义上的树型数据结构，而是一种数据存储机制。

LSM流程：

![leveldb LSM树和读写流程](/images/leveldb-lsm-tree.png)

当一个数据写入时，首先记录`预写日志（WAL，Write-Ahead Logging）`，然后将数据插入到内存中一个名为 MemTable 的数据结构中。当 MemTable 的大小到达阈值后，就会转换为 Immutable MemTable。

## 3. 编译运行

### 3.1. 下载并编译

1、下载代码：`git clone --recurse-submodules https://github.com/google/leveldb.git`

2、编译

截取编译过程如下，可看到包含了相当完备的测试内容：gtest、gmock、benchmark、db_bench等。

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

下面结合各gtest用例和测试工具，来了解下leveldb功能和实现。

### 3.2. db_bench

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

### 3.3. 基本IO操作

跟着 `leveldb/doc/index.md`（也可见[doc/index.md](https://github.com/google/leveldb/blob/main/doc/index.md)） 的说明，写个简单demo进行基本功能的试用。

#### 3.3.1. demo

```cpp
#include <cassert>
#include "leveldb/db.h"
#include <iostream>

using namespace std;

leveldb::DB* db;
leveldb::Options options;
options.create_if_missing = true;
leveldb::Status status = leveldb::DB::Open(options, "/tmp/testdb", &db);
assert(status.ok());

```

## 4. 小结


## 5. 参考

1、[leveldb](https://github.com/google/leveldb)

2、[leveldb-handbook](https://leveldb-handbook.readthedocs.io/zh/latest/index.html)

3、[LevelDB数据结构解析](https://www.qtmuniao.com/categories/源码阅读/leveldb/)

4、[LevelDB 源代码阅读（一）：写流程](https://thumarklau.github.io/2021/07/08/leveldb-source-code-reading-1/)

5、GPT
