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

### 3.1. 动态库hook方式

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

### 3.2. 获取默认接口的符号

动态链接时，因"全局符号介入"机制覆盖的默认接口还是需要的，除了自定义的操作部分，最终要实现的功能还是需要通过系统的默认接口来实现的。可通过`dlsym`接口获取默认接口的符号。
* 配合`dlopen`，还可以实现**插件化**的动态库加载，**程序库动态升级**也可以基于该机制实现。

`dlsym`（`dl`缩写对应：`dynamic linker`）接口声明如下，第一个参数是`dlopen`打开动态库返回的句柄。

```sh
dlsym(3)                      Library Functions Manual                   dlsym(3)

NAME
       dlsym, dlvsym - obtain address of a symbol in a shared object or executable
LIBRARY
       Dynamic linking library (libdl, -ldl)
SYNOPSIS
       #include <dlfcn.h>
       void *dlsym(void *restrict handle, const char *restrict symbol);
DESCRIPTION
       The  function  dlsym() takes a "handle" of a dynamic loaded shared object returned by
       dlopen(3) along with a null-terminated symbol name, and  returns  the  address  where
       that  symbol is loaded into memory. 
```

用法：使用`dlsym`找回被覆盖的符号时，第一个参数固定为 `RTLD_NEXT`，第二个参数为符号的名称

```cpp
typedef void* (*malloc_func_t)(size_t size);

// 函数指针用于保存libc中的malloc的地址
malloc_func_t sys_malloc_func = NULL;

// hook malloc，其中增加自定义的操作（此处仅打印）
// 这里重定义会导致libc中的同名符号被覆盖
void *malloc(size_t size) {
    // 先调用标准库里的malloc申请内存
    void *ptr = sys_malloc_func(size);
    fprintf(stderr, "malloc: ptr=%p, length=%ld\n", ptr, size);
    return ptr;
}

int main()
{
    // 通过dlsym找到标准库中的malloc的符号地址
    // 赋值给全局的函数指针，上述自定义malloc中会用到该函数指针
    sys_malloc_func = dlsym(RTLD_NEXT, "malloc");

    // 由于上述定义了和libc中malloc相同签名的函数，会使用上述自定义函数
    char *ptrs = malloc(100);
}
```

## 4. sylar中的hook模块

sylar中，只对socket的fd进行了hook，若不是socket则调用系统默认接口。
* 使用`FdManager`单例类管理所有分配过的fd上下文（用`FdCtx`类结构表示）。
* 并且其中的hook是针对**线程**为粒度，可对单个线程设置是否启用hook。

sylar中的hook模块中有三类接口需要hook：
* sleep延时系列接口
* socket io系列接口
* socket/fcntl/ioctl等，处理fd上下文，设置超时、非阻塞选项等

实现上，用前面所述的`dlsym`获取被hook接口的原始地址，sylar中定义了一个宏`HOOK_FUN`来简化操作。
* `extern "C"`空间中，对所有被hook函数定义了全局的函数指针变量，比如sleep函数：`sleep_fun sleep_f = nullptr;`
* `sylar`命名空间中，通过`dlsym`获取原始函数的符号地址给这些全局的函数指针赋值，比如：`sleep_f = (sleep_fun)dlsym(RTLD_NEXT, "sleep");`
* 头文件中，则定义了各个函数签名，比如`typedef unsigned int (*sleep_fun) (unsigned int seconds);`，并声明了一下和系统函数相同的函数，基于全局符号介入机制来覆盖系统默认函数，如`unsigned int sleep(unsigned int seconds);`

获取各默认接口的符号地址：

```cpp
// coroutine-lib/fiber_lib/6hook/hook.cpp
#define HOOK_FUN(XX) \
    XX(sleep) \
    XX(usleep) \
    XX(nanosleep) \
    XX(socket) \
    XX(connect) \
    XX(accept) \
    XX(read) \
    XX(readv) \
    XX(recv) \
    XX(recvfrom) \
    XX(recvmsg) \
    XX(write) \
    XX(writev) \
    XX(send) \
    XX(sendto) \
    XX(sendmsg) \
    XX(close) \
    XX(fcntl) \
    XX(ioctl) \
    XX(getsockopt) \
    XX(setsockopt) 

namespace sylar{

void hook_init()
{
    static bool is_inited = false;
    if(is_inited){
        return;
    }
    // test
    is_inited = true;

// 定义临时的`XX(name)`宏，`HOOK_FUN(XX)`则是对所有的系统接口都执行 `XX(接口名)`
// 以sleep接口展开为例，查看过程：
    // `XX(sleep)`展开即：sleep_f = (sleep_fun)dlsym(RTLD_NEXT, "sleep");
    // 定义了一个变量 `sleep_f`
#define XX(name) name ## _f = (name ## _fun)dlsym(RTLD_NEXT, #name);
    HOOK_FUN(XX)
#undef XX
}

struct HookIniter
{
    HookIniter()
    {
        hook_init();
    }
};

static HookIniter s_hook_initer;

} // end namespace sylar

// 不在sylar命名空间内，且以C方式定义函数符号
extern "C"{
// 定义临时的`XX(name)`宏，注意和上面不一样
// 以sleep接口为例，查看过程：
    // `XX(sleep)`展开即：sleep_fun sleep_f = nullptr;
    // 定义了一个全局变量`sleep_f`，其类型是 `sleep_fun`
#define XX(name) name ## _fun name ## _f = nullptr;
    HOOK_FUN(XX)
#undef XX
}
```

而各个`xxx_fun`的函数类型，则定义在`hook.h`中。

```cpp
// coroutine-lib/fiber_lib/6hook/hook.h
extern "C"
{
    // 1、对每个被hook的系统函数，定义跟其一样的签名
    typedef unsigned int (*sleep_fun) (unsigned int seconds);
    extern sleep_fun sleep_f;

    typedef int (*usleep_fun) (useconds_t usec);
    extern usleep_fun usleep_f;
    ...

    // 2、并定义各系统函数的hook函数
    unsigned int sleep(unsigned int seconds);
    int usleep(useconds_t usce);
    ...
}
```

以 `socket` 函数来看下hook的实现：
* `socket_f`是系统默认的函数地址
* （对于`sleep`，用的是定时器，并没有用系统默认的函数地址）

```cpp
// coroutine-lib/fiber_lib/6hook/hook.cpp
int socket(int domain, int type, int protocol)
{
    if(!sylar::t_hook_enable)
    {
        return socket_f(domain, type, protocol);
    }

    int fd = socket_f(domain, type, protocol);
    if(fd==-1)
    {
        std::cerr << "socket() failed:" << strerror(errno) << std::endl;
        return fd;
    }
    sylar::FdMgr::GetInstance()->get(fd, true);
    return fd;
}
```

## 5. 小结

介绍hook概念和实现方式，并简单梳理sylar中的hook模块实现。

## 6. 参考

* [coroutine-lib](https://github.com/youngyangyang04/coroutine-lib)
* [sylar -- hook模块](https://www.midlane.top/wiki/pages/viewpage.action?pageId=16417219)
