---
layout: post
title: 【实践系列】实现一个简单线程池
categories: CPU
tags: CPU 线程池 C++
---

* content
{:toc}

基于C++实现一个线程池。



## 1. 背景

最近在梳理基础（~~八股~~），有些东西平时都在用，但是要是让自己手撸一个简单demo，却发现缺这缺那，比如线程池、内存池、事件通知框架等等。

有时“看了”，觉得“会了”，动手时却发现并不是这样。究其原因，还是理解不到位，要“做会”而不是“看会”。于是开启 **【实践系列】**，倒推输出。

本篇基于C++实现线程池，并结合 [libstdc++](https://github.com/gcc-mirror/gcc/tree/releases/gcc-10.3.0/libstdc%2B%2B-v3) 代码，理解C++中的一些特性功能使用。

一点想法：

* 现在AI工具已经很强大了，cursor/trae 这类智能体和copilot可以直接把 很多优质资源和质量不错的实践经验 直接传授给你，但接不接受得了、能接受多少，内化多少到自己的技能和思维当中，关键还是实践。用十几年、几十年的工作经验积累起来的东西，借助AI已经可以大大拉低护城墙了，自己的经验何尝不是如此。“技术无用论”/大龄危机？拿出行动力，让技术飞轮滚动起来，不一定有多好的结果，但是祛魅、以及不后悔。
* “纸上得来终觉浅，绝知此事要躬行”
* "Stay hungry, Stay foolish"
* 自勉。

## 2. 线程池简单实现

需求：基于线程池，实现给定数据求和。

### 2.1. 基于 C++11 thread

编译：`g++ thread_pool.cpp -pthread`

`std::function`函数包装器，可以存储、复制和调用任何可调用对象，包括普通函数、成员函数、函数指针、lambda 表达式和仿函数（函数对象）等。组合lambda函数使用很方便。

```cpp
#include <iostream>
#include <vector>
#include <deque>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <functional>
#include <atomic>
#include <algorithm>

using namespace std;

// TODO 定义和实现暂放在一起，后续分离
class ThreadPool {
private:
    vector<thread> threads;
    deque<std::function<void()>> tasks;
    mutex task_mtx;
    condition_variable task_cond;
    std::atomic<bool> stop_;

public:
    ThreadPool(int num) {
        stop_ = false;
        while (num-- > 0) {
            threads.emplace_back([this]() { thread_proc(); });
        }
    }

    ~ThreadPool() {
        stop_ = true;
        task_cond.notify_all();
        for(auto &t : threads) {
            t.join();
        }
    }

    // 任务加入线程池
    void enqueue_task(std::function<void()> &&task) {
        {
            unique_lock<mutex> lk(task_mtx);
            tasks.emplace_back(task);
        }
        // 条件变量通知，既可以放在锁内，也可以放在锁外，各有优劣
        // 持锁内通知：确保其他唤醒线程是最新的共享状态；性能方面，释放锁其他线程才能被唤醒
        // 锁外通知：其他线程被唤醒后能更快地获取锁；需要确保释放锁后共享状态不会被意外修改
        // 一般建议将条件变量的通知操作放在锁外，以提高并发性能。
        task_cond.notify_one();
    }

    void stop() {
        stop_ = true;
        task_cond.notify_all();
    }

private:
    // 线程池执行体
    void thread_proc() {
        while(!stop_) {
            // 从任务队列获取任务
            std::function<void()> t;
            {
                unique_lock<mutex> lk(task_mtx);
                task_cond.wait(lk, [this]() { return stop_ || !tasks.empty(); });
                // 外部停止线程池
                if(stop_ && tasks.empty()) {
                    return;
                }
                t = std::move(tasks.front());
                tasks.pop_front();
            }
            // 执行任务
            t();
        }
    }
};

struct Result {
    long long sum;
    std::mutex mtx;
    int task_count;
    // 用于和task_count比较，所有都完成则进行通知
    int task_done_count;
    std::condition_variable cond;
    Result():sum(0), task_count(0), task_done_count(0) {}
};
void task_run(const std::vector<int> &data, int start, int end, Result &result) {
    long long sum = 0;
    for(auto i = start; i < end; i++) {
        sum += data[i];
    }
    
    lock_guard<mutex> lk(result.mtx);
    result.sum += sum;
    result.task_done_count++;
    printf("start:%d, end:%d, chunk sum:%lld, total:%lld, done count:%d, task:%d\n", 
            start, end, sum, result.sum, result.task_done_count, result.task_count);
    if(result.task_done_count == result.task_count) {
        result.cond.notify_one();
    }
}

int main(int argc, char *argv[])
{
    ThreadPool pool(4);
    std::vector<int> data(10000000, 2);
    size_t chunk = data.size() / 8;
    Result result;
    // 记录要执行的任务数
    result.task_count = data.size()/chunk + ((data.size() % chunk == 0) ? 0 : 1);
    for(auto i = 0; i < data.size(); i += chunk) {
        // 循环不变量[start, end)
        int end = std::min(i + chunk, data.size());
        // 引用捕获result，其他按值捕获
        pool.enqueue_task([=, &result]() { task_run(data, i, end, result); });
    }

    {
        // 等待执行完成，通过信号量通知
        unique_lock<mutex> lock(result.mtx);
        result.cond.wait(lock);
        cout << "result: " << result.sum << endl;
    }
}
```

### 2.2. 基于 pthread（POSIX线程库）

Linux原生的API相对于现代C++，没有RAII写起来生产效率差不少，而且不够优雅。先不写了。

1、线程创建：`pthread_create`

如果任务需要多个参数，需要把参数定义在一个类里，通过`void *arg`传给线程执行函数。（作为对比，`std::thread`可以支持lambda捕获、也支持构造多参数）

```c
#include <pthread.h>
int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                          void *(*start_routine) (void *), void *arg);
```

2、互斥锁：`pthread_mutex_t`，加锁解锁 `pthread_mutex_lock`/`pthread_mutex_unlock`

3、条件变量：`pthread_cond_t`，等待`pthread_cond_wait`，通知 `pthread_cond_signal`/`pthread_cond_broadcast`

## 3. libstdc++ 说明

[gcc-mirror](https://github.com/gcc-mirror/gcc) 仓库是 GCC（GNU Compiler Collection）编译器套件的代码库，涵盖了 GCC 编译器套件的多个方面。

从 `gcc-10.3.0` 分支代码里保留了 [libstdc++](https://github.com/gcc-mirror/gcc/tree/releases/gcc-10.3.0/libstdc%2B%2B-v3) ，上传到自己的仓库了：[libstdc++ 源码](https://github.com/xiaodongQ/gcc-10.3.0-libstdcpp-v3)，用于跟踪学习C++标准库的相关内容。

比如`condition_variable`：

* 定义在：libstdc++-v3/include/std/condition_variable
* 对应的实现则在：libstdc++-v3/src/c++11/condition_variable.cc

```cpp
  // libstdc++-v3/include/std/condition_variable
  /// condition_variable
  class condition_variable
  {
    using steady_clock = chrono::steady_clock;
    using system_clock = chrono::system_clock;
#ifdef _GLIBCXX_USE_PTHREAD_COND_CLOCKWAIT
    // 控制在使用条件变量（std::condition_variable）时是否使用 POSIX 线程库（pthread）中基于时钟的等待函数。
    // 具体来说，当这个宏被定义时，libstdc++ 会使用 pthread_cond_timedwait 或 pthread_cond_clockwait（如果系统支持的话）来实现条件变量的定时等待功能
    using __clock_t = steady_clock;
#else
    using __clock_t = system_clock;
#endif
    // __gthread_cond_t 是 GNU C++ 库（libstdc++）中用于线程同步的底层条件变量类型，
    // 它是对 POSIX 线程库（pthread）中条件变量的封装，为 C++ 标准库中的 std::condition_variable 提供了底层实现支持。
    typedef __gthread_cond_t    __native_type;

#ifdef __GTHREAD_COND_INIT
    __native_type       _M_cond = __GTHREAD_COND_INIT;
#else
    __native_type       _M_cond;
#endif

  public:
    typedef __native_type*  native_handle_type;

    condition_variable() noexcept;
    ~condition_variable() noexcept;

    condition_variable(const condition_variable&) = delete;
    condition_variable& operator=(const condition_variable&) = delete;

    void
    notify_one() noexcept;
    ...
```

## 4. 利用优先级队列支持 任务优先级



## 5. 小结

现代C++一直在迭代演进，跟其他的现代语言相比，基本都有类似特性和用法，比如之前看的Rust，可以借助C++17、20等新特性学习，进一步理解Rust的特性原理和使用。

最近DeepSeek开源的 [3FS](https://github.com/deepseek-ai/3FS) 存储系统，里面就用到很多C++新特性，比如协程（参考：[DeepSeek 3FS 源码解读——协程&RDMA篇](https://zhuanlan.zhihu.com/p/27331176252)）。

## 6. 参考

* [C++ 实现线程池详解：从零到一个高性能线程池](https://mp.weixin.qq.com/s/DuPWHTIw3WrhPRhYWCSOxQ)
* [libstdc++ 源码](https://github.com/xiaodongQ/gcc-10.3.0-libstdcpp-v3)
* [DeepSeek 3FS 源码解读——协程&RDMA篇](https://zhuanlan.zhihu.com/p/27331176252)
* GPT
