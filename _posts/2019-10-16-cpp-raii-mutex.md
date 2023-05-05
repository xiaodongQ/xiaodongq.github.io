---
layout: post
title: C++中的RAII机制和互斥锁应用
categories: C/C++
tags: RAII mutex
---

* content
{:toc}

介绍RAII (Resource Acquisition Is Initialization) 资源获取即初始化，及其使用。



## RAII概念

参考：

* cppreference: [RAII](https://zh.cppreference.com/w/cpp/language/raii)

* [C++11实现模板化(通用化)RAII机制](https://blog.csdn.net/10km/article/details/49847271)

RAII(Resource Acquisition Is Initialization)，，是C++语言的一种管理资源、避免泄漏的机制，它将必须在使用前请求的资源（分配的堆内存、执行线程、打开的套接字、打开的文件、锁定的互斥体、磁盘空间、数据库连接等——任何存在受限供给中的事物）的生命周期绑定与一个对象的生存期相绑定。

C++标准保证任何情况下，已构造的对象最终会销毁，即它的析构函数最终会被调用。

根据 RAII 对象的生存期在退出作用域时结束这一基本状况，此技术的另一名称是*作用域界定的资源管理*（ Scope-Bound Resource Management，SBRM）。


RAII 可总结如下:

* 将每个资源封装入一个类，其中
    - 构造函数请求资源，并建立所有类不变式，或在它无法完成时抛出异常，
    - 析构函数释放资源并决不抛出异常；
* 始终经由 RAII 类的实例使用满足要求的资源，该资源
    - 自身拥有自动存储期或临时生存期，或
    - 具有与自动或临时对象的生存期绑定的生存期

拥有 open()/close()、lock()/unlock()，或 init()/copyFrom()/destroy() 成员函数的类是非 RAII 类的典型的例子：

### 用途

```cpp
std::mutex m;

void bad()
{
    m.lock();                    // 请求互斥体
    f();                         // 若 f() 抛异常，则互斥体永远不被释放
    if(!everything_ok()) return; // 提早返回，互斥体永远不被释放
    m.unlock();                  // 若 bad() 抵达此语句，互斥才被释放
}

void good()
{
    std::lock_guard<std::mutex> lk(m); // RAII类：互斥体的请求即是初始化
    f();                               // 若 f() 抛异常，则释放互斥体
    if(!everything_ok()) return;       // 提早返回，互斥体被释放
}                                      // 若 good() 正常返回，则释放互斥体
```

### C++标准库中RAII的体现

C++ 标准库：

遵循 RAII 管理其自身的资源：

* std::string、std::vector、std::thread，以及多数其他类在构造函数中获取其资源（错误时抛出异常），并在其析构函数中释放之（决不抛出），而不要求显式清理。

另外，标准库提供几种 RAII 包装器以管理用户提供的资源：

* std::unique_ptr 及 std::shared_ptr 用于管理动态分配的内存，或以用户提供的删除器管理任何以普通指针表示的资源；
* std::lock_guard、std::unique_lock、std::shared_lock 用于管理互斥体。

### 不适用场景

> RAII 不适用于并非在使用前请求的资源：CPU 时间、核心，以及缓存容量、熵池容量、网络带宽、电力消费、栈内存等。

### 直接使用锁和使用封装器的对比

* 直接用锁

很容易漏unlock，也比较繁琐

```cpp
#include <mutex> // class mutex;
std::mutex g_mutexThing;

int doSomething(const string &input, string &output)
{
    int iRetVal = -1;

    do
    {
        g_mutexThing.lock();
        if (!condition1)
        {
            LOGGER_ERROR("error1");
            g_mutexThing.unlock();
            break;
        }
        if (!condition2)
        {
            LOGGER_ERROR("error1");
            g_mutexThing.unlock();
            break;
        }
        g_mutexThing.unlock();

        iRetVal = 0;
    } while (0);

    return iRetVal;
}
```

* 类 lock_guard 是互斥封装器，为在作用域块期间占有互斥提供便利 RAII 风格机制。

```cpp
#include <mutex> // class mutex; class lock_guard;
std::mutex g_mutexThing;

int doSomething2(const string &input, string &output)
{
    int iRetVal = -1;

    do
    {
        std::lock_guard<std::mutex> lockGuard(g_mutexThing);
        if (!condition1)
        {
            LOGGER_ERROR("error1");
            break;
        }
        if (!condition2)
        {
            LOGGER_ERROR("error1");
            break;
        }

        iRetVal = 0;
    } while (0);

    return iRetVal;
}
```

* 若只需要在某个小范围执行加锁，则用{}定义语句块，临时变量lockGuard在语句块结束时则析构销毁，析构中进行解锁。

```cpp
#include <mutex> // class mutex; class lock_guard;
std::mutex g_mutexThing;

int doSomething3(const string &input, string &output)
{
    int iRetVal = -1;

    do
    {
        {
            std::lock_guard<std::mutex> lockGuard(g_mutexThing);
            if (!condition1)
            {
                LOGGER_ERROR("error1");
                break;
            }
        }

        func1();

        iRetVal = 0;
    } while (0);

    return iRetVal;
}
```

以下是对互斥锁mutex的进一步了解说明。 涉及C++版本问题，因此一并整理。

## 标准库头文件 <mutex>

参考：

* cppreference.com: [标准库头文件 mutex](https://zh.cppreference.com/w/cpp/header/mutex)

mutex(互斥量/互斥锁)包含在C++的线程支持库中，C++包含线程、互斥、条件变量和future的内建支持。(C++11开始支持)

C++0x/C++11提供了对thread, mutex, condition_variable这些concurrency相关特性的支持

该标准头文件包含各类型的互斥量的类和函数，截取一部分：

```cpp
namespace std {
    class mutex;                                // 基本互斥锁 (C++11新增)
    class recursive_mutex;                      // 能被同一线程递归锁定的互斥设施(C++11)
    class timed_mutex;                          // 有时限锁定的互斥锁(C++11)
    class recursive_timed_mutex;                // 能被同一线程递归锁定的互斥设施，并实现有时限锁定(C++11)

    template <class Mutex> class lock_guard;    // 严格基于作用域的互斥体所有权包装器(C++11)
    template <class Mutex> class unique_lock;   // 可移动的互斥体所有权包装器(C++11)

    template< class... MutexTypes >class scoped_lock;  // 用于多个互斥体的免死锁 RAII 封装器(C++17)
    //...
}
```

关于读写锁：
C++是从14之后的版本才正式支持共享互斥量，也就是实现读写锁的结构。 <shared_mutex>头文件中。

关于linux下的posix读写锁类型，另外再做介绍。

关于该头文件中各个类型的版本支持，在cppreference.com已经有说明了，也可参考：
[C++雾中风景12:聊聊C++中的Mutex，以及拯救生产力的Boost](https://www.cnblogs.com/happenlee/p/9747743.html)

> 在C++98中没有thread, mutex, condition_variable这些与concurrency相关的特性支持
> 参考： [漫话C++0x（五）—- thread, mutex, condition_variable](https://www.cnblogs.com/lidabo/p/3949465.html)

## C++各版本简要过程

百度百科：[c++0x](https://baike.baidu.com/item/c%2B%2B0x)

* 1998年是C++标准委员会成立的第一年，以后每5年视实际需要更新一次标准。
* 2009年，C++标准有了一次更新，一般称该草案为C++0x。
* C++0x是C++11标准成为正式标准之前的草案临时名字。
* 后来，2011年，C++新标准标准正式通过，更名为ISO/IEC 14882:2011，简称C++11。

维基百科：[C++11](https://zh.wikipedia.org/wiki/C%2B%2B11#cite_note-1)

* C++11，先前被称作C++0x，即ISO/IEC 14882:2011，是C++编程语言的一个标准。
    - 它取代第二版标准ISO/IEC 14882:2003
    （第一版ISO/IEC 14882:1998公开于1998年，
      第二版于2003年更新，分别通称C++98以及C++03，两者差异很小），且已被C++14取代
* C++14 旨在作为C++11的一个小扩展，主要提供漏洞修复和小的改进。
    - 2014年8月18日，经过C++标准委员投票，C++14标准获得一致通过。ISO/IEC 14882:2014
* C++17 又称C++1z，是继 C++14 之后，C++ 编程语言 ISO/IEC 标准的下一次修订的非正式名称。
    - 官方名称 ISO/IEC 14882:2017
    - 基于 C++ 11，C++ 17 旨在简化该语言的日常使用，使开发者可以更简单地编写和维护代码。
    - C++ 17是对 C++ 语言的重大更新
    - 参考： [C++ 17 标准正式发布](https://blog.csdn.net/csdnnews/article/details/78737012)

相比于C++03，C++11标准包含核心语言的新机能，而且扩展C++标准程序库，并入了大部分的C++ Technical Report 1程序库（数学的特殊函数除外）。

关于C++11的版本发布过程...：

>上一个版本的C++国际标准是2003年发布的，所以叫C++ 03。然后C++国际标准委员会在研究C++ 03的下一个版本的时候，一开始计划是07年发布，所以最初这个标准叫C++ 07。但是到06年的时候，官方觉得07年肯定完不成C++ 07，而且官方觉得08年可能也完不成。最后干脆叫C++ 0x。x的意思是不知道到底能在07还是08还是09年完成。结果2010年的时候也没完成，最后在2011年终于完成了C++标准。所以最终定名为C++11。  参考：[c++ 0x和c++ 11是什么关系？0x又是什么意思？](https://www.zhihu.com/question/20141092/answer/21463744)