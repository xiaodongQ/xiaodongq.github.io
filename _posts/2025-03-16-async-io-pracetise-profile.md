---
layout: post
title: 并发与异步编程（四） -- 异步demo实验并分析性能
categories: 并发与异步编程
tags: CPU 存储 异步编程
---

* content
{:toc}

异步编程学习实践系列，demo实验，使用 gperftools 和 火焰图 进行性能分析。本篇开始进行实验。



## 1. 背景

[并发与异步编程（二） -- 异步编程框架了解](https://xiaodongq.github.io/2025/03/11/async-io/) 介绍了几种异步编程框架，现在来完成 [并发与异步编程（一） -- 实现一个简单线程池](https://xiaodongq.github.io/2025/03/08/threadpool/) 中的TODO，进行异步编程实验，并简单进行分析性能。

本篇进行代码实践，并使用 [并发与异步编程（三） -- 性能分析工具：gperftools和火焰图](https://xiaodongq.github.io/2025/03/14/async-io-example-profile/) 中提及的工具进行分析。

## 2. 采集方法说明

### 2.1. 采集命令说明

1、gperftools采集及结果转换为pdf说明：

```sh
# Makefile中需要 -lprofiler，使用gperftools
g++ thread_pool_withwait.cpp -pthread -g -lprofiler
# 采集结果
CPUPROFILE=./prof.out ./thread_pool_withwait
# 采集信息转换为pdf进行分析
pprof --pdf ./thread_pool_withwait prof.out > prof.pdf
```

2、采集各种火焰图，新增一个pro_commond.sh脚本手动在不同终端启动，形式如下，完整脚本见：[pro_commond.sh](https://github.com/xiaodongQ/prog-playground/tree/main/concurrent/base/pro_commond.sh)

```sh
[CentOS-root@xdlinux ➜ base git:(main) ✗ ]$ ./pro_commond.sh -h
用法: ./pro_commond.sh [选项]
选项:
  -h, --help                        显示此帮助信息
  -r, --run-program                 启动程序并等待回车
  -s, --run-perf-stat               执行 perf stat 并保存结果
  -c, --run-perf-record-and-flame   执行 perf record 并生成常规火焰图
  -w, --generate-wakeup-flamegraphs 生成 wakeup 火焰图
  -o, --generate-offwaketime-flamegraph 生成 offwaketime 火焰图
  -g, --generate-gperftools-report  生成 gperftools 报告
  -x, --clean-results               清理所有结果目录
```

比如其中的`-w`选项功能：

```sh
function generate_wakeup_flamegraphs() {
    WAKEUP_DIR="wakeup_flamegraph"
    mkdir -p $WAKEUP_DIR
    PID=$(pidof thread_pool_withwait)
    if [ -z "$PID" ]; then
        echo "未找到 thread_pool_withwait 进程"
        return
    fi
    echo "生成 wakeup 火焰图...(程序执行完成后打断采集，会自动生成)"
    /usr/share/bcc/tools/wakeuptime -f -p$PID -f > $WAKEUP_DIR/out.stacks
    cd $WAKEUP_DIR
    flamegraph.pl --color=wakeup --title="Wakeup Time Flame Graph" --countname=us < out.stacks > wakeup.svg
    flamegraph.pl --color=wakeup --title="Wakeup Time Flame Graph" --countname=us --reverse --inverted < out.stacks > wakeup_icicle.svg
    cd..
}
```

### 2.2. 采集脚本用法

手动多窗口执行命令（后续考虑脚本中自动起多终端，比如用`tmux`起不同session）：

```sh
# 终端1 启动运行，等待输入触发（等下面各个终端都启动后，回车触发）
./pro_commond.sh -r
# 终端2 perf stat -p进程
./pro_commond.sh -s
# 终端3 普通on-cpu火焰图，perf record -p进程
./pro_commond.sh -c
# 终端4 wakeup火焰图，需要手动打断（因为wakeuptime -f -p追踪没定时）
./pro_commond.sh -w
# 终端5 offwaketime火焰图，需要手动打断（因为offwaketime -f -p追踪没定时）
./pro_commond.sh -o

# 终端1，最后手动生成gperftools的pdf报告
./pro_commond.sh -g
```

## 3. 基准程序

### 3.1. 基准程序说明

使用第一篇中的线程池程序，进行信息采集作为对比。

为了便于采集工具指定进程，在之前线程池的基础上加上信号触发或等待输入（此处简单处理），启动进程后再开始逻辑

```cpp
int main(int argc, char *argv[]) {
    ThreadPool pool(4);
    std::vector<int> data(10000000, 2);
    size_t chunk = data.size() / 8;
    Result result;

    // 等待信号触发
    cout << "Press any key to start the tasks..." << endl;
    cin.get();

    // 信号触发后开始逻辑
    result.task_count = data.size() / chunk + ((data.size() % chunk == 0) ? 0 : 1);
    for (auto i = 0; i < data.size(); i += chunk) {
        int end = std::min(i + chunk, data.size());
        pool.enqueue_task([=, &result]() { task_run(data, i, end, result); });
    }

    // 启动线程池
    pool.start();

    // 等待所有任务完成
    {
        unique_lock<mutex> lock(result.mtx);
        result.cond.wait(lock);
        cout << "result: " << result.sum << endl;
    }

    // 停止线程池
    pool.stop();

    return 0;
}
```

完整程序见：[GitHub链接](https://github.com/xiaodongQ/prog-playground/tree/main/concurrent/base) 里的thread_pool_withwait.cpp

### 3.2. 运行并采集结果

如上面“采集脚本用法”所述，启动程序和采集。

结果：

```sh
[CentOS-root@xdlinux ➜ base git:(main) ]$ tree   
.
├── Makefile
├── pro_commond.sh
├── results
│   ├── gperftools_report
│   │   ├── prof.out
│   │   └── prof.pdf
│   ├── offwaketime_flamegraph
│   │   ├── offwaketime_out.svg
│   │   └── out.stacks
│   ├── perf_stat_result
│   │   └── perf_stat.out
│   ├── regular_flamegraph
│   │   ├── on_cpu_icicle.svg
│   │   ├── on_cpu.svg
│   │   └── perf.data
│   └── wakeup_flamegraph
│       ├── out.stacks
│       ├── wakeup_icicle.svg
│       └── wakeup.svg
└── thread_pool_withwait.cpp
```

下面对各部分结果做简要分析。结果相关文件可见：[base/results](https://github.com/xiaodongQ/prog-playground/tree/main/concurrent/base/results)

#### 3.2.1. perf stat结果

```sh
 Performance counter stats for process id '69525':

             63.77 msec task-clock                #    0.009 CPUs utilized          
                22      context-switches          #    0.345 K/sec                  
                 0      cpu-migrations            #    0.000 K/sec                  
             4,575      page-faults               #    0.072 M/sec                  
       290,443,472      cycles                    #    4.554 GHz                      (66.25%)
           823,375      stalled-cycles-frontend   #    0.28% frontend cycles idle     (70.28%)
         2,921,689      stalled-cycles-backend    #    1.01% backend cycles idle      (70.32%)
       284,414,120      instructions              #    0.98  insn per cycle         
                                                  #    0.01  stalled cycles per insn  (69.11%)
        51,552,148      branches                  #  808.389 M/sec                    (75.02%)
            56,986      branch-misses             #    0.11% of all branches          (78.60%)

       7.009230002 seconds time elapsed
```

分析：CPU时间占用 63.77ms，上下文切换22次，所以后面切换速率为 `22/63.77ms=0.345K/sec`

#### 3.2.2. gperftools采集的CPU消耗情况

查看 gperftools_report 里面生成的 prof.pdf，可看到最大开销还是vector的数据初始化（`std::vector<int> data(10000000, 2);`）

线程池中的 任务执行体`task_run` 中，vector的取值操作也占了不少开销：

![gperftools结果](/images/2025-03-16-threadcase-gperftools.png)

```cpp
// 任务执行函数
void task_run(const std::vector<int> &data, int start, int end, Result &result) {
    long long sum = 0;
    for (auto i = start; i < end; i++) {
        sum += data[i];
    }
    
    lock_guard<mutex> lk(result.mtx);
    result.sum += sum;
    result.task_done_count++;
    printf("start:%d, end:%d, chunk sum:%lld, total:%lld, done count:%d, task:%d\n",
           start, end, sum, result.sum, result.task_done_count, result.task_count);
    if (result.task_done_count == result.task_count) {
        result.cond.notify_one();
    }
}
```

#### 3.2.3. On-CPU火焰图

对比看下正常和倒置的冰柱型火焰图，都可以看到比较明显的热点：

* vector申请时的数据移动
* 缺页中断里最后的清理也比较耗时

![oncpu-flame](/images/2025-03-16-case-oncpu.png)

最左侧的堆栈最高，可以展开看下，可看到是线程池中对应的线程处理回调：`ThreadPool::thread_proc`

![ThreadPool::thread_proc展开](/images/2025-03-16-case-destructor-mmu.png)

里面主要是`std::vector<int, std::allocator<int> >::~vector`，vector数据的析构处理，内存映射，tlb、mmu相关的内存调度处理。

对应代码：

```cpp
class ThreadPool {
    ...
    // 构造函数，初始化线程池
    ThreadPool(int num) {
        stop_ = false;
        started_ = false;
        while (num-- > 0) {
            threads.emplace_back([this]() { thread_proc(); });
        }
    }
    ...
    // 线程执行体
    void thread_proc() {
        while (!stop_) {
            std::function<void()> t;
            {
                unique_lock<mutex> lk(task_mtx);
                task_cond.wait(lk, [this]() { return stop_ || (started_ &&!tasks.empty()); });
                if (stop_ && tasks.empty()) {
                    return;
                }
                t = std::move(tasks.front());
                tasks.pop_front();
            }
            t();
        }
    }
};
```

#### 3.2.4. Off-CPU火焰图

wakeup火焰图：

![case-wakeup](/images/20250316-case-wakeup.svg)

offwaketime火焰图：

![case-offwaketime_out](/images/20250316-case-offwaketime_out.svg)

## 4. std::async

## 5. io_uring

## 6. 小结



## 7. 参考

* [并发与异步编程（一） -- 实现一个简单线程池](https://xiaodongq.github.io/2025/03/08/threadpool/)
* [并发与异步编程（二） -- 异步编程框架了解](https://xiaodongq.github.io/2025/03/11/async-io/)
* [并发与异步编程（三） -- 性能分析工具：gperftools和火焰图](https://xiaodongq.github.io/2025/03/14/async-io-example-profile/) 

