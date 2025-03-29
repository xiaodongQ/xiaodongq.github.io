---
layout: post
title: DeepSeek 3FS学习实践（一） -- 事件循环
categories: 存储
tags: 3FS 存储
---

* content
{:toc}

本篇梳理3FS中的事件循环实现流程。



## 1. 背景

clone了一下 [DeepSeek 3FS](https://github.com/deepseek-ai/3FS) 仓库，看了部分的 [设计文档](https://github.com/deepseek-ai/3FS/blob/main/docs/design_notes.md) 和代码，有很多值得学习的内容。

看到蚂蚁存储团队梳理的3FS文章也特别好，可参考学习：

* [DeepSeek 3FS解读与源码分析（1）：高效训练之道](https://mp.weixin.qq.com/s/JbC4YiEj1u1BrBejmiytsA)
* [Deepseek 3FS解读与源码分析（2）：网络通信模块分析](https://mp.weixin.qq.com/s/qzeUL4tqXOBctOOllFqL7A)
* [DeepSeek 3FS解读与源码分析（3）：Storage模块解读](https://mp.weixin.qq.com/s/K8Wn0cop742sxfSdWB5wPg)
* [DeepSeek 3FS解读与源码分析（4）：Meta Service解读](https://mp.weixin.qq.com/s/urzArREaN7wj8UZ9Tx3FKA)
* [DeepSeek 3FS解读与源码分析（5）：客户端解读](https://mp.weixin.qq.com/s/sPkqOdVA3qBAUiMQltveoQ)

本篇先梳理其中的事件循环实现流程。

## 2. 3FS简要介绍

3FS是幻方AI自研的高速文件系统，是幻方“萤火二号”计算存储分离后，存储服务中的重要一环，全称是萤火文件系统（Fire-Flyer File System），因为有三个连续的 F，念起来不是很容易，因此被简称为 3FS。

3FS 是一个比较特殊的文件系统，因为它几乎只用在AI训练时**计算节点中的模型批量读取样本数据这个场景上**，通过高速的计算存储交互加快模型训练。这是一个大规模的随机读取任务，而且读上来的数据不会在短时间内再次被用到，因此我们无法使用 **“读取缓存”** 这一最重要的工具来优化文件读取，即使是 **超前读取** 也是毫无用武之地。 因此，3FS的实现也和其他文件系统有着比较大的区别。

参考幻方的博客说明：[幻方力量 -- 高速文件系统 3FS](https://www.high-flyer.cn/blog/3fs/)

## 3. 事件循环流程

事件循环基于`epoll`实现，其实现在 `3FS/src/common/net/EventLoop.h` 中，包含`EventLoop`事件循环类定义和一个`EventLoop`池：`EventLoopPool`

3FS中使用`Folly`库的协程将IO异步化，[Folly](https://github.com/facebook/folly)（Facebook Open Source Library）库由Facebook开源，基于C++17（3FS中用的Folly子模块是C++14版本），包含一系列实用工具和数据结构。本篇仅涉及Folly库的无界队列。

### 3.1. 类定义说明

`EventLoop`类定义如下：

```cpp
// 3FS/src/common/net/EventLoop.h
class EventLoop : public hf3fs::enable_shared_from_this<EventLoop> {
  struct HandlerWrapper;

 protected:
  EventLoop() = default;

 public:
  ~EventLoop() { stopAndJoin(); }

  // start and stop.
  Result<Void> start(const std::string &threadName = "EventLoop");
  Result<Void> wakeUp();
  void stopAndJoin();

  // 定义抽象类，具体任务需要实现该类
  class EventHandler {
   public:
    virtual ~EventHandler() = default;
    // socket fd
    virtual int fd() const = 0;
    // 事件处理函数，根据传入的事件类型，由实现类具体处理
    virtual void handleEvents(uint32_t epollEvents) = 0;

   protected:
    friend class EventLoop;
    std::weak_ptr<EventLoop> eventLoop_;
    std::list<HandlerWrapper>::iterator it_;
  };

  // add a event handler with interest events into event loop.
  Result<Void> add(const std::shared_ptr<EventHandler> &handler, uint32_t interestEvents);

  // remove a event handler from event loop.
  Result<Void> remove(EventHandler *handler);

 private:
  struct HandlerWrapper {
    std::weak_ptr<EventHandler> handler;
  };

  // 事件循环
  void loop();

 private:
  // epoll句柄
  FdWrapper epfd_;
  // 用于通知事件循环是否开始，向其write一个uint64_t数字
  FdWrapper eventfd_;

  std::atomic<bool> stop_{false};
  // 用于epoll_wait等待事件的线程
  // std::jthread，c++20引入，相对于std::thread，不用手动join
  std::jthread thread_;

  std::mutex mutex_;
  // 任务列表，里面是一个可调用对象的weak_ptr，避免shared_ptr循环引用
  std::list<HandlerWrapper> wrapperList_;

  // wake up the event loop to do deletion if the size of delete queue greater than this threshold.
  constexpr static size_t kDeleteQueueWakeUpLoopThreshold = 128u;
  // deletion of the wrapper object is done in the loop thread.
  // folly库提供的无界队列，多生产者单消费者，Unbounded Multi Producers Single Consumers
  folly::UMPSCQueue<std::list<HandlerWrapper>::iterator, true> deleteQueue_;
};
```

`EventLoopPool`定义：

```cpp
// 3FS/src/common/net/EventLoop.h
class EventLoopPool {
 public:
  EventLoopPool(size_t numThreads);

  // start and stop.
  Result<Void> start(const std::string &threadName);
  void stopAndJoin();

  // add a event handler with interest events into event loop.
  Result<Void> add(const std::shared_ptr<EventLoop::EventHandler> &handler, uint32_t interestEvents);

 private:
  std::vector<std::shared_ptr<EventLoop>> eventLoops_;
};
```

### 3.2. epoll初始化

流程：

1. `epoll_create`创建epoll句柄
    * 参数只要`>0`即可，Linux 2.6.8之前用于定义最大文件描述符数量，后续弃用了，为了兼容性还是传入一个`>0`的值。
2. `eventfd`创建一个fd句柄，可用于事件通知，此处用来通知事件循环是否启动，即`wakeUp`成员函数中write一个数字
    * 创建时指定`NONBLOCK`
3. `epoll_ctl`注册输入事件，此处是`EPOLLET`边缘触发模式，只是write和read一个`uint64_t`数据用于简单控制，下面的loop里会循环读取
4. `std::jthread`创建后台线程，在线程中（`EventLoop::loop`）负责 `epoll_wait`
    * c++20引入jthread，相对于std::thread，不用手动join，析构时会自行join管理线程的生命周期，且支持中断线程

```cpp
// 3FS/src/common/net/EventLoop.cc
Result<Void> EventLoop::start(const std::string &threadName) {
  // 1. init epoll fd.
  epfd_ = ::epoll_create(16_KB);
  if (UNLIKELY(!epfd_.valid())) {
    XLOGF(ERR, "create epoll failed");
    return makeError(RPCCode::kEpollInitError, "create epoll failed");
  }

  // 2. init event fd for notify.
  eventfd_ = ::eventfd(0, EFD_NONBLOCK);
  if (UNLIKELY(!eventfd_.valid())) {
    XLOGF(ERR, "create eventfd failed");
    return makeError(RPCCode::kEpollInitError, "create eventfd failed");
  }

  // 3. add event fd into epoll.
  // eventfd_ 没有初始化私有数据，仅用作loop里简单通知
  struct epoll_event evt = {EPOLLIN | EPOLLET, {nullptr}};
  int ret = ::epoll_ctl(epfd_, EPOLL_CTL_ADD, eventfd_, &evt);
  if (UNLIKELY(ret == -1)) {
    auto msg = fmt::format("add eventfd into epoll failed, epoll {}, eventfd {}, errno {}", epfd_, eventfd_, errno);
    XLOG(ERR, msg);
    return makeError(RPCCode::kEpollAddError, std::move(msg));
  }

  // 4. start loop in background thread.
  thread_ = std::jthread(&EventLoop::loop, this);
  folly::setThreadName(thread_.get_id(), threadName);
  return Void{};
}
```

上面的`eventfd_`，通过`write`一个`uint64_t`进行事件通知：

```cpp
Result<Void> EventLoop::wakeUp() {
  uint64_t val = 1;
  int ret = ::write(eventfd_, &val, sizeof(val));
  if (ret == -1) {
    auto msg = fmt::format("wake up epoll loop failed, eventfd {}, errno {}", eventfd_, errno);
    XLOG(ERR, msg);
    return makeError(RPCCode::kEpollWakeUpError, std::move(msg));
  }
  return Void{};
}
```

### 3.3. 注册事件

`EventLoopPool::add`负责注册感兴趣事件，`EventHandler`定义了一个抽象类，具体的任务需要实现该类的接口。

该函数中，除了将fd和相应回调注册到epoll中，还会把任务（HandlerWrapper包装的`weak_ptr<EventHandler>`）记录到`wrapperList_`队列里。

```cpp
// 3FS/src/common/net/EventLoop.cc
Result<Void> EventLoop::add(const std::shared_ptr<EventHandler> &handler, uint32_t interestEvents) {
  HandlerWrapper *wrapper = nullptr;
  {
    auto lock = std::unique_lock(mutex_);
    // HandlerWrapper用weak_ptr包装一个可调用对象（任务）：`weak_ptr<EventHandler>`，避免shared_ptr循环引用问题
    wrapperList_.emplace_front(HandlerWrapper{handler});
    // handler中it_指向本次插入的列表元素
    handler->it_ = wrapperList_.begin();
    // 获取当前EventLoop对象的 weak_ptr
    handler->eventLoop_ = weak_from_this();
    wrapper = &wrapperList_.front();
  }

  struct epoll_event event;
  event.events = interestEvents;
  // 包装后的可调用对象作为注册事件的私有数据，用于后续触发事件时处理
  event.data.ptr = wrapper;
  // 注册fd及对应私有数据
  int ret = ::epoll_ctl(epfd_, EPOLL_CTL_ADD, handler->fd(), &event);
  if (ret == 0) {
    // 成功则返回
    return Void{};
  }

  // 注册失败才走到这里，回退之前添加的任务
  // remove from list if fail to add.
  {
    auto lock = std::unique_lock(mutex_);
    wrapperList_.erase(handler->it_);
  }
  handler->it_ = std::list<HandlerWrapper>::iterator{};
  handler->eventLoop_.reset();
  auto msg = fmt::format("add fd into epoll failed, epoll {}, fd {}, errno {}", epfd_, handler->fd(), errno);
  XLOG(ERR, msg);
  return makeError(RPCCode::kEpollAddError, std::move(msg));
}
```

`EventHandler`抽象类：

```cpp
// 3FS/src/common/net/EventLoop.cc
// 定义抽象类，具体任务需要实现该类
class EventHandler {
  public:
  virtual ~EventHandler() = default;
  // socket fd
  virtual int fd() const = 0;
  // 事件处理函数，根据传入的事件类型，由实现类具体处理
  virtual void handleEvents(uint32_t epollEvents) = 0;

  protected:
  friend class EventLoop;
  std::weak_ptr<EventLoop> eventLoop_;
  std::list<HandlerWrapper>::iterator it_;
};
```

### 3.4. 移除注册的fd事件

`epoll_ctl`进行`EPOLL_CTL_DEL`移除fd，并将fd对应的任务入队到`待删除队列`，队列数超过128则`wakeUp`通知loop中处理。

```cpp
// 3FS/src/common/net/EventLoop.cc
Result<Void> EventLoop::remove(EventHandler *handler) {
  if (handler->it_ == std::list<HandlerWrapper>::iterator{}) {
    XLOGF(DBG, "try to remove a invalid event handler, epoll {}, fd {}", epfd_, handler->fd());
    return Void{};
  }

  int ret = ::epoll_ctl(epfd_, EPOLL_CTL_DEL, handler->fd(), nullptr);
  if (ret == -1) {
    auto msg = fmt::format("remove fd from epoll failed, epoll {}, fd {}, errno {}", epfd_, handler->fd(), errno);
    XLOG(ERR, msg);
    return makeError(RPCCode::kEpollDelError, std::move(msg));
  }

  // 入队到待删除队列
  deleteQueue_.enqueue(handler->it_);
  handler->it_ = std::list<HandlerWrapper>::iterator{};

  // wake up event loop if size of delete queue is greater than threshold.
  if (deleteQueue_.size() >= kDeleteQueueWakeUpLoopThreshold) {
    wakeUp();
  }
  return Void{};
}
```

### 3.5. loop处理：epoll_wait等待事件

在上述`std::jthread`创建的线程里负责`epoll_wait`。

* eventfd_注册时设置`边缘触发`模式，所以用while进行read
* 关于其中用到的无界队列，下面小节单独说明

```cpp
// 3FS/src/common/net/EventLoop.cc
void EventLoop::loop() {
  XLOGF(INFO, "EventLoop::loop() started.");

  while (true) {
    // 1. wait events.
    constexpr int kMaxEvents = 64;
    struct epoll_event events[kMaxEvents];
    int n = ::epoll_wait(epfd_, events, kMaxEvents, -1);
    if (n == -1) {
      XLOGF(ERR, "epoll_wait failed, errno {}, retry", errno);
      continue;
    }
    if (stop_) {
      break;
    }

    // 2. handle events.
    for (int i = 0; i < n; ++i) {
      auto &evt = events[i];
      // 注册的 eventfd_ ，其注册时没设置ptr
      // 此处触发后，主要为了等for循环结束，进行第3步的 deleteQueue_ 队列处理
      if (evt.data.ptr == nullptr) {
        // waked up by event fd. read all.
        uint64_t val;
        // 边缘触发，所以此处循环read
        while (::read(eventfd_, &val, sizeof(val)) > 0) {
        }
        continue;
      }

      auto wrapper = reinterpret_cast<HandlerWrapper *>(evt.data.ptr);
      // weak_ptr的lock()，检查对象是否还存在，并获取一个shared_ptr
      if (auto handler = wrapper->handler.lock()) {
        // 实现类会实现具体处理，此处进行事件处理
        handler->handleEvents(evt.events);
      }
    }

    // 3. handle remove.
    if (!deleteQueue_.empty()) {
      auto lock = std::unique_lock(mutex_);
      std::list<HandlerWrapper>::iterator it;
      // limit the number of deletions in a single iteration.
      // 从 无界队列：任务删除队列 中移除任务，并从任务列表删除，此处控制每次处理数量
      for (auto i = 0ul; i < kDeleteQueueWakeUpLoopThreshold && deleteQueue_.try_dequeue(it); ++i) {
        wrapperList_.erase(it);
      }
    }
  }

  XLOGF(INFO, "EventLoop::loop() stopped.");
}
```

## 4. folly::UMPSCQueue介绍

Facebook开源的Folly中提供了很多高性能组件，此处说明下上面用到的`UMPSCQueue`无界队列，其中的模板、无锁编程等很值得学习参考。

`UMPSCQueue`其实是`UnboundedQueue`无界队列的模板别名，表示多生产者单消费者，此外还定义了`USPSCQueue`、`USPMCQueue`、`UMPMCQueue`等别名，各有应用场景。

```cpp
// 3FS/third_party/folly/folly/concurrency/UnboundedQueue.h
template <
    typename T,
    bool MayBlock,
    size_t LgSegmentSize = 8,
    size_t LgAlign = constexpr_log2(hardware_destructive_interference_size),
    template <typename> class Atom = std::atomic>
using UMPSCQueue =
    UnboundedQueue<T, false, true, MayBlock, LgSegmentSize, LgAlign, Atom>;
```

```cpp
/// Template Aliases:
///   USPSCQueue<T, MayBlock, LgSegmentSize, LgAlign>
///   UMPSCQueue<T, MayBlock, LgSegmentSize, LgAlign>
///   USPMCQueue<T, MayBlock, LgSegmentSize, LgAlign>
///   UMPMCQueue<T, MayBlock, LgSegmentSize, LgAlign>
```

看下 `UnboundedQueue`，其中使用原子操作实现了lock-free的无界队列，模板参数指定不同用法：

```cpp
template <
    typename T,
    bool SingleProducer,
    bool SingleConsumer,
    bool MayBlock,
    // 分段存储，每段最大2^8个列表项，可优化内存需要重新分配的场景
    size_t LgSegmentSize = 8,
    // 防止伪共享，此处cache line的以2为底的对数，64字节则此处为6
    size_t LgAlign = constexpr_log2(hardware_destructive_interference_size),
    // 原子操作，实现无锁队列操作
    template <typename> class Atom = std::atomic>
class UnboundedQueue {
  ...
};
```

上述`loop`中调用的`try_dequeue(it)`定义如下：

* 其中传入`std::chrono::steady_clock::time_point::min()`时间最小值，所以tryDequeueUntil会立即进行删除，无延迟
* `tryDequeueUntil`实现中，设计 **hazard pointers机制** 进行指针保护，防止队列操作时出现非预期的资源释放，导致悬垂指针

```cpp
// 3FS/third_party/folly/folly/concurrency/UnboundedQueue.h
  FOLLY_ALWAYS_INLINE bool try_dequeue(T& item) noexcept {
    auto o = try_dequeue();
    if (LIKELY(o.has_value())) {
      item = std::move(*o);
      return true;
    }
    return false;
  }

  FOLLY_ALWAYS_INLINE folly::Optional<T> try_dequeue() noexcept {
    return tryDequeueUntil(std::chrono::steady_clock::time_point::min());
  }
```

## 5. 小结

梳理了3FS中的事件循环流程，主要还是常规的epoll处理，其中涉及的一些细节值得参考。

了解了Folly库中的无界队列实现，其中也提供了很多其他组件，作为工业级开源库，后续可以深入学习实践。

## 6. 参考

* [幻方力量 -- 高速文件系统 3FS](https://www.high-flyer.cn/blog/3fs/)
* [DeepSeek 3FS](https://github.com/deepseek-ai/3FS) 源码
* [Deepseek 3FS解读与源码分析（2）：网络通信模块分析](https://mp.weixin.qq.com/s/qzeUL4tqXOBctOOllFqL7A)