---
title: 协程梳理实践（四） -- sylar协程API hook封装
description: 梳理sylar协程对标准库和系统API的hook封装
categories: [并发与异步编程]
tags: [协程, 异步编程]
---


## 1. 引言

梳理sylar协程对标准库和系统API的hook封装。

相关参考：
* [sylar -- hook模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=16417219)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. hook介绍和示例

**hook**实际上就是对系统接口的封装，提供和原始接口一样的函数签名，让使用者在调用时跟调用原始系统接口没有什么差别，但实际上是执行hook接口中的逻辑，可以实现自定义操作+原始接口操作。

sylar中的hook，就是为了在**不重写**代码的情况下，把原有代码中的同步socket操作api都转换为**异步操作**，以提升性能。

hook使用场景示例：**单个线程中**，3个协程分别在默认情况和hook系统api情况下的表现
* 协程1：`sleep(2)`；
* 协程2：在socket fd1 上`send` 100k数据；
* 协程3：在socket fd2 上`recv`数据直到成功

![sylar-coroutine-hook](/images/sylar-coroutine-hook.svg)

* 1、默认情况下，单个线程中的3个协程需要串行。`sleep`期间其他协程无法`resume`运行，`recv`阻塞等待数据发送期间，其他协程也无法运行
* 2、hook情况下，对`sleep`、`send`、`recv`接口进行hook，分别用上节中的**定时器**和**IOManager epoll**，在定时器到期或有io事件时才执行相应回调函数，可以避免无意义的阻塞，让CPU时间片运行在有意义的操作上

## 3. hook实现方式

hook实现有多种方式：**动态链接**、**静态链接**，还有**内核模块**的hook。本篇中基于参考链接，也仅说明动态链接的hook方式。

作为理解hook实现的基础，先看下链接顺序、符号冲突相关的几个小实验，可了解：[关于链接与装载的几个测试代码](https://www.midlane.top/wiki/pages/viewpage.action?pageId=16418206)，代码可见：[compile](https://github.com/xiaodongQ/prog-playground/tree/main/compile)。此处只放一下结论。

* 1、（未定义符号提前解决）无论动态链接还是静态链接，链接时都是**从左到右**扫描库文件。扫描时如果发现所有**未定义符号**都解决了，则后面的库就**不会再继续扫描**。
    * 对应上面链接中的 测试1 和 测试4。
    * 只是不用扫描这部分符号，不是说不加载了，比如用户在链接libc库前链接指定库，库中实现了`read/write`，而libc中也有这些接口，但因为是基础的运行时库，还是会加载的。
* 2、（符号冲突）从左到右扫描过程中，如果发现**优先级相同**的符号出现了2次，则：
    * 2.1、`动态扫描`不会报错，而是以**第一次**加载的符号为准。因为动态链接器在加载动态库时，会维护一份**所有对象共享**的**全局符号表**，符号加入全局符号表时若发现相同符号已存在，则会忽略后加入的符号（可称作**全局符号介入**）。（测试5）
    * 2.2、`静态扫描`会报**重复定义错误**，因为静态库中没有全局符号表的介入。（测试2）

基于动态链接进行hook，也有2种方式：

* 1、外挂式hook，也称**非侵入式hook**，不需要重新编译代码。通过**优先加载自定义动态库**来实现对后面动态库的hook。（对应上面结论中的`2.1`，实验demo可见参考链接）
    * 方式：实现和库函数签名相同的接口（如libc的`write`），编译为动态库，并在运行时通过`LD_PRELOAD`指定优先加载：`LD_PRELOAD="./libhook.so" ./a.out`。
    * 比如之前在 [并发与异步编程（三） -- 性能分析工具：gperftools和火焰图](https://xiaodongq.github.io/2025/03/14/async-io-example-profile) 中提及的`gperftools`工具，就可以通过`LD_PRELOAD`指定`tcmalloc`库来采集内存相关的统计。
* 2、**侵入式hook**，需要**改造代码**或者**重新编译**一次，以指定动态库的加载顺序。
    * 改造代码方式：在代码里（比如`main.c`）直接实现相同签名的函数
    * 重新编译方式：编译时将自定义库放在libc之前链接，如`gcc main.c -L. -lhook -Wl,-rpath=.`（libc库默认链接顺序总是在最后），以实现**全局符号介入**。

## 4. 小结


## 5. 参考

* [coroutine-lib](https://github.com/youngyangyang04/coroutine-lib)
* [sylar -- hook模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=16417219)
