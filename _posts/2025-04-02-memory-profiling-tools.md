---
layout: _post
title: CPU及内存调度（三） -- 内存问题定位工具和实验
categories: CPU及内存调度
tags: 内存
---

介绍内存问题定位工具并进行相关实验：Valgrind Massif、AddressSanitizer、Memory Leak and Growth火焰图 和 bcc中内存相关的工具。

## 1. 背景

利用 [Valgrind Massif](https://valgrind.org/docs/manual/ms-manual.html)、[AddressSanitizer](https://github.com/google/sanitizers/wiki/AddressSanitizer) 进行内存相关实验。以及使用 [并发与异步编程（三） -- 性能分析工具：gperftools和火焰图](https://xiaodongq.github.io/2025/03/14/async-io-example-profile/) 中未具体展开的 [Memory Leak and Growth火焰图](https://www.brendangregg.com/FlameGraphs/memoryflamegraphs.html) 工具进行操作实践。

并介绍下bcc tools里面内存相关的工具。

## 2. 测试程序demo

生成一个测试demo，也可见：[leak_test.cpp](https://github.com/xiaodongQ/prog-playground/blob/main/memory/leak/leak_test.cpp)，下述实验的结果均可见该目录。

* 模拟内存泄漏：在单独线程中，随机申请 1KB~1MB 之间的内存，并且50%的概率不释放
* 模拟空悬指针和野指针

编译：`g++ -o leak_test leak_test.cpp -g -pthread`

```cpp
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <pthread.h>

#define MAX_CHUNK_SIZE 1024 * 1024 // 最大块大小为 1 MB
#define MIN_CHUNK_SIZE 1024        // 最小块大小为 1 KB

// 模拟随机内存泄漏的函数
void* random_leak_memory(void* arg) {
    int max_chunks = *(int*)arg;
    srand(time(NULL)); // 初始化随机数种子

    for (int i = 0; i < max_chunks; i++) {
        // 随机生成内存块大小 (1 KB 到 1 MB)
        size_t chunk_size = (rand() % (MAX_CHUNK_SIZE - MIN_CHUNK_SIZE + 1)) + MIN_CHUNK_SIZE;

        // 分配内存
        void *ptr = malloc(chunk_size);
        if (ptr == NULL) {
            perror("malloc failed");
            exit(EXIT_FAILURE);
        }

        // 填充数据以确保内存真正被使用
        memset(ptr, 0, chunk_size);
        printf("Allocated chunk %d of size %zu bytes\n", i + 1, chunk_size);

        // 随机决定是否释放内存（50% 的概率不释放）
        if (rand() % 2 == 0) {
            printf("Freeing chunk %d\n", i + 1);
            free(ptr);
        } else {
            printf("Leaking chunk %d\n", i + 1);
        }

        // 等待模拟实际运行中的内存使用
        sleep(1);
    }

    return NULL;
}

// 模拟空悬指针的问题
void simulate_dangling_pointer() {
    // 分配内存并初始化
    int *ptr = (int*)malloc(sizeof(int));
    if (ptr == NULL) {
        perror("malloc failed");
        exit(EXIT_FAILURE);
    }
    *ptr = 42;
    printf("Allocated memory and initialized with value: %d\n", *ptr);

    // 释放内存
    free(ptr);
    printf("Memory freed, but ptr is still accessible.\n");

    // 访问已释放的内存（产生空悬指针）
    printf("Dangling pointer triggered: Accessing freed memory...\n");
    // 这里尝试访问已经释放的内存
    printf("Value at dangling pointer: %d\n", *ptr); // 可能导致未定义行为
}

// 模拟野指针的问题
void simulate_wild_pointer() {
    int *wild_ptr; // 声明但不初始化
    printf("Wild pointer declared but not initialized.\n");

    // 尝试使用未初始化的指针（产生野指针）
    printf("Wild pointer triggered: Accessing uninitialized memory...\n");
    // 这里尝试访问未初始化的指针
    printf("Value at wild pointer: %d\n", *wild_ptr); // 可能导致段错误
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <max_number_of_chunks>\n", argv[0]);
        return EXIT_FAILURE;
    }
    printf("ASAN_OPTIONS=%s\n", getenv("ASAN_OPTIONS"));

    int max_chunks = atoi(argv[1]);

    if (max_chunks <= 0) {
        fprintf(stderr, "Please provide a positive number of chunks.\n");
        return EXIT_FAILURE;
    }

    pthread_t leak_thread;
    pthread_create(&leak_thread, NULL, random_leak_memory, &max_chunks);

    // 主线程进行空悬指针和野指针的模拟
    printf("\nTesting Dangling Pointer:\n");
    simulate_dangling_pointer();

    printf("\nTesting Wild Pointer:\n");
    simulate_wild_pointer();

    printf("\nRandom memory issue simulation completed. Check memory usage with tools like Valgrind or memleak.\n");

    // 等待泄漏线程完成
    pthread_join(leak_thread, NULL);
    printf("\nAll Tests Done.\n");

    // 主动进入无限循环，方便观察内存占用情况
    while (1) {
        sleep(1);
    }

    return 0;
}
```

## 3. Valgrind Massif

Valgrind比较普遍的用法是用`memcheck`检查内存泄漏，不指定工具时默认就用memcheck。不过有些内存申请了只是未被有效使用则`memcheck`识别不清楚，此时可利用`massif`辅助分析。

可查看官网介绍：[Valgrind Massif](https://valgrind.org/docs/manual/ms-manual.html)

* Valgrind提供的堆分析器`massif`，用于监控程序的堆内存使用情况，可辅助识别内存泄漏和不必要的内存使用
    * massif会报告程序运行期间的峰值内存使用量，包括堆内存的最大分配量，对于**评估程序的内存需求**非常有用
* 性能影响：程序变慢 `20` 倍左右（`10~30`）
* 使用方式：`-g`编译；`valgrind --tool=massif xxx`，会生成一个分析文件；`ms_print ./massif.out.18042`输出报告
* 实用选项
    * **`--time-unit=B`**：massif是定时获取快照的，默认`时间单位（time-unit）`是**指令数**，`--time-unit=B`则指定时间单位是**字节**，能更精准地体现内存分配释放与时间的关系（还是定时采样，不是说每次内存分配都会快照到）
    * **`--pages-as-heap=yes`**：把内存映射页当作堆内存来处理，如此就能捕获更多类型的内存分配，比如`mmap`系统调用分配的内存
    * `--depth=N`：限制调用栈的深度
    * `--threshold=N`：只记录内存分配比例大于N% 的函数
    * `--max-snapshots=N`：限制生成的快照数量，减少磁盘空间消耗和分析时间
    * `--detailed-count=N`：指定详细快照的最大数量
* 示例：`valgrind --tool=massif --time-unit=B --pages-as-heap=yes ./leak_test 5`

### 3.1. memcheck测试

memcheck测试：`valgrind --tool=memcheck --leak-check=full ./leak_test 5`，最后ctrl+c打断程序

```sh
[CentOS-root@xdlinux ➜ leak git:(main) ✗ ]$ valgrind --tool=memcheck --leak-check=full ./leak_test 5
==23944== Memcheck, a memory error detector
...
# 代码运行的随机泄漏情况
Allocated chunk 1 of size 380016 bytes
Freeing chunk 1
Allocated chunk 2 of size 67379 bytes
Leaking chunk 2
Allocated chunk 3 of size 594641 bytes
Leaking chunk 3
Allocated chunk 4 of size 510578 bytes
Leaking chunk 4
Allocated chunk 5 of size 869036 bytes
Leaking chunk 5
...
==23944== 2,041,634 bytes in 4 blocks are definitely lost in loss record 1 of 1
==23944==    at 0x4C360A5: malloc (vg_replace_malloc.c:380)
==23944==    by 0x400AEC: random_leak_memory(void*) (leak_test.cpp:21)
==23944==    by 0x577D179: start_thread (pthread_create.c:479)
==23944==    by 0x5A91DC2: clone (clone.S:95)
==23944== 
==23944== LEAK SUMMARY:
==23944==    definitely lost: 2,041,634 bytes in 4 blocks
==23944==    indirectly lost: 0 bytes in 0 blocks
==23944==      possibly lost: 0 bytes in 0 blocks
==23944==    still reachable: 0 bytes in 0 blocks
==23944==         suppressed: 0 bytes in 0 blocks
```

### 3.2. massif测试

#### 3.2.1. 生成数据文件

massif测试：`valgrind --tool=massif --time-unit=B --pages-as-heap=yes ./leak_test 5`，最后ctrl+c打断程序

对生成的数据文件`massif.out.pid`进行分析：`ms_print massif.out.24000`（ms_print也在Valgrind包中）

```sh
[CentOS-root@xdlinux ➜ leak git:(main) ✗ ]$ valgrind --tool=massif --time-unit=B --pages-as-heap=yes ./leak_test 5
==24161== Massif, a heap profiler
...
# 代码运行的随机泄漏情况
Allocated chunk 1 of size 816446 bytes
Leaking chunk 1
Allocated chunk 2 of size 281989 bytes
Freeing chunk 2
Allocated chunk 3 of size 692444 bytes
Leaking chunk 3
Allocated chunk 4 of size 676581 bytes
Leaking chunk 4
Allocated chunk 5 of size 714673 bytes
Freeing chunk 5
...

# 打断程序，生成了 massif.out.24161 数据文件
[CentOS-root@xdlinux ➜ leak git:(main) ✗ ]$ ls -ltrh
total 56K
-rw-r--r-- 1 root root 3.3K Apr  4 16:31 leak_test.cpp
-rwxr-xr-x 1 root root  29K Apr  4 16:31 leak_test
-rw-r--r-- 1 root root  18K Apr  4 17:18 massif.out.24161
```

#### 3.2.2. 结果分析和说明

`ms_print massif.out.24161`结果分析，完整结果可见：[1_ms_print_24161.result](https://github.com/xiaodongQ/prog-playground/tree/main/memory/leak/massif_profiler/1_ms_print_24161.result)。（该目录下也可查看其他选项的结果，比如`pages-as-heap=no`、`stacks=yes`）

* ms_print结果中，最前面是一个字符组成的柱状图，不同字符表示不同含义
    * 每条竖线表示一次快照（snapshot），体现当前的内存使用，下面的`Number of snapshots: 47`表示有47次快照
    * `:`竖线表示普通快照，`@`竖线表示详细快照，发生了内存分配，`#`表示本次快照到的内存最大，也是一个详细快照
        * `peak snapshots`是通过发生内存释放时进行快照采样，可能存在误差，不一定是实际内存使用最大的时间点，仅供参考
    * `Detailed snapshots: [9, 19, 29, 31, 36 (peak), 46]`表示有6次详细快照
* 接着则是每次快照的信息，详细快照还会把堆栈打出来，比如：`[9, 19, 29, 31, 36 (peak), 46]`，编号`36`达到内存使用顶峰
    * `n        time(B)         total(B)   useful-heap(B) extra-heap(B)    stacks(B)`
    * `编号   时间单位（字节）     消耗的内存      已分配内存  超出内存申请量的内存  栈占用的内存`
    * 栈占用的内存统计默认是关的，因为会大大降低massif的性能，可通过`--stacks=yes`开启（不能和`--pages-as-heap=yes`混用）

```sh
[CentOS-root@xdlinux ➜ leak git:(main) ✗ ]$ ms_print massif.out.24161 
--------------------------------------------------------------------------------
Command:            ./leak_test 5
Massif arguments:   --time-unit=B --pages-as-heap=yes
ms_print arguments: massif.out.24161
--------------------------------------------------------------------------------


    MB
153.6^                                                 #                      
     |                                                 #:::::::::             
     |                                                 #                      
     |                                                 #                      
     |                                                 #         :::::::::::  
     |                                                 #         :            
     |                                                 #         :            
     |                                                 #         :            
     |                                                 #         :           :
     |                                                 #         :          :@
     |                                                 #         :          :@
     |                                                 #         :          :@
     |                                                 #         :          :@
     |                                                 #         :          :@
     |                                                 #         :          :@
     |                                                 #         :          :@
     |                                                 #         :          :@
     |        :::::::::::::::::::::::::::::::::::::::::#         :          :@
     |     @:::                                        #         :          :@
     |   @:@  :                                        #         :          :@
   0 +----------------------------------------------------------------------->MB
     0                                                                   221.7

Number of snapshots: 47
 Detailed snapshots: [9, 19, 29, 31, 36 (peak), 46]
--------------------------------------------------------------------------------
  n        time(B)         total(B)   useful-heap(B) extra-heap(B)    stacks(B)
--------------------------------------------------------------------------------
  0          8,192            8,192            8,192             0            0
  1         16,384           16,384           16,384             0            0
  2        196,608          196,608          196,608             0            0
  3        208,896          208,896          208,896             0            0
  4        212,992          212,992          212,992             0            0
  5        217,088          217,088          217,088             0            0
  6        225,280          225,280          225,280             0            0
  7        229,376          229,376          229,376             0            0
  8        233,472          233,472          233,472             0            0
  9        233,472          233,472          233,472             0            0
100.00% (233,472B) (page allocation syscalls) mmap/mremap/brk, --alloc-fns, etc.
->98.25% (229,376B) 0x0: ???
| 
->01.75% (4,096B) 0x4000FA0: ??? (in /usr/lib64/ld-2.28.so)
...
--------------------------------------------------------------------------------
  n        time(B)         total(B)   useful-heap(B) extra-heap(B)    stacks(B)
--------------------------------------------------------------------------------
 32     18,378,752       18,362,368       18,362,368             0            0
 33     18,550,784       18,460,672       18,460,672             0            0
 36    161,161,216      161,071,104      161,071,104             0            0
100.00% (161,071,104B) (page allocation syscalls) mmap/mremap/brk, --alloc-fns, etc.
->88.54% (142,610,432B) 0x5877707: __mmap64 (mmap64.c:52)
| ->88.54% (142,610,432B) 0x5877707: mmap (mmap64.c:40)
|   ->83.33% (134,217,728B) 0x58016F6: new_heap (arena.c:489)
|   | ->83.33% (134,217,728B) 0x58022A1: _int_new_arena (arena.c:694)
|   |   ->83.33% (134,217,728B) 0x58022A1: arena_get2.part.6 (arena.c:913)
|   |     ->83.33% (134,217,728B) 0x5804E5C: arena_get2 (arena.c:881)
|   |       ->83.33% (134,217,728B) 0x5804E5C: tcache_init.part.7 (malloc.c:2995)
|   |         ->83.33% (134,217,728B) 0x5805B85: tcache_init (malloc.c:2992)
|   |           ->83.33% (134,217,728B) 0x5805B85: malloc (malloc.c:3051)
|   |             ->83.33% (134,217,728B) 0x400AEC: random_leak_memory(void*) (leak_test.cpp:21)
|   |               ->83.33% (134,217,728B) 0x5568179: start_thread (pthread_create.c:479)
|   |                 ->83.33% (134,217,728B) 0x587CDC2: clone (clone.S:95)
...
--------------------------------------------------------------------------------
  n        time(B)         total(B)   useful-heap(B) extra-heap(B)    stacks(B)
--------------------------------------------------------------------------------
 37    161,165,312      161,067,008      161,067,008             0            0
 38    191,287,296      130,945,024      130,945,024             0            0
 39    229,089,280       94,781,440       94,781,440             0            0
 40    229,371,904       95,064,064       95,064,064             0            0
 41    229,376,000       95,059,968       95,059,968             0            0
 42    230,350,848       95,477,760       95,477,760             0            0
 43    231,030,784       96,157,696       96,157,696             0            0
 44    231,747,584       96,874,496       96,874,496             0            0
 45    231,751,680       96,870,400       96,870,400             0            0
 46    232,468,480       96,153,600       96,153,600             0            0
100.00% (96,153,600B) (page allocation syscalls) mmap/mremap/brk, --alloc-fns, etc.
->80.80% (77,692,928B) 0x5877707: __mmap64 (mmap64.c:52)
| ->80.80% (77,692,928B) 0x5877707: mmap (mmap64.c:40)
...
```

## 4. Sanitizer

### 4.1. Sanitizer系列工具说明

Google的`Sanitizer`系列工具，在gcc和clang中都集成了，通过`-fsanitize=`即可开启，还可以在程序运行时动态进行开关

1、**AddressSanitizer（`ASan`）**，检测内存访问错误，如越界访问、使用已释放的内存（悬空指针）、重复释放等

* `-fsanitize=address`
    * 若要检测到报错后支持继续执行，编译时需要加`-fsanitize-recover=address`，并且运行时设置`ASAN_OPTIONS=halt_on_error=0`
    * 需要安装：`yum install libasan`，否则编译会提示缺`libasan.so`库
* 性能影响（仅作参考）：程序变慢约2倍（取决于代码复杂度）；内存占用增加约2倍
* 详见：[AddressSanitizer](https://github.com/google/sanitizers/wiki/AddressSanitizer)
    * 使用有疑问可以先看**FAQ**中是否已覆盖
    * 相关编译选项和运行时选项，可见：**Flags**

2、**LeakSanitizer（`LSan`）**，检测内存泄漏

* `-fsanitize=leak`
    * 需要安装：`yum install libasan`，否则编译会提示缺`libasan.so`库
* 性能影响：运行时开销极低，与 ASan 结合时影响较小（约 1-2 倍）；内存轻微增加
* 详见：[AddressSanitizerLeakSanitizer](https://github.com/google/sanitizers/wiki/AddressSanitizerLeakSanitizer)

3、**MemorySanitizer（`MSan`）**，检测程序中使用未初始化的内存

* `-fsanitize=memory`
* 性能影响：程序变慢约3倍；影子内存与程序内存1:1，内存占用显著增加
* clang支持，貌似没介绍gcc中的支持，暂不展开。详见：[MemorySanitizer](https://github.com/google/sanitizers/wiki/MemorySanitizer)

4、**ThreadSanitizer（`TSan`）**，检测多线程程序中的数据竞争和**死锁**

* `-fsanitize=thread`
    * 需要安装：`yum install libtsan`
* 性能影响：变慢约5-15倍；内存消耗增加5-10倍
* 详见：[ThreadSanitizerCppManual](https://github.com/google/sanitizers/wiki/ThreadSanitizerCppManual)
    * 支持的选项，可见：[ThreadSanitizerFlags](https://github.com/google/sanitizers/wiki/ThreadSanitizerFlags)
    * 示例（使用空格间隔）：`TSAN_OPTIONS="history_size=7 force_seq_cst_atomics=1" ./myprogram`

5、**UndefinedBehavaiorSnitizer（`UBSan`）**，检测未定义行为，如整数溢出、空指针解引用、类型转换错误等

* `-fsanitize=undefined`
    * 需要安装：`yum install libubsan`
* 性能影响：开销通常小于10%
* 详见：[UndefinedBehaviorSanitizer](https://github.com/llvm/llvm-project/blob/main/clang/docs/UndefinedBehaviorSanitizer.rst)，貌似只看到clang的

对比汇总：

| 工具                               | 检测类型                   | 性能影响（时间） | 内存占用       |
|------------------------------------|----------------------------|------------------|----------------|
| AddressSanitizer (ASan)            | 内存访问错误、泄漏         | 2×               | 高（虚拟内存） |
| ThreadSanitizer (TSan)             | 数据竞争、死锁             | 5-15×            | 极高           |
| MemorySanitizer (MSan)             | 未初始化内存使用           | 3×               | 高             |
| UndefinedBehaviorSanitizer (UBSan) | 未定义行为                 | <10%             | 低             |
| Valgrind                           | 综合检测（内存错误、性能） | 20×              | 极高           |

**使用建议**：

* 快速开发调试：优先使用 ASan 或 UBSan（性能影响小，覆盖常见问题）。
    * ASan（内存错误） + UBSan（未定义行为） + LSan（泄漏检测）覆盖大部分常见问题
* 多线程问题：使用 TSan。
* 未初始化内存：使用 MSan（需确保依赖库支持）。
* 全面检测：分阶段使用不同工具，避免同时启用多个工具（如 ASan + TSan 冲突）。
    * LSAN 和 TSAN 不能同时启用（-fsanitize=thread 和 -fsanitize=leak 冲突）
    * 替代方案：先使用 TSAN 检测数据竞争，再使用 LSAN 检测泄漏（分两次编译运行）
* 性能敏感场景：禁用 Sanitizer 或仅在关键模块启用。
* 遗留系统：Valgrind 仍为无源码调试的备选方案

Sanitizer工具使用时需要用系统默认的常规内存分配器，跟踪标准内存管理函数，比如RocksDB里使用时就禁用了jemalloc：

![sanitizer-jemalloc](/images/2025-04-03-sanitizer-jemalloc.png)

### 4.2. 实验

还是使用上述demo，编译器：`gcc version 8.5.0 20210514 (Red Hat 8.5.0-4) (GCC)`

Makefile：

```makefile
# 编译器和标志
CC = g++
CFLAGS = -Wall -g
LDFLAGS = -lpthread

# 程序名称和源文件
TARGET = leak_test
SRCS = leak_test.cpp

# 默认目标
all: $(TARGET)

# 编译普通版本
$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRCS) $(LDFLAGS)

# 使用 AddressSanitizer 编译
# 若要检测到报错后支持继续执行，需要加`-fsanitize-recover=address`，并且运行时设置`ASAN_OPTIONS=halt_on_error=0`
asan: CFLAGS += -fsanitize=address -fsanitize-recover=address
asan: CFLAGS += -DTEST_LEAK
asan: clean $(TARGET)

# 单独使用 LeakSanitizer 编译 (通常与 AddressSanitizer 一起启用)
# AddressSanitizer里面已经默认集成了LeakSanitizer，asan不需要显式指定
lsan: CFLAGS += -fsanitize=leak
lsan: CFLAGS += -DTEST_LEAK
lsan: clean $(TARGET)

# MemorySanitizer
msan: CFLAGS += -fsanitize=memory
msan: clean $(TARGET)

# 使用 UndefinedBehaviorSanitizer 编译
ubsan: CFLAGS += -fsanitize=undefined
ubsan: clean $(TARGET)

# ThreadSanitizer
tsan: CFLAGS += -fsanitize=thread
tsan: clean $(TARGET)

# 清理生成的文件
clean:
	rm -f $(TARGET)

.PHONY: all asan lsan ubsan clean
```

#### 4.2.1. AddressSanitizer

默认情况下，ASan在检测到错误（如内存泄漏、空悬指针访问等）时会**终止程序**。若要检测到报错后支持继续执行，编译时需要加`-fsanitize-recover=address`，并且运行时设置`ASAN_OPTIONS=halt_on_error=0`

编译：

```sh
# -Wall 编译器就会警告不规范使用
[CentOS-root@xdlinux ➜ leak git:(main) ✗ ]$ make asan
rm -f leak_test
g++ -Wall -g -fsanitize=address -o leak_test leak_test.cpp -lpthread
leak_test.cpp: In function ‘void simulate_wild_pointer()’:
leak_test.cpp:81:11: warning: ‘wild_ptr’ is used uninitialized in this function [-Wuninitialized]
     printf("Value at wild pointer: %d\n", *wild_ptr); // 可能导致段错误
     ~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

运行：`ASAN_OPTIONS=`指定选项，多个用`:`间隔

```sh
[CentOS-root@xdlinux ➜ leak git:(main) ✗ ]$ ASAN_OPTIONS="halt_on_error=0:detect_leaks=1:log_path=AddressSanitizer/asan.log" ./leak_test 5
ASAN_OPTIONS=halt_on_error=0:detect_leaks=1:log_path=AddressSanitizer/asan.log

Testing Dangling Pointer:
Allocated memory and initialized with value: 42
Memory freed, but ptr is still accessible.
Dangling pointer triggered: Accessing freed memory...
Allocated chunk 1 of size 43233 bytes
Freeing chunk 1
Value at dangling pointer: 260046849

Testing Wild Pointer:
Wild pointer declared but not initialized.
Wild pointer triggered: Accessing uninitialized memory...
Value at wild pointer: 1102416563

Random memory issue simulation completed. Check memory usage with tools like Valgrind or memleak.
Allocated chunk 2 of size 53407 bytes
Leaking chunk 2
Allocated chunk 3 of size 53586 bytes
Freeing chunk 3
Allocated chunk 4 of size 5692 bytes
Freeing chunk 4
Allocated chunk 5 of size 22918 bytes
Freeing chunk 5
^C
```

结果：

* 可看到 **空悬指针访问**（下面的`heap-use-after-free`）、**野指针访问**（下面的`stack-buffer-underflow`）都检测出来了。
* 内存泄漏没识别，并不是因为未加`-fsanitize=leak`的原因，而是主线程`while(1)`死循环，最后是通过ctrl+c结束的，但lsan需要依赖程序退出时(`atexit`)检查

```sh
=================================================================
==38822==ERROR: AddressSanitizer: heap-use-after-free on address 0x602000000010 at pc 0x00000040111b bp 0x7fff7ee56650 sp 0x7fff7ee56640                      
READ of size 4 at 0x602000000010 thread T0
    #0 0x40111a in simulate_dangling_pointer() /home/workspace/prog-playground/memory/leak/leak_test.cpp:64
    #1 0x4013ca in main /home/workspace/prog-playground/memory/leak/leak_test.cpp:103
    #2 0x7f32aa24b492 in __libc_start_main ../csu/libc-start.c:314
    #3 0x400e0d in _start (/home/workspace/prog-playground/memory/leak/leak_test+0x400e0d)
...
=================================================================
==38822==ERROR: AddressSanitizer: stack-buffer-underflow on address 0x7fff7ee56690 at pc 0x000000401188 bp 0x7fff7ee56650 sp 0x7fff7ee56640
READ of size 4 at 0x7fff7ee56690 thread T0
    #0 0x401187 in simulate_wild_pointer() /home/workspace/prog-playground/memory/leak/leak_test.cpp:81
    #1 0x4013d9 in main /home/workspace/prog-playground/memory/leak/leak_test.cpp:106
    #2 0x7f32aa24b492 in __libc_start_main ../csu/libc-start.c:314
    #3 0x400e0d in _start (/home/workspace/prog-playground/memory/leak/leak_test+0x400e0d)
...
```

#### 4.2.2. LeakSanitizer

AddressSanitizer里面已经默认集成了LeakSanitizer，编译时不需要显式指定`-fsanitize=leak`，但注意还是需要安装liblsan：`yum install liblsan`。

而且AddressSanitizer中 `detect_leaks=1` 是默认打开的，`ASAN_OPTIONS`中不用显式指定。所以**实践中建议直接使用 AddressSanitizer**，不需单独使用LeakSanitizer。

之前内存泄漏没识别，并不是因为未加`-fsanitize=leak`的原因，而是主线程`while(1)`死循环，最后是通过ctrl+c结束的，但lsan需要依赖程序退出时(`atexit`)检测泄漏。有2种方式触发检查：

* 1、移除无限循环，让程序自然退出
* 2、显式触发泄漏检查。
    * 比如调试长期运行的服务，需要代码里调用：`__lsan_do_leak_check();`
    * 包含头文件：`#include <sanitizer/lsan_interface.h>`

两种方式：

* 下面实际验证都是生效的
* 不过方式2打印内存泄漏后还是自动退出了程序，因为**LeakSanitizer检测到泄漏后，默认会终止程序**，即使设置了`ASAN_OPTIONS="halt_on_error=0"`
    * LSAN 独立于 ASAN，`ASAN_OPTIONS` 控制 ASAN 错误（如越界访问）是否终止程序，但 不控制 LSAN 的行为。
    * LSAN 的默认行为，检测到内存泄漏时，LSAN 会打印报告并终止程序（默认退出码为 1），无论是否调用 `__lsan_do_leak_check()`
    * **可通过设置`LSAN_OPTIONS`的退出码`exitcode=0`，让程序继续运行**：`LSAN_OPTIONS="exitcode=0" ASAN_OPTIONS="halt_on_error=0" ./leak_test 5`

```c
// 方式1：
int main(int argc, char *argv[]) {
    ...
    // 主动进入无限循环，方便观察内存占用情况
    // while (1) {
    //     sleep(1);
    // }
}

// 方式2：
#ifdef TEST_LEAK
#include <sanitizer/lsan_interface.h>
#endif
int main(int argc, char *argv[]) {
    ...
#ifdef TEST_LEAK
    __lsan_do_leak_check();
#endif 

    // 主动进入无限循环，方便观察内存占用情况
    while (1) {
        sleep(1);
    } 
}
```

重新`make asan`（不用单独的LeakSanitizer）编译运行：

```sh
[CentOS-root@xdlinux ➜ leak git:(main) ✗ ]$ ASAN_OPTIONS="halt_on_error=0:log_path=AddressSanitizer/asan_no_while.log" ./leak_test 5 
ASAN_OPTIONS=halt_on_error=0:log_path=AddressSanitizer/asan_no_while.log

Testing Dangling Pointer:
Allocated memory and initialized with value: 42
Memory freed, but ptr is still accessible.
Dangling pointer triggered: Accessing freed memory...
Allocated chunk 1 of size 516871 bytes
Leaking chunk 1
Value at dangling pointer: 67108865

Testing Wild Pointer:
Wild pointer declared but not initialized.
Wild pointer triggered: Accessing uninitialized memory...
Value at wild pointer: 1102416563

Random memory issue simulation completed. Check memory usage with tools like Valgrind or memleak.
Allocated chunk 2 of size 10176 bytes
Leaking chunk 2
Allocated chunk 3 of size 288425 bytes
Leaking chunk 3
Allocated chunk 4 of size 652067 bytes
Leaking chunk 4
Allocated chunk 5 of size 184961 bytes
Leaking chunk 5

All Tests Done.
```

查看检测结果，可看到除了检测到上面2个内存问题，最后还检测到了内存泄漏：

```sh
# AddressSanitizer/asan_no_while.log.41093
...
=================================================================
==41093==ERROR: LeakSanitizer: detected memory leaks
 
Direct leak of 1652500 byte(s) in 5 object(s) allocated from:
    #0 0x7f0c4e316ba8 in __interceptor_malloc (/lib64/libasan.so.5+0xefba8)
    #1 0x400f83 in random_leak_memory(void*) /home/workspace/prog-playground/memory/leak/leak_test.cpp:21
    #2 0x7f0c4e00f179 in start_thread /usr/src/debug/glibc-2.28/nptl/pthread_create.c:479
                                                                                 
SUMMARY: AddressSanitizer: 1652500 byte(s) leaked in 5 allocation(s).
```

设置`LSAN_OPTIONS`：注意`log_path`也要设置在这里

```sh
[CentOS-root@xdlinux ➜ leak git:(main) ✗ ]$ LSAN_OPTIONS="exitcode=0:log_path=AddressSanitizer/asan-with-LSAN_OPTIONS.log" ASAN_OPTIONS="halt_on_error=0" ./leak_test 5

ASAN_OPTIONS=halt_on_error=0
LSAN_OPTIONS=exitcode=0:log_path=AddressSanitizer/asan-with-LSAN_OPTIONS.log

Testing Dangling Pointer:
Allocated memory and initialized with value: 42
Memory freed, but ptr is still accessible.
Dangling pointer triggered: Accessing freed memory...
Allocated chunk 1 of size 946309 bytes
Freeing chunk 1
Value at dangling pointer: 1317011457

Testing Wild Pointer:
Wild pointer declared but not initialized.
Wild pointer triggered: Accessing uninitialized memory...
Value at wild pointer: 1102416563

Random memory issue simulation completed. Check memory usage with tools like Valgrind or memleak.
Allocated chunk 2 of size 505380 bytes
Leaking chunk 2
Allocated chunk 3 of size 5840 bytes
Freeing chunk 3
Allocated chunk 4 of size 1029577 bytes
Freeing chunk 4
Allocated chunk 5 of size 922868 bytes
Freeing chunk 5

All Tests Done.
^C
```

完整代码可分别见：[leak_test_no-while-wait.cpp](https://github.com/xiaodongQ/prog-playground/blob/main/memory/leak/leak_test_no-while-wait.cpp) 和 [leak_test.cpp](https://github.com/xiaodongQ/prog-playground/blob/main/memory/leak/leak_test.cpp)。

#### 4.2.3. ThreadSanitizer

测试如下，检测到了`heap-use-after-free`使用问题。

* 也可指定选项：`TSAN_OPTIONS="log_path=ThreadSanitizer/tsan.log halt_on_error=1" ./leak_test 5`
* tsan中，halt_on_error默认是0，检测到错误不退出，具体可见上面贴的flags说明链接

```sh
[CentOS-root@xdlinux ➜ leak git:(main) ✗ ]$ make tsan
rm -f leak_test
g++ -Wall -g -fsanitize=thread -o leak_test leak_test.cpp -lpthread
leak_test.cpp: In function ‘void simulate_wild_pointer()’:
leak_test.cpp:75:11: warning: ‘wild_ptr’ may be used uninitialized in this function [-Wmaybe-uninitialized]
     printf("Value at wild pointer: %d\n", *wild_ptr); // 可能导致段错误
     ~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

[CentOS-root@xdlinux ➜ leak git:(main) ✗ ]$ ./leak_test 5
ASAN_OPTIONS=(null)
LSAN_OPTIONS=(null)

Testing Dangling Pointer:
Allocated memory and initialized with value: 42
Memory freed, but ptr is still accessible.
Dangling pointer triggered: Accessing freed memory...
Allocated chunk 1 of size 451052 bytes
Freeing chunk 1
==================
WARNING: ThreadSanitizer: heap-use-after-free (pid=43497)
  Read of size 4 at 0x7b0400000000 by main thread:
    #0 simulate_dangling_pointer() /home/workspace/prog-playground/memory/leak/leak_test.cpp:64 (leak_test+0x401023)
    #1 main /home/workspace/prog-playground/memory/leak/leak_test.cpp:98 (leak_test+0x4011ff)

  Previous write of size 8 at 0x7b0400000000 by main thread:
    #0 free <null> (libtsan.so.0+0x2c16a)
    #1 simulate_dangling_pointer() /home/workspace/prog-playground/memory/leak/leak_test.cpp:58 (leak_test+0x401003)
    #2 main /home/workspace/prog-playground/memory/leak/leak_test.cpp:98 (leak_test+0x4011ff)

SUMMARY: ThreadSanitizer: heap-use-after-free /home/workspace/prog-playground/memory/leak/leak_test.cpp:64 in simulate_dangling_pointer()
==================
...
```

## 5. Memory 火焰图

介绍文章：[Memory Leak and Growth火焰图](https://www.brendangregg.com/FlameGraphs/memoryflamegraphs.html)

### 5.1. 追踪方法

借助`perf`和`eBPF`来采集内存信息，并生成火焰图，文章介绍了4种方法追踪内存申请事件：

* 1、追踪用户态的 `malloc()`, `free()`
    * 使用bcc下的 stackcount 工具采集用户态的内存分配
        * `/usr/share/bcc/tools/stackcount -p $(pidof mysqld) -U c:malloc > out_mysqld.stack`
        * 生成火焰图：`stackcollapse.pl < out_mysqld.stack | flamegraph.pl --color=mem --title="malloc() Flame Graph" --countname="calls" > out_mysqld.svg`
    * **memleak**：但是要检查内存泄漏的话，需要同时追踪`malloc`、`realloc`、`calloc`、`posix_memalign`等等库函数调用，bcc里的memleak已经实现了，可以直接用
        * 采集：`/usr/share/bcc/tools/memleak -p $(pidof mysqld) > memleak_mysqld.stack`，并用客户端连接mysql触发一些查询操作
    * 性能对比：
        * 追踪`uprobes`使程序变慢 4 倍（4.15内核）
        * libtcmalloc 的堆采集，则变慢 6 倍
* 2、追踪系统调用：`brk()`
    * `brk()`一般不会被应用程序直接调用，比用户态的`malloc`频率低很多。用户态分配器用`malloc`/`calloc`等申请的内存一般在其内存池缓存中，不会频繁`brk`增加内存。
    * 所以可以用`perf`来采集：`perf record -e syscalls:sys_enter_brk -a -g -- sleep 10`
        * `perf script |stackcollapse-perf.pl | flamegraph.pl --color=mem --title="Heap Expansion Flame Graph" --countname="calls" > brk.svg`
    * 也可以用bcc：`/usr/share/bcc/tools/stackcount __x64_sys_brk`
        * `SyS_brk`可能是老内核的方式
        * 可`bpftrace -l|grep brk`过滤查看符号
        * 也可查看系统符号：`grep -i sys_brk /proc/kallsyms`
        * 也可到tracing文件系统下查看：`grep brk /sys/kernel/tracing/available_*`
* 3、追踪系统调用：`mmap()`
    * `perf record -e syscalls:sys_enter_mmap -a -g -- sleep 10`
    * `/usr/share/bcc/tools/stackcount __x64_sys_mmap`
* 4、追踪缺页中断：`page-faults`
    * `perf record -e page-faults -a -g -- sleep 30`
    * `/usr/share/bcc/tools/stackcount 't:exceptions:page_fault_*'`

### 5.2. demo实验

1、火焰图：`/usr/share/bcc/tools/stackcount -p $(pidof leak_test) -U c:malloc > out_leak_test.stack`

`stackcollapse.pl < out_leak_test.stack | flamegraph.pl --color=mem --title="malloc() Flame Graph" --countname="calls" > out_leak_test.svg`

本demo场景收集到的内容比较简单。

![out_leak_test](/images/out_leak_test.svg)

2、memleak：`/usr/share/bcc/tools/memleak -p $(pidof leak_test) > memleak_leak_test.result`

```sh
Attaching to pid 45324, Ctrl+C to quit.                                                                                                                       
[07:21:41] Top 10 stacks with outstanding allocations:
    975573 bytes in 3 allocations from stack
        random_leak_memory(void*)+0x87 [leak_test]
        start_thread+0xea [libpthread-2.28.so]
[07:21:46] Top 10 stacks with outstanding allocations:
    2238288 bytes in 5 allocations from stack
        random_leak_memory(void*)+0x87 [leak_test]
        start_thread+0xea [libpthread-2.28.so]
[07:21:51] Top 10 stacks with outstanding allocations:
    2238288 bytes in 5 allocations from stack
        random_leak_memory(void*)+0x87 [leak_test]
        start_thread+0xea [libpthread-2.28.so]
[07:21:56] Top 10 stacks with outstanding allocations:
    2238288 bytes in 5 allocations from stack
        random_leak_memory(void*)+0x87 [leak_test]
        start_thread+0xea [libpthread-2.28.so]
[07:22:01] Top 10 stacks with outstanding allocations:
    2238288 bytes in 5 allocations from stack
        [unknown]
        [unknown]
```

## 6. bcc tools工具

之前的文章中：

* 在 [eBPF学习实践系列（二） -- bcc tools网络工具集](https://xiaodongq.github.io/2024/06/10/bcc-tools-network/) 中介绍了网络相关bcc工具
* 在 [并发与异步编程（三） -- 性能分析工具：gperftools和火焰图](https://xiaodongq.github.io/2025/03/14/async-io-example-profile/) 中介绍了Scheduler下的offcputime、wakeuptime、offwaketime等几个工具用于生成不同类别的火焰图。

本小节介绍下内存相关工具。

![bcc tools 2019](/images/bcc-tools-2019.png)  
[出处](https://github.com/iovisor/bcc/blob/master/images/bcc_tracing_tools_2019.png)

简要说明上述bcc tools图示中与内存、缓存相关的几个工具。

Virtual Memory模块：

* `memleak`
    * 检测用户空间内存泄漏，跟踪 malloc/free 等内存操作（还有`realloc`、`calloc`、`posix_memalign`等库函数）
* `oomkill`
    * 监控 OOM Killer 杀死进程的事件。可以结合`dmesg`和`/var/log/messages`查看内核日志，分析内存耗尽原因
* `shmsnoop`
    * 跟踪 System V 共享内存操作（shmget/shmat/shmdt），调试共享内存通信异常或性能问题
    * 使用场景：调试共享内存通信异常或性能问题
* `slabratetop`
    * 统计内核 SLAB 缓存的分配/释放速率，结合`slabtop`查看SLAB使用情况
    * 使用场景：内核对象分配异常（如 dentry 缓存暴涨）
* `drsnoop`
    * 跟踪目录项缓存（dcache）查找事件
    * 使用场景：分析文件路径解析性能（如频繁 stat 调用）

VFS模块：

* `cachestat`
    * 统计系统级`页缓存`命中率（LRU 机制）
    * 使用场景：评估系统缓存效率，分析磁盘 I/O 压力
* `cachetop`
    * 按进程/文件统计页缓存命中率
    * 使用场景：定位具体进程或文件的缓存效率问题
* `dcstat`
    * 统计目录项缓存（dcache）的查找次数与命中率
    * 使用场景：分析文件路径解析的整体效率
* `dcsnoop`
    * 跟踪单个目录项缓存查找事件（类似 drsnoop）
    * 使用场景：调试具体文件路径的查找延迟或失败

## 7. 小结

介绍了内存问题定位工具并进行相关实验。

## 8. 参考

* [ptmalloc、tcmalloc与jemalloc对比分析](https://www.cyningsun.com/07-07-2018/memory-allocator-contrasts.html)
* [使用 jemalloc profile memory](https://www.jianshu.com/p/5fd2b42cbf3d)
* [Memory Leak and Growth火焰图](https://www.brendangregg.com/FlameGraphs/memoryflamegraphs.html)
* [Massif](https://valgrind.org/docs/manual/ms-manual.html)
* [AddressSanitizer](https://github.com/google/sanitizers/wiki/AddressSanitizer)