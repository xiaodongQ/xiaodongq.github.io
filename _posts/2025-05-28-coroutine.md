---
title: 实现一个简易协程
description: 梳理协程相关机制，并实践实现一个简易协程。
categories: [并发与异步编程]
tags: [协程, 异步编程]
---


## 1. 引言

[Ceph学习笔记（三） -- 对象存储](https://xiaodongq.github.io/2025/05/16/ceph-object-storage/) 中梳理`rgw`的`main`启动流程时，提到客户端请求管理类`RGWCompletionManager`基于**协程**实现。以及之前的多篇博客中留下了梳理协程的TODO项，本篇就来梳理下协程的机制原理，并基于开源项目进行实践。

相关参考：

* 代码随想录的协程库项目：[coroutine-lib](https://github.com/youngyangyang04/coroutine-lib)。并进行[fork](https://github.com/xiaodongQ/coroutine-lib)。
* [协程Part1-boost.Coroutine.md](https://www.cnblogs.com/pokpok/p/16932735.html)
    * 说明：[boost.coroutine](https://www.boost.org/doc/libs/latest/libs/coroutine/doc/html/coroutine/overview.html)已经被标记为`已过时（deprecated）`了，不过可以从中学习理解协程的基本原理，新的协程实现为 [boost.coroutine2](https://www.boost.org/doc/libs/latest/libs/coroutine2/doc/html/index.html)。
* [sylar开源项目 -- 协程模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=10060957)
* 以及在[RocksDB学习笔记（三） -- RocksDB中的一些特性设计和高性能相关机制](https://xiaodongq.github.io/2025/04/30/rocksdb-performance-mechanism/)中未展开的几篇协程相关参考文章
    * [实现一个简单的协程](https://www.bluepuni.com/archives/implements-coroutine/)
    * [从无栈协程，到 Asio 的协程实现](https://www.bluepuni.com/archives/stackless-coroutine-and-asio-coroutine/)
    * [从 C++20 协程，到 Asio 的协程适配](https://www.bluepuni.com/archives/cpp20-coroutine-and-asio-coroutine/)
* 协程库：
    * [boost.coroutine2](https://www.boost.org/doc/libs/latest/libs/coroutine2/doc/html/index.html)
    * [libco](https://github.com/Tencent/libco)，腾讯开源的协程栈，广泛用于微信中
    * [libgo](https://github.com/yyzybb537/libgo)，C++实现的Go风格协程库

## 2. 协程基础

`协程`是支持对执行进行`挂起（suspend，也称yield）`和`恢复（resume）`的程序。（[维基百科 -- Coroutine](https://en.wikipedia.org/wiki/Coroutine)）

也可称`协程`为 **轻量级线程** 或 **用户态线程**，协程的本质就是`函数`和`函数运⾏状态`的组合，**相对于函数**一旦调用就要从头执行直到退出，协程可以多次挂起和恢复。

* 协程退出/挂起的操作一般称为`yield`，此时的执行状态会被存储起来，称为**协程上下文**，协程上下文包括CPU寄存器状态、局部变量和栈帧状态等。
    * `yield`时只是暂时出让CPU，其他协程可以获得CPU并运行。
* 协程创建后，其运行和`yield`、`resume`完全**由应用程序控制**，不经过内核调度。相对而言，线程的`运行和调度`则需要内核进行控制。
* 协程的上下文切换开销
    * 在之前的 [CPU及内存调度（一） -- 进程、线程、系统调用、协程上下文切换](https://xiaodongq.github.io/2025/03/09/context-switch) 中对比过几种上下文切换的时机和开销，此处贴一下作为参考。依赖不同硬件，参考数量级即可。
    * 进程上下文切换：`2.7us到5.48us之间`
    * 线程上下文切换：`3.8us`左右
    * 系统调用：`200ns`
    * 协程切换：`120ns`（用户态）

**协程分类：**

* `对称协程（symmetric coroutine）` 和 `非对称协程（asymmetric coroutine）`
    * 对称协程：协程可以通过**协程调度器**不受限制地将**控制权/调度权**转移给任何其他协程
    * 非对称协程：协程间存在**调用方->被调用方**的关系，协程出让调度权的目标只能是它的调用者。
    * 在对称协程中，每个子协程除了运行自身逻辑，还要负责选出下一个合适的协程进行切换，即还要充当调度器的角色，所以**对称协程更灵活，但实现更为复杂**；非对称协程中则可借助专门的调度器来调度协程，只运行自己的入口函数。
* `有栈协程` 和 `无栈协程`
    * 有栈协程：用**独立的执行栈**保存上下文信息。
        * 有栈协程又区分`独立栈`和`共享栈`
        * 独立栈时协程的栈空间都是独立的，且大小固定；
        * 共享栈则是所有协程在`运行`时使用同一个栈空间，`resume`切换时需要将`yield`时保存的栈内容**拷贝**到运行时的栈空间。
    * 无栈协程：不需独立的执行栈，上下文信息放在公共内存
    * 调用栈示意，可了解：[有栈协程与无栈协程](https://mthli.xyz/stackful-stackless/)

## 3. 协程库实现结构

基于`sylar`中的协程库实现来学习协程栈的结构原理。

### 3.1. ucontext_t 用户上下文

其中的协程实现依赖 `ucontext_t`（user context）来保存和获取**用户上下文**，相关结构体定义和4个API如下，可通过`man`查看。

```c
// 头文件
#include <ucontext.h>

// 获取当前的上下⽂
int getcontext(ucontext_t *ucp);
// 恢复ucp指向的上下⽂，并跳转到ucp上下⽂对应的函数中执⾏
int setcontext(const ucontext_t *ucp);

// 修改ucp指向的上下文，将上下文与⼀个函数func进⾏绑定，并可指定函数参数
// 注意：调用本函数前，需要先创建栈空间，并赋值给ucp->uc_stack
    // 本函数不创建ucontext_t，而是只修改ucp对应的上下文，栈空间也是本函数之外先申请好的
void makecontext(ucontext_t *ucp, void (*func)(), int argc, ...);

// 保存当前上下文到oucp里，并激活ucp指向的上下文
int swapcontext(ucontext_t *restrict oucp,
                const ucontext_t *restrict ucp);

typedef struct ucontext_t {
    // 指向当前context结束后下一个将要resume恢复的context
    struct ucontext_t *uc_link;
    // 当前context中的信号屏蔽掩码
    sigset_t          uc_sigmask;
    // 当前context使用的栈空间
    stack_t           uc_stack;
    // 特定机器平台相关的上下文信息，包含调用线程的寄存器
    mcontext_t        uc_mcontext;
    ...
} ucontext_t;
```

`mcontext_t`相关定义：

```c
// x86
typedef struct
  {
    gregset_t __ctx(gregs);
    /* Note that fpregs is a pointer.  */
    fpregset_t __ctx(fpregs);
    __extension__ unsigned long long __reserved1 [8];
} mcontext_t;

// 相关寄存器
typedef struct _libc_fpstate *fpregset_t;
struct _libc_fpstate
{
  /* 64-bit FXSAVE format.  */
  __uint16_t		__ctx(cwd);
  __uint16_t		__ctx(swd);
  __uint16_t		__ctx(ftw);
  __uint16_t		__ctx(fop);
  __uint64_t		__ctx(rip);
  __uint64_t		__ctx(rdp);
  __uint32_t		__ctx(mxcsr);
  __uint32_t		__ctx(mxcr_mask);
  struct _libc_fpxreg	_st[8];
  struct _libc_xmmreg	_xmm[16];
  __uint32_t		__glibc_reserved1[24];
};
```

### 3.2. Fiber协程类定义

sylar里的协程实现是**非对称协程**，并且是**有栈协程**。且保证子协程不能创建新的协程，只和主协程进行相互切换。

下面是协程类定义：
* 协程状态简化为3种：就绪`READY`、运行`RUNNING`、结束`TERM`
* 协程栈默认128KB（Fiber带参构造中，不指定`stacksize`时，会申请`128000`字节空间作为协程栈）
* 操作：`yield()`挂起、`resume()`恢复；

```cpp
// fiber_lib/2fiber/fiber.h
// 协程类
class Fiber : public std::enable_shared_from_this<Fiber>
{
public:
    // 协程状态（简化为3种状态）
    enum State
    {
        READY,   // 就绪
        RUNNING, // 运行
        TERM     // 结束
    };

private:
    // 仅由GetThis()调用 -> 私有 -> 创建主协程  
    Fiber();

public:
    Fiber(std::function<void()> cb, size_t stacksize = 0, bool run_in_scheduler = true);
    ~Fiber();

    // 重用一个协程
    // 重复利⽤已结束的协程，复⽤其栈空间，创建新的协程
    void reset(std::function<void()> cb);

    // 当前协程恢复执行
    // 协程交换，当前协程变为 RUNNING，正在运行的协程变为 READY
    void resume();

    // 当前协程让出执行权
    // 协程交换，当前协程变为 READY，上次resume时保存的协程变为 RUNNING
    void yield();

    uint64_t getId() const {return m_id;}
    State getState() const {return m_state;}

public:
    // 设置当前运行的协程
    static void SetThis(Fiber *f);

    // 得到当前运行的协程 
    static std::shared_ptr<Fiber> GetThis();

    // 设置调度协程（默认为主协程）
    static void SetSchedulerFiber(Fiber* f);
    
    // 得到当前运行的协程id
    static uint64_t GetFiberId();

    // 协程函数
    static void MainFunc();

private:
    // id
    uint64_t m_id = 0;
    // 栈大小
    uint32_t m_stacksize = 0;
    // 协程状态
    State m_state = READY;
    // 协程上下文
    ucontext_t m_ctx;
    // 协程栈指针
    void* m_stack = nullptr;
    // 协程函数
    std::function<void()> m_cb;
    // 是否让出执行权交给调度协程
    bool m_runInScheduler;

public:
    std::mutex m_mutex;
};
```

此处的 `std::enable_shared_from_this` 模板类用法需要重点说明一下：

`std::enable_shared_from_this` 模板类允许通过 `shared_from_this()`成员函数来从当前实例获取`shared_ptr`智能指针。

1、使用场景：
* 当使用`shared_ptr`管理对象时，有时在对象内部还想获取对象自身的`shared_ptr`，比如成员函数将自身作为参数传递给其他函数，而该函数入参又是`std::shared_ptr`形式
* 此时若使用`this`创建`shared_ptr`，会导致有两个控制引用计数的控制块，引用计数为0时会出现double free的情况
* `std::enable_shared_from_this` 则可以和已有的`shared_ptr`共享所有权，即共享同一个控制块
* 典型应用场景：
    * 异步操作、回调、事件监听等场景下，需要确保在操作完成之前对象不会被销毁，如果传递this裸指针，则无法保证对象在回调时仍然存在。而通过 `shared_from_this()` 获得一个 `shared_ptr`，则增加了引用计数，从而保证了对象的生命周期至少持续到回调完成。

2、注意事项：
* 使用 `shared_from_this()`时，必须保证此前已经有 `std::shared_ptr` 拥有该对象了，否则是未定义行为
* 构造函数中不能使用`shared_from_this()`，因为还没有`shared_ptr`拥有该对象
* 栈上分配的对象不能使用`shared_from_this()`

3、原理：
* `std::enable_shared_from_this`内部有一个`std::weak_ptr`成员，其在第一个shared_ptr创建时被初始化；
* 并在`shared_from_this()`时，通过`weak_ptr`的`lock()`方法获取一个`shared_ptr`，它和已有的shared_ptr共享控制块

### 3.3. 协程类实现说明

上述协程类定义的成员函数不做一一展开，可见 [2fiber/fiber.cpp](https://github.com/xiaodongQ/coroutine-lib/blob/main/fiber_lib/2fiber/fiber.cpp) 中的注释说明。

通过`thread_local`线程局部变量定义每个线程中各协程共享的结构，包括线程中**当前运行的协程**、**主协程**、**调度协程**。`协程计数器`和`协程id`则用于全局统计和id分配。

```cpp
// fiber_lib/2fiber/fiber.cpp
// 下述几个线程局部变量，表示一个线程同时最多只能知道2个协程的上下文：主协程和当前运行协程（可能出现是同一个的时刻）
// 正在运行的协程（指针形式）
static thread_local Fiber* t_fiber = nullptr;
// 主协程（是一个智能指针）
static thread_local std::shared_ptr<Fiber> t_thread_fiber = nullptr;
// 调度协程（一般是主协程）
static thread_local Fiber* t_scheduler_fiber = nullptr;

// 协程计数器
static std::atomic<uint64_t> s_fiber_id{0};
// 协程id
static std::atomic<uint64_t> s_fiber_count{0};
```

带参构造函数：

```cpp
Fiber::Fiber(std::function<void()> cb, size_t stacksize, bool run_in_scheduler):
m_cb(cb), m_runInScheduler(run_in_scheduler)
{
    m_state = READY;

    // 分配协程栈空间
    // 未指定则默认栈空间 128KB
    m_stacksize = stacksize ? stacksize : 128000;
    // 析构时会free掉
    m_stack = malloc(m_stacksize);

    // 获取用户上下文，保存到本协程上下文中
    if(getcontext(&m_ctx))
    {
        std::cerr << "Fiber(std::function<void()> cb, size_t stacksize, bool run_in_scheduler) failed\n";
        pthread_exit(NULL);
    }
    
    m_ctx.uc_link = nullptr;
    m_ctx.uc_stack.ss_sp = m_stack;
    m_ctx.uc_stack.ss_size = m_stacksize;
    // 绑定协程上下文和其执行函数：Fiber::MainFunc
    makecontext(&m_ctx, &Fiber::MainFunc, 0);
    
    // 全局的协程id
    m_id = s_fiber_id++;
    // 全局的协程个数
    s_fiber_count ++;
    if(debug) std::cout << "Fiber(): child id = " << m_id << std::endl;
}
```

## 4. 小结


## 5. 参考


