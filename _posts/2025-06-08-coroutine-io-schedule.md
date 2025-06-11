---
title: 协程梳理实践（三） -- sylar协程IO事件调度
description: 梳理sylar协程中的IO事件调度
categories: [并发与异步编程]
tags: [协程, 异步编程]
---


## 1. 引言

前文梳理了协程的基本实现 和 协程在多线程情况下的调度，只是搭起了一个架子，协程任务也比较简单，并未涉及到网络IO等跟业务关联紧密的操作。

本篇梳理的内容比较实用，通过协程中结合网络IO事件，能更高效利用系统资源，较大提升应用程序的性能。

相关说明详见：
* [sylar -- IO协程调度模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10061031)
* [sylar -- 定时器模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=16417216)

本篇涉及代码：[fiber_lib/5iomanager](https://github.com/xiaodongQ/coroutine-lib/tree/main/fiber_lib/5iomanager)。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 实现总体说明

sylar中的IO协程调度基于`epoll`实现。相对于上篇多线程下的协程调度，在没有任务时，通过`epoll_wait`等待事件，避免没有必要的线程空转。
* 封装的添加、删除接口 和 `epoll_ctl`的`EPOLL_CTL_ADD`、`EPOLL_CTL_DEL`操作相对应。
* 关注的事件则归类简化为了 **读（`EPOLLIN`）**、**写（`EPOLLOUT`）**事件。

总体流程如下：

![sylar_io_coroutine_scheduler](/images/sylar_io_coroutine_scheduler.svg)

* IO协程调度类继承上篇中的调度类和一个定时器。支持epoll和定时器两个途径来产生任务，任务可以是协程或者函数对象，协程调度时都是包装为协程来进行`resume()`执行的。
* 使用`idle()`和`tickle()`来避免没有任务情况下的空转，通过`epoll_wait`来进行等待，有两种情况会触发epoll事件：
    * 1）当有用户注册的fd，如网络socket）有数据读写，epoll会触发事件，`run`调度处理中会进行事件处理，其中根据读、写不同，调用不同上下文进行任务添加；
    * 2）通过`pipe`管道来进行通知，当任务队列里还有任务没一次性处理完，通过`tickle()`向管道发送数据来触发`epoll_wait`

`epoll`的使用流程和项目中的应用，之前在好几篇历史博文里都梳理过了，可作回顾：
* Redis的事件循环：[梳理Redis中的epoll机制](https://xiaodongq.github.io/2025/02/28/epoll-redis-nginx/)
* muduo库，以及trae生成的demo项目：[ioserver服务实验（二） -- epoll使用梳理](https://xiaodongq.github.io/2025/02/25/ioserver2-epoll-dive/)
* 3FS里的事件循环也基于epoll：[DeepSeek 3FS学习实践（一） -- 事件循环](https://xiaodongq.github.io/2025/03/28/3fs-overview-eventloop/)
    * 另外其中也基于`Folly`库的**协程**，对IO进行了异步化。

## 3. IO调度类定义

在前面的`class Scheduler`中，像`start()`/`stop()`、`tickle()`、`run()`、`idle()`等很多成员都定义为了`virtual`虚函数，是为了显式地提示这部分成员函数可被子类**重载**。

本篇的主角`IOManager`调度类，就是继承自`Scheduler`，其定义截取部分内容如下：

* 其中包含的fd上下文信息：`FdContext`，会设置给epoll_event的私有数据指针。
    * `FdContext`里面针对读和写事件，分别定义了一个事件上下文成员（`EventContext`类型）
    * 各自包含三部分：协程调度器指针、协程、事件回调函数。事件一般是协程 或者 函数 取其一。

```cpp
// coroutine-lib/fiber_lib/5iomanager/ioscheduler.h
class IOManager : public Scheduler, public TimerManager 
{
    ...
private:
    // 私有数据，赋值给`struct epoll_event`中的私有数据指针：event.data.ptr
    struct FdContext
    {
        // 事件上下文定义，里面包含了3部分：协程调度器指针 + 协程 + 事件回调函数
        struct EventContext
        {
            // scheduler
            Scheduler *scheduler = nullptr;
            // callback fiber
            std::shared_ptr<Fiber> fiber;
            // callback function
            std::function<void()> cb;
        };
        // read event context
        EventContext read;
        // write event context
        EventContext write;
        int fd = 0;
        ...
    };
public:
    IOManager(size_t threads = 1, bool use_caller = true, const std::string &name = "IOManager");
    ~IOManager();

    // add one event at a time
    int addEvent(int fd, Event event, std::function<void()> cb = nullptr);
    // delete event
    bool delEvent(int fd, Event event);
    ...
protected:
    // 下面显式override的函数都重载掉
    void tickle() override;
    bool stopping() override;
    void idle() override;
    ...
private:
    // epoll句柄，epoll_create/epoll_create1 创建
    int m_epfd = 0;
    // fd[0] read，fd[1] write
    // pipe管道，用于idle通知。
    int m_tickleFds[2];
    std::atomic<size_t> m_pendingEventCount = {0};
    // C++17起才支持，读写锁
        // 通过 unique_lock<std::shared_mutex> w_lk(m_mutex) 定义写锁
        // 通过 shared_lock<std::shared_mutex> r_lk(m_mutex) 定义读锁
    std::shared_mutex m_mutex;
    // store fdcontexts for each fd
    std::vector<FdContext *> m_fdContexts;
};
```

上面的`m_tickleFds`是`pipe`创建的管道，`pipe`管道是半双工的，1个管道需要2个文件fd，一读一写。POSIX标准写了可以 **`fd[1]`写，`fd[0]`读**，没有明确是否可以`fd[0]`写，`fd[1]`读，使用时需统一遵循`fd[1]`写`fd[0]`读。

`man`手册中就是遵循`POSIX`标准给的说明：

```sh
# Manual page pipe(3p)
PIPE(3P)                          POSIX Programmer's Manual                         PIPE(3P)
       Data can be written to the file descriptor fildes[1] and read from the file  descrip‐
       tor  fildes[0].  A read on the file descriptor fildes[0] shall access data written to
       the file descriptor fildes[1]  on  a  first-in-first-out  basis.  It  is  unspecified
       whether  fildes[0]  is  also  open for writing and whether fildes[1] is also open for
       reading.
```

## 4. IOManager类构造

其中工作：
* 1）初始化epoll句柄；
* 2）创建好pipe管道；
* 3）注册读管道（`fd[0]`用于读）的读事件；
* 4）父类初始化调度线程池。

```cpp
// coroutine-lib/fiber_lib/5iomanager/ioscheduler.cpp
// IO调度构造函数
IOManager::IOManager(size_t threads, bool use_caller, const std::string &name): 
Scheduler(threads, use_caller, name), TimerManager()
{
    // create epoll fd
    // 参数自Linux 2.6.8会被忽略，但要>0
    m_epfd = epoll_create(5000);
    assert(m_epfd > 0);

    // create pipe
    // 创建一个pipe管道时，需要2个文件fd，一读一写。一般是fd[1]写，fd[0]读
    int rt = pipe(m_tickleFds);
    assert(!rt);

    // add read event to epoll
    epoll_event event;
    // 注册读事件，且使用边缘触发（来事件后需一次性读取完对应数据）
    event.events  = EPOLLIN | EPOLLET; // Edge Triggered
    event.data.fd = m_tickleFds[0];

    // non-blocked
    rt = fcntl(m_tickleFds[0], F_SETFL, O_NONBLOCK);
    assert(!rt);
    // 此处注册的句柄为pipe的 fd[0]，用于读
    rt = epoll_ctl(m_epfd, EPOLL_CTL_ADD, m_tickleFds[0], &event);
    assert(!rt);

    // 初始化 FdContext数组
    contextResize(32);

    // 这里的start()没有在IOManager类中重载，用的是父类Scheduler中的函数实现。
    // 里面会初始化线程池，创建threads个线程都用于协程调度
    start();
}
```

## 5. epoll事件注册：addEvent

事件注册，传入需要注册的`fd`和事件，向epoll里进行注册（添加或修改）。几点说明：

* `FdContext *fd_ctx`指针会设置给 `epoll_event` 中的私有数据指针
    * 可以选择`cb`传入函数对象，若不传入则会创建一个协程，记录在`EventContext`上下文中
* 此处注册事件时，epoll的触发模式也是`EPOLLET`（上述构造注册`fd[0]`管道的事件也是）
* 其中涉及`std::shared_mutex`读写锁（共享锁/独占锁）的用法，需要C++17才支持
    * `unique_lock<std::shared_mutex> w_lk(m_mutex)` 定义写锁
    * `shared_lock<std::shared_mutex> r_lk(m_mutex)` 定义读锁

```cpp
// coroutine-lib/fiber_lib/5iomanager/ioscheduler.cpp
int IOManager::addEvent(int fd, Event event, std::function<void()> cb) 
{
    // attemp to find FdContext
    FdContext *fd_ctx = nullptr;
    
    // 读锁
    std::shared_lock<std::shared_mutex> read_lock(m_mutex);
    if ((int)m_fdContexts.size() > fd) 
    {
        // fd作为数组下标，好处是便于索引查找，不过没使用的fd下标存在一些浪费
        fd_ctx = m_fdContexts[fd];
        // 解除读锁。加锁只为了访问 m_fdContexts
        read_lock.unlock();
    }
    else
    {
        // 先解除上面的读锁
        read_lock.unlock();
        // 写锁
        std::unique_lock<std::shared_mutex> write_lock(m_mutex);
        // fd作下标超出vector容量，则根据 fd*1.5 来扩容，而不是之前的capacity
        contextResize(fd * 1.5);
        fd_ctx = m_fdContexts[fd];
    }

    // fd上下文整体加互斥锁
    std::lock_guard<std::mutex> lock(fd_ctx->mutex);
    
    // the event has already been added
    if(fd_ctx->events & event)
    {
        return -1;
    }

    // add new event
    // 原来的事件不是NONE（0），则op是修改，按位或增加本次要注册的事件
    int op = fd_ctx->events ? EPOLL_CTL_MOD : EPOLL_CTL_ADD;
    epoll_event epevent;
    // 边缘触发模式
    epevent.events   = EPOLLET | fd_ctx->events | event;
    epevent.data.ptr = fd_ctx;

    // 事件注册
    int rt = epoll_ctl(m_epfd, op, fd, &epevent);
    if (rt) 
    {
        std::cerr << "addEvent::epoll_ctl failed: " << strerror(errno) << std::endl; 
        return -1;
    }

    // 注册的事件计数+1
    ++m_pendingEventCount;

    // update fdcontext
    // 更新成 Event 里限定的3个枚举（无事件、读、写），去掉了前面 按位| 的边缘触发标志
    fd_ctx->events = (Event)(fd_ctx->events | event);

    // update event context
    // 根据读写类型获取对应的 FdContext，设置其信息：调度类指针 和 协程/回调函数
    // fd_ctx指针设置给了上述 epoll_event 中的私有数据指针，只是个指针。此处更新fd_ctx指向结构的内容，前后顺序没影响
    FdContext::EventContext& event_ctx = fd_ctx->getEventContext(event);
    assert(!event_ctx.scheduler && !event_ctx.fiber && !event_ctx.cb);
    event_ctx.scheduler = Scheduler::GetThis();
    if (cb) 
    {
        // 如果传入了函数对象，则记录在EventContext中
        event_ctx.cb.swap(cb);
    } 
    else 
    {
        // 没传函数则创建一个新协程（新协程默认是RUNNING），并记录在EventContext中
        event_ctx.fiber = Fiber::GetThis();
        assert(event_ctx.fiber->getState() == Fiber::RUNNING);
    }
    return 0;
}
```

## 6. 调度流程

`IOManager`里没有重载父类`Scheduler`中的`run()`，因此**调度类线程池**中各调度线程的线程函数还是`Scheduler::run()`。

具体逻辑可见上篇中的 [调度处理：run()](https://xiaodongq.github.io/2025/06/02/coroutine-schedule/#34-%E8%B0%83%E5%BA%A6%E5%A4%84%E7%90%86run)。这里贴一下上篇的流程图：

![sylar-coroutine-schedule](/images/sylar-coroutine-schedule.svg)

差异比较大的是`tickle()`和`idle()`成员函数，在`IOManager`类中进行了重载实现。

1、`tickle()`中判断有`idle`线程（空闲线程）时，向`pipe`管道的`fd[1]`发送（`write`）一个消息，而`idle()`里会进行**消息接收方**的处理。

```cpp
// coroutine-lib/fiber_lib/5iomanager/ioscheduler.cpp
void IOManager::tickle() 
{
    // no idle threads
    if(!hasIdleThreads()) 
    {
        return;
    }
    int rt = write(m_tickleFds[1], "T", 1);
    assert(rt == 1);
}
```

2、如上面调度流程图所示，没有任务时，通过`idle`协程进行`resume()`操作，执行的是`idle`协程绑定的`idle()`函数，此处即重载后的`IOManager::idle()`
* `idle()`里面结合了定时器做`epoll_wait`，定时器说明见下小节。

```cpp
void IOManager::idle()
{
    static const uint64_t MAX_EVNETS = 256;
    // 创建临时的epoll_event数组（没用vector<epoll_event>方式），用于接收epoll_wait返回的就绪事件，每次最大256个
    std::unique_ptr<epoll_event[]> events(new epoll_event[MAX_EVNETS]);

    while(true)
    {
        // blocked at epoll_wait
        int rt = 0;
        // 此处while循环为了结合定时器做超时检查，等待epoll事件超时触发，有触发则break此处的while(true)
        while(true)
        {
            static const uint64_t MAX_TIMEOUT = 5000;
            // 返回堆中最近的超时时间，还有多少ms到期（set里第一个成员时间最小，最先到期）
            uint64_t next_timeout = getNextTimer();
            next_timeout = std::min(next_timeout, MAX_TIMEOUT);

            // 获取events原始指针，接收epoll触发的事件。此处阻塞等待事件发生，避免idle协程空转
            rt = epoll_wait(m_epfd, events.get(), MAX_EVNETS, (int)next_timeout);
            // EINTR -> retry
            if(rt < 0 && errno == EINTR)
            {
                continue;
            }
            else
            {
                // 只要有任何事件通知就break出小循环
                break;
            }
        }

        // 既然有超时触发的事件，此处捞取超时定时器的回调函数
        std::vector<std::function<void()>> cbs;
        listExpiredCb(cbs);
        if(!cbs.empty()) 
        {
            // 把这些回调函数都加入到协程调度器的任务队列里
            for(const auto& cb : cbs) 
            {
                // 如果是第一次添加任务，则会tickle()一次：其中会向管道的fd[1]进行一次write（fd[0]就可以收到epoll读事件）
                scheduleLock(cb);
            }
            cbs.clear();
        }

        // 处理epoll_wait获取到的事件
        for (int i = 0; i < rt; ++i) 
        {
            epoll_event& event = events[i];
            // pipe管道，则做read，由于是边缘触发，此处while处理。虽然fd[1] write时也只是写了1个字符。
            if (event.data.fd == m_tickleFds[0]) 
            {
                uint8_t dummy[256];
                // edge triggered -> exhaust
                while (read(m_tickleFds[0], dummy, sizeof(dummy)) > 0);
                continue;
            }
            // other events
            FdContext *fd_ctx = (FdContext *)event.data.ptr;
            std::lock_guard<std::mutex> lock(fd_ctx->mutex);
            ...
            // 事件只保留读和写类型
            int real_events = NONE;
            if (event.events & EPOLLIN) 
            {
                real_events |= READ;
            }
            if (event.events & EPOLLOUT) 
            {
                real_events |= WRITE;
            }
            ...
            // 根据类型触发相应的事件回调处理
            if (real_events & READ) 
            {
                fd_ctx->triggerEvent(READ);
                --m_pendingEventCount;
            }
            if (real_events & WRITE) 
            {
                fd_ctx->triggerEvent(WRITE);
                --m_pendingEventCount;
            }
        } // end for

        Fiber::GetThis()->yield();
    } // end while(true)
}
```

## 7. 定时器说明

定时器通过`std::set`来模拟最小堆，`set`管理的类重载了`operator()`，从小到大，即第一个元素最小，`begin()`当做堆顶元素（最小）。
* `getNextTimer()` 返回堆中最近的超时时间，还有多少`ms`到期（set里第一个成员时间最小，最先到期）。
* `listExpiredCb` 取出所有超时定时器的回调函数
    * 如果定时器支持循环利用，则重置超时时间后重新加入到管理器中；
    * 否则超时的定时器会从`m_timers`（`std::set`模拟的堆）中移除。

```cpp
// coroutine-lib/fiber_lib/5iomanager/timer.h
class TimerManager 
{
    // 声明 Timer 是 TimerManager 的友元（Timer 可以访问 TimerManager 的私有成员）
    friend class Timer;
public:
    TimerManager();
    virtual ~TimerManager();
    ...
    // 添加timer
    std::shared_ptr<Timer> addTimer(uint64_t ms, std::function<void()> cb, bool recurring = false);
    // 拿到堆中最近的超时时间
    uint64_t getNextTimer();
    // 取出所有超时定时器的回调函数
    void listExpiredCb(std::vector<std::function<void()>>& cbs);
    ...
protected:
    ...
    // 添加timer
    void addTimer(std::shared_ptr<Timer> timer);
private:
    ...
    // 时间堆。根据超时时间由小到大排序
    // 此处用set模拟堆，begin作为堆顶（最小堆，堆顶是最小元素）。而没有用std::priority_queue优先级队列
    std::set<std::shared_ptr<Timer>, Timer::Comparator> m_timers;
    ...
};

class Timer : public std::enable_shared_from_this<Timer> 
{
    // 声明 TimerManager 是 Timer 的友元（TimerManager 可以访问 Timer 的私有成员）
    friend class TimerManager;
    ...
private:
    // 此处构造定义为了私有，可通过友元类（friend）TimerManager来访问
    Timer(uint64_t ms, std::function<void()> cb, bool recurring, TimerManager* manager);
private:
    ...
    // 超时时触发的回调函数
    std::function<void()> m_cb;
    ...
private:
    // 实现最小堆的比较函数
    struct Comparator 
    {
        // 实现中是由小到大：lhs->m_next < rhs->m_next。默认情况就是`std::less`，也是从小到大升序排序。
        bool operator()(const std::shared_ptr<Timer>& lhs, const std::shared_ptr<Timer>& rhs) const;
    };
};
```

`TimerManager`声明为了`Timer`的`friend`类，才能使用到`Timer`类的私有构造类：

```cpp
// coroutine-lib/fiber_lib/5iomanager/timer.cpp
std::shared_ptr<Timer> TimerManager::addTimer(uint64_t ms, std::function<void()> cb, bool recurring) 
{
    std::shared_ptr<Timer> timer(new Timer(ms, cb, recurring, this));
    addTimer(timer);
    return timer;
}
```

## 8. 小结

梳理sylar中结合epoll和定时器之后的协程调度逻辑。限于篇幅，标准库和系统API hook的梳理还是作为下篇单独梳理。

## 9. 参考

* [coroutine-lib](https://github.com/youngyangyang04/coroutine-lib)
* [sylar -- IO协程调度模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10061031)
* [sylar -- 定时器模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=16417216)
