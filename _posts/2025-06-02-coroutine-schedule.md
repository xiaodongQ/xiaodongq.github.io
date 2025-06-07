---
title: 协程梳理实践（二） -- 多线程下的协程调度
description: 梳理多线程下的sylar协程调度
categories: [并发与异步编程]
tags: [协程, 异步编程]
---


## 1. 引言

上一篇梳理了sylar中如何实现一个基本协程，本篇对多线程下的协程调度进行跟踪说明。

从上篇基本协程实现可知，一个线程中可以创建多个协程，协程间会进行挂起和恢复切换，但 **⼀个线程同⼀时刻只能运⾏⼀个协程**。所以一般需要**多线程**来提高协程的效率，这样同时可以有多个协程在运行。

继续学习梳理下sylar里面的协程调度。

* 详情可见：[协程调度模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10060963)
* demo代码则可见：`coroutine-lib`中的 [3scheduler](https://github.com/xiaodongQ/coroutine-lib/tree/main/fiber_lib/3scheduler)。其中的`fiber.h/fiber.cpp`协程类代码和`2fiber`里是一样的，独立目录只是便于单独编译测试。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 调度流程图

先贴下对下述内容的梳理总结，调度流程如下（svg图，单独链接打开查看效果更好），主要是`Scheduler::run()`中逻辑。

![sylar-coroutine-schedule](/images/sylar-coroutine-schedule.svg)

说明：
* demo使用时，只会创建一个`Scheduler`实例。其中包含一个线程池，可创建多个线程，每个线程都用于协程调度。
* 线程池中所有线程都**共用任务队列**。协程调度时，每个线程**先加锁**从任务队列获取一个任务，取出后就**解锁**，因此其他线程可并发获取任务。
* 而后调度函数中对该任务进行执行，都以**协程**方式`resume`（恢复执行），若任务是函数则也包装为协程再`resume`。
    * `resume`会和**调度协程**进行 **<mark>协程上下文切换</mark>**，并执行协程函数，协程函数的实现中最后都会包含`yield()`，以便切换回调度协程的上下文。
* 没有任务时，走的是idle分支，执行空闲协程进行`sleep 1秒`后切回调度协程

## 3. 调度器类定义

截取主要结构如下，添加任务：`scheduleLock`，开始调度：`run`。

* `scheduleLock`函数用于添加任务`ScheduleTask`，是一个模板函数，`FiberOrCb`是模板参数
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

对应的类成员实现在`scheduler.cpp`中。

构造时，根据`use_caller`来指定是否让调度类主线程也参与协程调度。
* 若参与则少创建一个线程，只创建`threads - 1`个；
* 并且记录主线程id，用以区分其他线程。主线程不参与协程任务的上下文切换，而是**创建一个单独的协程**，用于和任务间进行协程上下文切换。
    * 并把新建的这个调度协程设置给协程所在的线程，而不是用默认情况下线程中的主协程（默认情况下，线程创建主协程时，也指定其为该线程的调度协程）

```cpp
Scheduler::Scheduler(size_t threads, bool use_caller, const std::string &name):
m_useCaller(use_caller), m_name(name)
{
    ...
    // 使用主线程当作工作线程（也用于协程调度）
    if(use_caller)
    {
        // 需要创建的工作线程数-1，当前线程也占了一个工作线程
        threads --;

        // 创建主协程，并默认会设置其为线程的调度协程（不过下面重新设置了调度协程）
        Fiber::GetThis();

        // 创建调度协程
            // 构造函数签名：Fiber(std::function<void()> cb, size_t stacksize = 0, bool run_in_scheduler = true);
            // 此处创建单独的一个调度协程。false表示不参与协程任务的上下文切换，本调度协程退出后会返回主协程
        m_schedulerFiber.reset(new Fiber(std::bind(&Scheduler::run, this), 0, false));
        // 并把新建的这个调度协程设置给协程所在的线程，而不是用默认情况下线程中的主协程
        Fiber::SetSchedulerFiber(m_schedulerFiber.get());
        
        // 记录一下主线程，用以和其他调度线程区分开
        m_rootThread = Thread::GetThreadId();
        m_threadIds.push_back(m_rootThread);
    }
    // 在下面的start()里面，会创建该数量的线程
    m_threadCount = threads;
    if(debug) std::cout << "Scheduler::Scheduler() success\n";
}
```

## 4. 调度器初始化线程池：start()

调度类初始化函数：`start()`。

* 如上所述，线程局部变量和线程池一一对应，`static thread_local Scheduler* t_scheduler = nullptr;`
    * 使用时`Scheduler`调度类只实例化一个，但各线程里指针虽然各自独立，但指向都是本调度类
* `Scheduler::start()`中初始化创建线程池中的线程，其中的线程均**用于协程调度**
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

## 5. 线程类Thread实现说明

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

* 这里说明下线程处理函数`Thread::run`。通过`pthread_create`创建线程后该函数就开始并发运行，线程外则通过`m_semaphore.wait();`等待，而`run`里面异步执行完相关操作后，会通过`thread->m_semaphore.signal();`通知外面可以结束等待了，而后线程构造结束。
* sylar中的`Semaphore m_semaphore;`，则通过`std::mutex`和`std::condition_variable`组合实现

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

// 线程处理函数，其中的相关赋值初始化完成后，通过信号量（通过 std::mutex 和 std::condition_variable 实现）通知
void* Thread::run(void* arg) 
{
    Thread* thread = (Thread*)arg;

    t_thread       = thread;
    t_thread_name  = thread->m_name;
    thread->m_id   = GetThreadId();
    pthread_setname_np(pthread_self(), thread->m_name.substr(0, 15).c_str());

    std::function<void()> cb;
    cb.swap(thread->m_cb); // swap -> 可以减少m_cb中智能指针的引用计数
    
    // 初始化完成
    thread->m_semaphore.signal();

    cb();
    return 0;
}
```

### 5.1. 线程id

关于线程相关的几个id说明如下。注意：`pthread_self()`获取的线程id仅用于进程内部标识，和`ps`查看到的`pid`、`tid`无关。

| **ID类型**      | **获取方式**          | **作用域**     | **唯一性** | **是否与`ps -efL`的LWP一致** | **备注**                                   |
| --------------- | --------------------- | -------------- | ---------- | ---------------------------- | ------------------------------------------ |
| **`pthread_t`** | `pthread_self()`      | 进程内         | 进程内唯一 | ❌ 不一致                     | 用户态线程ID，Linux下可能是`unsigned long` |
| **`gettid()`**  | `syscall(SYS_gettid)` | 全局（系统内） | 系统唯一   | ✅ 完全一致                   | 即`ps -efL`中的**LWP**（轻量级进程ID）     |
| **`PID`**       | `getpid()`            | 全局（系统内） | 系统唯一   | ✅ 一致（但所有线程相同）     | 进程ID，`ps -efL`中的`PID`列               |
| **`ppid`**      | `getppid()`           | 全局（系统内） | 系统唯一   | ✅ 一致                       | 父进程ID，`ps -efL`中的`PPID`列            |

### 5.2. std::thread 实现走读

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

## 6. 调度处理：run()

每个线程各自有一个调度函数，由上述的`Scheduler::start()`中创建。

```cpp
// coroutine-lib/fiber_lib/3scheduler/scheduler.cpp
void Scheduler::run()
{
    ...
    // 设置线程局部变量t_scheduler指向本调度类实例
    // 由于使用时只会创建一个Scheduler实例，所以各线程里指针虽然各自独立，但指向都是本调度类
    SetThis();

    // 运行在新创建的线程 -> 需要创建主协程。
    // 即不是主线程时，通过Fiber::GetThis()创建该线程的主协程
    if(thread_id != m_rootThread)
    {
        // 里面除了创建主协程，还指定其所在线程的调度协程也为该主协程
        Fiber::GetThis();
    }

    // 创建idle协程，协程函数`Scheduler::idle`
    std::shared_ptr<Fiber> idle_fiber = std::make_shared<Fiber>(std::bind(&Scheduler::idle, this));
    ScheduleTask task;
    
    while(true)
    {
        task.reset();
        bool tickle_me = false;

        {
            // 保护任务队列，取出任务后就解锁。后面具体执行任务时不在锁中。
            std::lock_guard<std::mutex> lock(m_mutex);
            // 遍历任务队列，从中获取一个协程任务
            auto it = m_tasks.begin();
            // 1 遍历任务队列
            while(it!=m_tasks.end())
            {
                ...
                // 2 取出任务
                assert(it->fiber||it->cb);
                task = *it;
                m_tasks.erase(it); 
                m_activeThreadCount++;
                // 只获取一个任务就退出循环，所以不会出现一个线程一直占用任务队列的情况
                break;
            }
            // 即 tickle_me |= (it != m_tasks.end());，若获取一个任务后队列中还有任务，则tickle唤醒其他线程
            tickle_me = tickle_me || (it != m_tasks.end());
        }
        ...
        // 3 执行任务
        // 即可以是协程，也可以是函数
        if(task.fiber)
        {
            {
                // 协程中的锁？有必要？
                std::lock_guard<std::mutex> lock(task.fiber->m_mutex);
                if(task.fiber->getState()!=Fiber::TERM)
                {
                    // 协程恢复，执行对应的协程函数
                    task.fiber->resume();
                }
            }
            m_activeThreadCount--;
            task.reset();
        }
        else if(task.cb)
        {
            // 根据函数构造一个协程，并恢复协程执行
            std::shared_ptr<Fiber> cb_fiber = std::make_shared<Fiber>(task.cb);
            {
                std::lock_guard<std::mutex> lock(cb_fiber->m_mutex);
                cb_fiber->resume();
            }
            m_activeThreadCount--;
            task.reset();
        }
        // 4 无任务 -> 执行空闲协程
        else
        {
            ...
            // 上述idle协程创建时，绑定的协程函数为：Scheduler::idle，其中做sleep(1)后就挂起切换
            idle_fiber->resume();
            ...
        }
    }
}
```

## 7. 停止协程调度：stop

```cpp
void Scheduler::stop()
{
    ...
    m_stopping = true;	

    if (m_useCaller) 
    {
        // 当使用了caller线程来调度时（调度类主线程作为一个调度线程），只能由caller线程来执行stop
        assert(GetThis() == this);
    } 
    else 
    {
        // 此处特别注意：
        // 如果主线程（caller线程）不作为其中一个调度线程，则创建threads个线程，那么就会有 threads+1 个线程局部变量。
        // 这里表示stop必须由这threads之外的线程来触发
        assert(GetThis() != this);
    }
}
```

```cpp
Scheduler* Scheduler::GetThis()
{
    return t_scheduler;
}

void Scheduler::SetThis()
{
    t_scheduler = this;
}
```

## 8. 小结

梳理sylar协程在多线程下的调度逻辑。

## 9. 参考

* [coroutine-lib](https://github.com/youngyangyang04/coroutine-lib)
* [sylar -- 协程调度模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10060963)
* [sylar -- IO协程调度模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10061031)
* LLM
