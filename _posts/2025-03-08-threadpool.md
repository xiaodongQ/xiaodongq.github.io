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

## 2. 线程池实现

需求：基于线程池，实现给定数据求和。

### 2.1. C++11 thread库

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
	std::condition_variable cond;
	Result():sum(0) {}
};
void task_run(const std::vector<int> &data, int start, int end, Result &result) {
	long long sum = 0;
	for(auto i = start; i < end; i++) {
		sum += data[i];
	}
	lock_guard<mutex> lk(result.mtx);
	result.sum += sum;
	printf("start:%d, end:%d, chunk sum:%lld, total:%lld\n", start, end, sum, result.sum);
}

int main(int argc, char *argv[])
{
	ThreadPool pool(4);
	std::vector<int> data(10000000, 2);
	size_t chunk = data.size() / 8;
	Result result;
	for(auto i = 0; i < data.size(); i += chunk) {
		// 循环不变量[start, end)
		int end = std::min(i + chunk, data.size());
		// 引用捕获result，其他按值捕获
		pool.enqueue_task([=, &result]() { task_run(data, i, end, result); });
	}

	{
		// 等待执行完成，通过信号量通知
		this_thread::sleep_for(chrono::seconds(1));
		cout << "result: " << result.sum << endl;
	}
}
```

## 3. 

## 4. 参考


