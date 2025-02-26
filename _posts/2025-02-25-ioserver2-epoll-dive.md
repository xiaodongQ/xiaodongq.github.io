---
layout: post
title: ioserver服务实验（二） -- 深入学习epoll原理
categories: 网络
tags: C++ 网络
---

* content
{:toc}

基于ioserver demo项目，梳理学习epoll原理。



## 1. 背景

基于C++实现的读写服务demo，借此作为场景温习并深入学习io多路复用、性能调试、MySQL/Redis等开源组件。

本篇先看理论，后续再进行运行调试。梳理demo里面的几个io多路复用实现，并比较 [muduo](https://github.com/chenshuo/muduo)网络库、nginx 中的epoll使用进行学习，而后了解内核中的的epoll实现。

参考：

* [深入揭秘 epoll 是如何实现 IO 多路复用的](https://mp.weixin.qq.com/s/OmRdUgO1guMX76EdZn11UQ)
* [muduo源码](https://github.com/chenshuo/muduo)

结合之前 [TCP半连接全连接（一） -- 全连接队列相关过程](https://xiaodongq.github.io/2024/05/18/tcp_connect/#6-%E6%BA%90%E7%A0%81%E4%B8%AD%E5%90%84%E9%98%B6%E6%AE%B5%E7%AE%80%E8%A6%81%E6%B5%81%E7%A8%8B) 里梳理走读的[内核](https://github.com/xiaodongQ/linux-5.10.10)相关结构定义和流程，加深印象和理解。

## 2. epoll一般使用流程

`epoll` api的一般使用流程：

```cpp
// 1、使用epoll_create1创建 epoll 实例
int epoll_fd = epoll_create1(0);

// 2、添加监控文件描述符到 epoll 实例。假设已有 listenfd 进行了监听
struct epoll_event event; 
// 指定监听读事件
event.events = EPOLLIN;
event.data.fd = listenfd;
epoll_ctl(epoll_fd, EPOLL_CTL_ADD, fd, &event);

// 3、等待事件发生
struct epoll_event events[10];  // 用于存储发生事件的文件描述符信息，此处最大监听10个事件
int num_events = epoll_wait(epoll_fd, events, 10, 1000);  // 等待epoll实例上的事件发生，最多等待1000毫秒（1秒）
// 返回值num_events表示发生了多少个事件，events数组会存储这些事件信息
if (num_events == -1) {
    // 出现错误
} else if (num_events == 0) {
    // 超时时间内没有事件发生
} else {
    // 有事件发生，遍历events数组处理事件
    for (int i = 0; i < num_events; i++) {
        int fd = events[i].data.fd;
        if (fd == listenfd) {
            // 处理新的连接请求
            // 然后通过epoll_ctl把新的连接文件描述符fd也添加到epoll实例中，进行 EPOLLIN | EPOLLOUT 监听
        } else {
            if (events[i].events & EPOLLIN) {
                // 读事件发生
            } else if (events[i].events & EPOLLOUT) {
                // 写事件发生
            } else {
                // 其他事件发生
            }
            // 关闭之前添加到epoll中的文件描述符fd
            close(fd);
        }
    }
}

// 4、使用完epoll实例后，关闭epoll实例和之前添加到epoll中的文件描述符fd
// 关闭epoll实例
close(epoll_fd);
// 关闭之前添加到epoll中的文件描述符
close(listenfd);
```

## 3. demo中epoll使用流程走读

项目代码：[ioserver_demo](https://github.com/xiaodongQ/prog-playground/tree/main/ioserver_demo)

再来看下demo里的实现。

### 3.1. 抽象类定义

1、抽象类定义，还是比较优雅的：

```cpp
// include/io_multiplexing.h
// IO多路复用接口抽象类
class IOMultiplexing {
public:
    virtual ~IOMultiplexing() = default;
    
    // 添加监听事件
    virtual bool addEvent(int fd, EventType type) = 0;
    
    // 移除监听事件
    virtual bool removeEvent(int fd, EventType type) = 0;
    
    // 修改监听事件
    virtual bool modifyEvent(int fd, EventType type) = 0;
    
    // 等待事件发生
    virtual int wait(std::vector<Event>& events, int timeout = -1) = 0;
};

// Epoll实现
class EpollIO : public IOMultiplexing {
private:
    int epollfd_;
    std::vector<epoll_event> events_;
    
public:
    EpollIO(int max_events = 1024);
    ~EpollIO() override;
    
    bool addEvent(int fd, EventType type) override;
    bool removeEvent(int fd, EventType type) override;
    bool modifyEvent(int fd, EventType type) override;
    int wait(std::vector<Event>& events, int timeout = -1) override;
};
```

构造时就用`epoll_create1`创建了`epoll`句柄，并初始化了vector容量：

```cpp
// include/io_multiplexing.cpp
EpollIO::EpollIO(int max_events) : events_(max_events) {
    epollfd_ = epoll_create1(0);
    if (epollfd_ < 0) {
        throw std::runtime_error("epoll_create1 failed");
    }
}
```

### 3.2. epoll api调用

1、基本`socket` api创建socket并监听，实例化`EpollIO`类：`io_ = std::make_unique<io::EpollIO>();`

```cpp
// src/server/server.cpp
class Server {
    bool init(const std::string& config_path) {
        ...
        // 创建服务器socket
        serverfd_ = socket(AF_INET, SOCK_STREAM, 0);
        if (serverfd_ < 0) {xxx}
        
        // 设置socket选项
        int opt = 1;
        if (setsockopt(serverfd_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {xxx}

        // 绑定地址
        struct sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(port_);
        if (bind(serverfd_, (struct sockaddr*)&addr, sizeof(addr)) < 0) {xxx}

        // 监听连接
        if (listen(serverfd_, SOMAXCONN) < 0) {xxx}

        // 设置为非阻塞模式
        if (!setNonBlocking(serverfd_)) {xxx}
        ...

        // 创建IO多路复用对象
        io_ = std::make_unique<io::EpollIO>();
        // 添加 listen fd 到监控列表
        io_->addEvent(serverfd_, io::EventType::READ);
        ...
    }
    ...
};
```

上述`addEvent`中封装了`epoll_ctl`接口：

```cpp
// src/server/io_multiplexing.cpp
bool EpollIO::addEvent(int fd, EventType type) {
    if (fd < 0) return false;
    
    epoll_event ev{};
    ev.data.fd = fd;
    
    // 传入时可以指定多个事件，如 EventType::READ | EventType::WRITE
    if (static_cast<int>(type) & static_cast<int>(EventType::READ))
        ev.events |= EPOLLIN;
    if (static_cast<int>(type) & static_cast<int>(EventType::WRITE))
        ev.events |= EPOLLOUT;
    if (static_cast<int>(type) & static_cast<int>(EventType::ERROR))
        ev.events |= EPOLLERR;
    
    return epoll_ctl(epollfd_, EPOLL_CTL_ADD, fd, &ev) == 0;
}
```

2、主循环中，`int nfds = io_->wait(events, 1000);`进行`epoll_wait`等待

1）如果是监听句柄，则调用`handleNewConnection`处理新连接。

* 其中会`accept`接收新连接 -> 设置非阻塞 -> 调用`io_->addEvent`将新连接句柄加入监控列表

2）如果是客户端句柄，则将请求加入线程池处理。此处捕获当前对象指针并传入客户端fd

* `handleClient`处理中，进行`recv`接收数据、解析json、Redis和MySQL操作，并发送响应、关闭连接
* 此处：客户端句柄的`close`关闭和是否`epoll_ctl`移除，还需要进一步考虑

```cpp
class Server {
    void run() {
        logger_->info("Server started on port " + std::to_string(port_));

        // 主事件循环
        while (running) {
            std::vector<io::Event> events;
            int nfds = io_->wait(events, 1000); // 1秒超时

            if (nfds < 0) {
                if (errno == EINTR) continue;
                logger_->error("IO wait error");
                break;
            }

            for (const auto& event : events) {
                if (event.fd == serverfd_) {
                    handleNewConnection();
                } else {
                    // 将客户端请求加入线程池
                    threadPool_.enqueue([this, fd = event.fd] {
                        handleClient(fd);
                    });
                }
            }
        }

        cleanup();
    }
}
```

`io_->wait`中对应的epoll override实现：

```cpp
// src/server/io_multiplexing.cpp
int EpollIO::wait(std::vector<Event>& events, int timeout) {
    int ret = epoll_wait(epollfd_, events_.data(), events_.size(), timeout);
    if (ret < 0) return -1;
    
    events.clear();
    for (int i = 0; i < ret; ++i) {
        // 初始化暂时用读事件，下面根据实际调整，如果仅是写事件触发，不会多出读？
        Event event{events_[i].data.fd, EventType::READ, nullptr};
        if (events_[i].events & EPOLLIN)
            event.type = EventType::READ;
        else if (events_[i].events & EPOLLOUT)
            event.type = EventType::WRITE;
        else if (events_[i].events & EPOLLERR)
            event.type = EventType::ERROR;
        events.push_back(event);
    }
    
    return ret;
}
```

## 4. muduo网络库中的epoll

## 5. nginx中的epoll

## 6. 小结


## 7. 参考

* [深入揭秘 epoll 是如何实现 IO 多路复用的](https://mp.weixin.qq.com/s/OmRdUgO1guMX76EdZn11UQ)
* [muduo源码](https://github.com/chenshuo/muduo)
