---
title: 协程梳理实践（二） -- 多线程下的协程调度
description: 梳理多线程下的协程调度
categories: [并发与异步编程]
tags: [协程, 异步编程]
---


## 1. 引言

上一篇梳理了sylar中如何实现一个基本协程，本篇对多线程下的协程调度进行跟踪说明。

## 2. 多线程+协程调度

> 详情可见：[协程调度模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10060963)

从上篇基本协程实现可知，一个线程中可以创建多个协程，协程间会进行挂起和恢复切换，但 **⼀个线程同⼀时刻只能运⾏⼀个协程**。所以一般需要**多线程**来提高协程的效率，这样同时可以有多个协程在运行。

继续学习梳理下sylar里面的协程调度。
* demo代码则可见：`coroutine-lib`中的[3scheduler](https://github.com/xiaodongQ/coroutine-lib/tree/main/fiber_lib/3scheduler)，其中的`fiber.h/fiber.cpp`协程类代码和`2fiber`里是一样的，独立目录只是便于单独编译测试。

### 2.1. 调度器类定义

截取主要结构如下，添加任务：`scheduleLock`，开始调度：`run`。

* `scheduleLock`用于添加任务`ScheduleTask`，是一个模板函数，`FiberOrCb`是模板参数
    * 支持通过协程类（`Fiber`）或者函数（`std::function`）来构造 `ScheduleTask` 调度任务
* 调度类中包含一个线程池：`std::vector<std::shared_ptr<Thread>> m_threads;`
    * 下述cpp中则可见**线程局部变量**定义：`static thread_local Scheduler* t_scheduler = nullptr;`，线程池中每个线程都有一个调度类

```cpp
// coroutine-lib/fiber_lib/3scheduler/scheduler.h
class Scheduler
{
public:
    ...
    // 添加任务到任务队列
    template <class FiberOrCb>
    void scheduleLock(FiberOrCb fc, int thread = -1)
    {
        // 是否需要通知
        bool need_tickle;
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            // empty ->  all thread is idle -> need to be waken up
            // 若原来协程任务队列是空的，下面需要唤醒
            need_tickle = m_tasks.empty();
            
            ScheduleTask task(fc, thread);
            if (task.fiber || task.cb) 
            {
                m_tasks.push_back(task);
            }
        }

        if(need_tickle)
        {
            // 唤醒，不过看该函数是个空实现 {}
            tickle();
        }
    }
    // 启动线程池
    virtual void start();
    // 关闭线程池
    virtual void stop();	

protected:
    // 线程调度函数
    virtual void run();

    virtual void tickle();
    // 空闲协程函数
    virtual void idle();
    // 判断是否可以关闭
    virtual bool stopping();
    ...

private:
    // 任务。支持通过协程和函数来构造任务
    struct ScheduleTask
    {
        std::shared_ptr<Fiber> fiber;
        std::function<void()> cb;
        int thread;
        ScheduleTask(std::shared_ptr<Fiber> f, int thr);
        ScheduleTask(std::shared_ptr<Fiber>* f, int thr);
        ScheduleTask(std::function<void()> f, int thr);
        ScheduleTask(std::function<void()>* f, int thr);
    };

private:
    std::string m_name;
    // 互斥锁 -> 保护任务队列
    std::mutex m_mutex;
    // 线程池
    std::vector<std::shared_ptr<Thread>> m_threads;
    // 任务队列
    std::vector<ScheduleTask> m_tasks;
    // 存储工作线程的线程id
    std::vector<int> m_threadIds;
    // 需要额外创建的线程数
    size_t m_threadCount = 0;
    // 活跃线程数
    std::atomic<size_t> m_activeThreadCount = {0};
    // 空闲线程数
    std::atomic<size_t> m_idleThreadCount = {0};

    // 主线程是否用作工作线程
    bool m_useCaller;
    // 如果是 -> 需要额外创建调度协程
    std::shared_ptr<Fiber> m_schedulerFiber;
    // 如果是 -> 记录主线程的线程id
    int m_rootThread = -1;
    // 是否正在关闭
    bool m_stopping = false;
};
```

### 2.2. 调度器初始化线程池

对应的类成员实现在`scheduler.cpp`中。

* 如上所述，线程局部变量和线程池一一对应，`static thread_local Scheduler* t_scheduler = nullptr;`
* `Scheduler::start()`中初始化创建线程池中的线程
    * `m_mutex`：线程池队列m_threads、任务队列m_tasks、线程id队列 都由该锁做竞争保护

```cpp
// coroutine-lib/fiber_lib/3scheduler/scheduler.cpp

// 每个线程都有一个调度器
static thread_local Scheduler* t_scheduler = nullptr;

void Scheduler::start()
{
    // 锁范围较大，线程池队列m_threads、任务队列m_tasks、线程id队列 都由该锁做竞争保护
    std::lock_guard<std::mutex> lock(m_mutex);
    if(m_stopping)
    {
        std::cerr << "Scheduler is stopped" << std::endl;
        return;
    }

    assert(m_threads.empty());
    m_threads.resize(m_threadCount);
    for(size_t i=0;i<m_threadCount;i++)
    {
        // 创建线程
        m_threads[i].reset(new Thread(std::bind(&Scheduler::run, this), m_name + "_" + std::to_string(i)));
        // 记录线程tid
        m_threadIds.push_back(m_threads[i]->getId());
    }
    if(debug) std::cout << "Scheduler::start() success\n";
}
```

### 2.3. 线程类实现说明

`sylar`里面未使用C++标准库的`std::thread`，而是基于`pthread`自行实现了一个线程类。

**原因是：** 

* `std::thread`在Linux下本身也是基于`pthread`实现的，并未有什么效率增益。（其实现走读可见下面的`std::thread`说明小节）
* 且未提供读写锁（`C++11`未提供，`C++14`中引入了`std::shared_lock`可支持读写锁），而pthread原生的`pthread_rwlock_t`则可直接使用读写锁。

```cpp
// coroutine-lib/fiber_lib/3scheduler/thread.h
class Thread 
{
public:
    Thread(std::function<void()> cb, const std::string& name);
    ~Thread();

    pid_t getId() const { return m_id; }
    const std::string& getName() const { return m_name; }

    void join();

public:
    // 获取系统分配的线程id
    static pid_t GetThreadId();
    // 获取当前所在线程
    static Thread* GetThis();

    // 获取当前线程的名字
    static const std::string& GetName();
    // 设置当前线程的名字
    static void SetName(const std::string& name);

private:
    // 线程函数
    static void* run(void* arg);

private:
    pid_t m_id = -1;
    pthread_t m_thread = 0;

    // 线程需要运行的函数
    std::function<void()> m_cb;
    std::string m_name;
    
    Semaphore m_semaphore;
};
```

可看到构造时直接用了Linux的`pthread_create`创建线程，析构则是通过`detach`让线程自行管理资源的释放。

```cpp
// coroutine-lib/fiber_lib/3scheduler/thread.pp
Thread::Thread(std::function<void()> cb, const std::string &name): 
m_cb(cb), m_name(name) 
{
    int rt = pthread_create(&m_thread, nullptr, &Thread::run, this);
    if (rt) 
    {
        std::cerr << "pthread_create thread fail, rt=" << rt << " name=" << name;
        throw std::logic_error("pthread_create error");
    }
    // 等待线程函数完成初始化
    m_semaphore.wait();
}

Thread::~Thread() 
{
    if (m_thread) 
    {
        pthread_detach(m_thread);
        m_thread = 0;
    }
}
```

#### 2.3.1. 线程id说明

关于线程相关的几个id说明如下。注意：`pthread_self()`获取的线程id仅用于进程内部标识，和`ps`查看到的`pid`、`tid`无关。

| **ID类型**      | **获取方式**          | **作用域**     | **唯一性** | **是否与`ps -efL`的LWP一致** | **备注**                                   |
| --------------- | --------------------- | -------------- | ---------- | ---------------------------- | ------------------------------------------ |
| **`pthread_t`** | `pthread_self()`      | 进程内         | 进程内唯一 | ❌ 不一致                     | 用户态线程ID，Linux下可能是`unsigned long` |
| **`gettid()`**  | `syscall(SYS_gettid)` | 全局（系统内） | 系统唯一   | ✅ 完全一致                   | 即`ps -efL`中的**LWP**（轻量级进程ID）     |
| **`PID`**       | `getpid()`            | 全局（系统内） | 系统唯一   | ✅ 一致（但所有线程相同）     | 进程ID，`ps -efL`中的`PID`列               |
| **`ppid`**      | `getppid()`           | 全局（系统内） | 系统唯一   | ✅ 一致                       | 父进程ID，`ps -efL`中的`PPID`列            |

#### 2.3.2. std::thread 实现简要说明

来看下从gcc中对应的C++标准实现，`std::thread`里的`thread`构造函数。

* `auto __depend = reinterpret_cast<void(*)()>(&pthread_create);` 包装了一下 `pthread_create` 原生api，并赋值给函数对象`__depend`
* 最后的`_M_start_thread`则对传入的 回调函数`__f`和参数`__args`进行**完美转发**，作为`__depend`函数对象的参数
    * `_Invoker_type`包装了可调用对象

```cpp
// gcc-10.3.0-libstdcpp-v3/libstdc++-v3/include/std/thread
class thread
{
    ...
public:
    template<typename _Callable, typename... _Args,
            typename = _Require<__not_same<_Callable>>>
    explicit
    thread(_Callable&& __f, _Args&&... __args)
    {
    static_assert( __is_invocable<typename decay<_Callable>::type,
                                    typename decay<_Args>::type...>::value,
        "std::thread arguments must be invocable after conversion to rvalues"
        );

#ifdef GTHR_ACTIVE_PROXY
    // Create a reference to pthread_create, not just the gthr weak symbol.
    auto __depend = reinterpret_cast<void(*)()>(&pthread_create);
#else
    auto __depend = nullptr;
#endif
    // A call wrapper holding tuple{DECAY_COPY(__f), DECAY_COPY(__args)...}
    using _Invoker_type = _Invoker<__decayed_tuple<_Callable, _Args...>>;

    _M_start_thread(_S_make_state<_Invoker_type>(
            std::forward<_Callable>(__f), std::forward<_Args>(__args)...),
        __depend);
    }

    ~thread()
    {
      if (joinable())
        std::terminate();
    }
    ...
private:
    void _M_start_thread(_State_ptr, void (*)());
    ...
#if _GLIBCXX_THREAD_ABI_COMPAT
    void _M_start_thread(__shared_base_type, void (*)());
    ...
#endif
};
```

`_M_start_thread`对应的实现则为：

```cpp
// gcc-10.3.0-libstdcpp-v3/libstdc++-v3/src/c++11/thread.cc
  void
  thread::_M_start_thread(_State_ptr state, void (*)())
  {
    const int err = __gthread_create(&_M_id._M_thread,
                                     &execute_native_thread_routine,
                                     state.get());
    if (err)
      __throw_system_error(err);
    state.release();
  }
```

在posix里`__gthread_create`中调的还是`pthread_create`：

```cpp
// gcc-10.3.0-libstdcpp-v3/libgcc/gthr-posix.h
static inline int
__gthread_create (__gthread_t *__threadid, void *(*__func) (void*),
                  void *__args)
{
  return __gthrw_(pthread_create) (__threadid, NULL, __func, __args);
}
```

### 2.4. 调度处理

每个线程各自有一个调度器。每个线程各自调度

### 2.5. 调度器初始化


## 3. 小结



## 4. 参考

* [coroutine-lib](https://github.com/youngyangyang04/coroutine-lib)
* [sylar -- 协程调度模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10060963)
* [sylar -- IO协程调度模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10061031)
* LLM
