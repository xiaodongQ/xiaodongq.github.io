---
layout: _post
title: 创建型设计模式-单例模式
categories: 设计模式
tags: 设计模式
---

* content
{:toc}

创建型设计模式-单例模式示例记录



## 1. 背景

最近梳理项目模块代码，其中部分模块和工具涉及一些设计模式，画了一些相关的流程图和草图。重新打开极客时间里设计模式课程，通过示例(C++)加强一些体感。

![单例模式形式](/images/2024-05-12-09-27-03.png)

## 2. 23种设计模式简要说明

23种设计模式：创建型(5种)、结构型(7种)、行为型(11种)

1. 单例模式(Singleton Pattern)  
   确保一个类只有一个实例，并提供一个全局访问点。
2. 工厂方法模式(Factory Method Pattern)  
   定义一个用于创建对象的接口，让子类决定实例化哪一个类。
3. 抽象工厂模式(Abstract Factory Pattern)  
   提供一个接口，用于创建一系列相关或相互依赖的对象，而无需指定它们的具体类。
4. 建造者模式(Builder Pattern)  
   将一个复杂对象的构建与它的表示分离，使得同样的构建过程可以创建不同的表示。
5. 原型模式(Prototype Pattern)  
   用原型实例指定创建对象的种类，并且通过复制这些原型来创建新的对象。

本篇文章中介绍单例模式。

## 3. 饿汉式(Eager Initialization)：类加载时就完成实例化

说明：下面是一个饿汉式单例模式示例

* 通过私有的构造函数和拷贝构造函数，外部不能再创建和复制实例
* 通过`=delete`禁用拷贝构造函数、赋值运算符，也限制了新增实例
* **线程安全**：静态成员`instance`在类加载时就被初始化，因此是线程安全的。不需要额外的同步机制来保证线程安全，这是饿汉式单例的一个优点。
* 如果`doSomething`里访问非原子性的共享资源，需要相应的资源保护。不过单例类自身是线程安全的。
* 需要注意的是，尽管饿汉式单例在C++中是线程安全的，但在某些情况下（例如当类库被动态加载时），它可能不是最佳选择。在这些情况下，可能需要使用其他单例模式（如懒汉式或双重检查锁定模式）来确保线程安全和性能。

```cpp
#include <iostream>  
  
class Singleton {  
private:  
    // 静态实例，在类定义时就被创建（饿汉式）  
    static Singleton instance;  
  
    // 构造函数私有，防止外部创建实例  
    Singleton() = default;  
  
    // 禁止拷贝构造函数和赋值运算符  
    Singleton(const Singleton&) = delete;  
    Singleton& operator=(const Singleton&) = delete;  
  
public:  
    // 静态方法，返回单例实例的引用  
    static Singleton& getInstance() {  
        return instance;  
    }  
  
    // 示例成员函数  
    void doSomething() {  
        std::cout << "Singleton: doSomething called." << std::endl;  
    }  
};  
  
// 静态实例的初始化，在类定义时就完成了  
Singleton Singleton::instance;  
  
int main() {  
    // 获取单例实例并调用方法  
    Singleton& s1 = Singleton::getInstance();  
    s1.doSomething();  
  
    // 再次获取单例实例（实际上是同一个实例），并调用方法  
    Singleton& s2 = Singleton::getInstance();  
    s2.doSomething();  
  
    // 由于s1和s2引用的是同一个实例，所以输出会表明它们是相同的实例  
    // 但实际上这在这个例子中不是重点，因为饿汉式单例已经保证了这一点  
  
    return 0;  
}
```

## 4. 懒汉式(Lazy Initialization)：延迟加载

说明：首次调用`getInstance()`才进行实例创建，下面是一个使用`std::mutex`和`std::lock_guard`的懒汉式单例模式的示例

* 静态成员变量instance初始化为nullptr
* 互斥锁mtx用于保护instance实例的线程安全
* 禁止外部创建实例、禁用拷贝构造函数和赋值运算符
* 析构函数被设置为protected或private，以防止外部代码删除单例实例
* 缺点：如果频繁地用到单例，那频繁加锁、释放锁及并发度低等问题，会导致性能瓶颈，这种实现方式就不可取了。

```cpp
#include <iostream>  
#include <mutex>  
  
class Singleton {  
private:  
    // 静态实例指针，初始化为nullptr  
    static Singleton* instance;  
  
    // 静态互斥锁，用于保护instance的线程安全创建  
    static std::mutex mtx;  
  
    // 构造函数私有，防止外部创建实例  
    Singleton() = default;  
  
    // 禁止拷贝构造函数和赋值运算符  
    Singleton(const Singleton&) = delete;  
    Singleton& operator=(const Singleton&) = delete;  
  
public:  
    // 静态方法，返回单例实例的指针  
    static Singleton* getInstance() {  
        std::lock_guard<std::mutex> lock(mtx); // 锁定互斥锁  
        if (instance == nullptr) { // 如果实例尚未创建  
            instance = new Singleton(); // 创建实例  
        }  
        return instance; // 返回实例指针  
    }  
  
    // 示例成员函数  
    void doSomething() {  
        std::cout << "Singleton: doSomething called." << std::endl;  
    }  
  
    // 析构函数设置为protected或private，并在单例类内部提供删除实例的方法  
    // （注意：在实际应用中，通常不会删除单例实例，除非是在程序结束时）  
protected:  
    ~Singleton() {  
        // 如果需要，可以在这里释放资源  
    }  
  
    // 提供静态方法用于删除单例实例（通常不建议这样做，除非有特别的需求）  
    static void destroyInstance() {  
        if (instance != nullptr) {  
            delete instance;  
            instance = nullptr;  
        }  
    }  
};  
  
// 初始化静态成员变量  
Singleton* Singleton::instance = nullptr;  
std::mutex Singleton::mtx;  
  
int main() {  
    // 获取单例实例并调用方法  
    Singleton* s1 = Singleton::getInstance();  
    s1->doSomething();  
  
    // 再次获取单例实例（实际上是同一个实例），并调用方法  
    Singleton* s2 = Singleton::getInstance();  
    s2->doSomething();  
  
    // 由于s1和s2指向的是同一个实例，所以它们的输出将表明它们引用的是同一个对象  
  
    // 注意：通常不会调用destroyInstance()，除非有特别的需求  
    // Singleton::destroyInstance(); // 这将删除单例实例，之后再次调用getInstance()将重新创建实例  

    // 在实际应用中，应该避免在main函数中创建局部静态的单例实例
  
    return 0;  
}
```

## 5. 双重检测(Double-Checked Locking, DCL)

双重检测锁定用于减少在懒汉式单例模式中的同步开销。它尝试只在第一次创建实例时同步，之后则直接返回已创建的实例，无需再次同步。

双重检测锁定的基本思想是在`getInstance()`方法中使用两次检查：第一次无锁检查实例是否已经被创建，如果尚未创建，则进入同步块进行第二次检查（此时需要加锁），以避免多个线程同时创建实例。

注意：由于C++内存模型的一些复杂性，双重检测的正确实现可能会变得相当复杂，并且容易出错。因此，在许多情况下，使用其他更简单且安全的替代方案（如`Meyers' Singleton`或`std::call_once`）可能是更好的选择。

说明：下面是一个双重检测的示例(比较复杂)

* `std::atomic`是一个模板类，用于提供原子操作，这些操作在多线程环境中是线程安全的。
* `std::atomic`可以包装任何类型的对象，如整数、指针等，提供了一组成员函数来执行原子操作，如`load`、`store`、`exchange`、`compare_exchange_strong`等
* `std::memory_order`是一个枚举类型，用于指定`std::atomic`操作的内存顺序。内存顺序决定了编译器和处理器如何重新排序内存访问。在多线程编程中，重新排序可能会导致数据竞争和不可预测的行为。因此，正确地设置内存顺序对于确保程序的正确性和性能至关重要。

```cpp
#include <iostream>  
#include <mutex>  
#include <atomic>  
#include <memory>  
  
class Singleton {  
private:  
    static std::atomic<Singleton*> instance;  
    static std::mutex mtx;  
  
    Singleton() = default;  
    Singleton(const Singleton&) = delete;  
    Singleton& operator=(const Singleton&) = delete;  
  
public:  
    static Singleton* getInstance() {  
        Singleton* localInstance = instance.load(std::memory_order_relaxed);  
        if (localInstance == nullptr) {  
            std::lock_guard<std::mutex> lock(mtx);  
            localInstance = instance.load(std::memory_order_relaxed);  
            if (localInstance == nullptr) {  
                localInstance = new Singleton();  
                // 使用memory_order_release确保instance的写入在后续读之前对其它线程可见  
                instance.store(localInstance, std::memory_order_release);  
            }  
        }  
        // 由于这里只是读取instance的值，所以使用memory_order_acquire或relaxed都是可以的  
        // 但为了保持一致性，这里仍然使用memory_order_acquire  
        return instance.load(std::memory_order_acquire);  
    }  
  
    // 示例成员函数  
    void doSomething() {  
        std::cout << "Singleton: doSomething called." << std::endl;  
    }  
  
    // 析构函数设置为protected或private，并提供静态方法用于删除实例（通常不推荐）  
protected:  
    ~Singleton() {  
        // 释放资源  
    }  
  
    // 提供静态方法用于删除单例实例（通常不推荐这样做，除非有特别的需求）  
    static void destroyInstance() {  
        if (instance.load(std::memory_order_relaxed) != nullptr) {  
            std::lock_guard<std::mutex> lock(mtx);  
            if (instance.load(std::memory_order_relaxed) != nullptr) {  
                Singleton* temp = instance.exchange(nullptr, std::memory_order_relaxed);  
                delete temp;  
            }  
        }  
    }  
};  
  
std::atomic<Singleton*> Singleton::instance(nullptr);  
std::mutex Singleton::mtx;  
  
// ...  
// 使用Singleton::getInstance()等  
  
int main() {  
    Singleton* s1 = Singleton::getInstance();  
    s1->doSomething();  
  
    Singleton* s2 = Singleton::getInstance();  
    // s1和s2将指向同一个Singleton实例  
    if (s1 == s2) {  
        std::cout << "s1 and s2 point to the same instance." << std::endl;  
    }  
  
    // 注意：通常不会调用destroyInstance()，除非有特别的需求  
    // Singleton::destroyInstance(); // 这将删除单例实例  
  
    return 0;  
}
```

`std::memory_order`枚举值说明：

* `std::memory_order_relaxed`：最弱的内存顺序约束。它既不保证加载操作之前的存储操作对其他线程可见，也不保证加载操作之后的存储操作对其他线程可见。它只保证原子操作本身的原子性。
* `std::memory_order_acquire`：加载操作之前的存储操作对执行加载的线程可见。它确保在加载操作之前的所有存储操作都已经完成，并且对其他线程也是可见的。
* `std::memory_order_release`：存储操作之后的加载操作对执行存储的线程不可见。它确保在存储操作之后的所有加载操作都还没有开始，或者已经完成了对其他线程的可见性。
* 还有`memory_order_consume`、`memory_order_acq_rel`、`memory_order_seq_cst`
* 在编写涉及多线程和原子操作的代码时，正确选择`std::memory_order`的值非常重要。过强的内存顺序可能导致性能下降，而过弱的内存顺序可能导致数据竞争和不可预测的行为。通常，应该选择最弱但足以满足程序正确性要求的内存顺序。

## 6. Meyers' Singleton

Meyers' Singleton（也被称为"Magic Statics"或者"Local Static Initialization"）是C++11及以后版本中推荐的单例实现方式之一。这种方法利用了C++的局部静态变量初始化是线程安全的这一特性，从而避免了显式使用锁或其他同步机制。

说明：下面是一个Meyers' Singleton的示例

* `getInstance`函数返回一个对Singleton类型静态局部变量的引用.
* 这个静态局部变量只会在第一次调用`getInstance`函数时初始化，并且是线程安全的。
* 由于C++11及以后的标准保证了局部静态变量的初始化是线程安全的，因此这种实现方式既简洁又高效。
* 此外，这种单例模式实现避免了双重检测锁定（Double-Checked Locking, DCL）的复杂性，并且通常比使用锁的方法更加高效。因此，在C++11及以后的版本中，推荐使用Meyers' Singleton作为单例模式的实现方式。

```cpp
#include <iostream>  
  
class Singleton {  
private:  
    Singleton() = default;  
    ~Singleton() = default;  
    Singleton(const Singleton&) = delete;  
    Singleton& operator=(const Singleton&) = delete;  
  
public:  
    static Singleton& getInstance() {  
        static Singleton instance; // 局部静态变量，线程安全地初始化  
        return instance;  
    }  
  
    void doSomething() {  
        std::cout << "Singleton: doSomething called." << std::endl;  
    }  
};  
  
// 使用Singleton  
int main() {  
    Singleton& s1 = Singleton::getInstance();  
    s1.doSomething();  
  
    Singleton& s2 = Singleton::getInstance();  
    // s1和s2引用的是同一个Singleton实例  
    if (&s1 == &s2) {  
        std::cout << "s1 and s2 refer to the same instance." << std::endl;  
    }  
  
    return 0;  
}
```

### 6.1. 和饿汉式单例的对比

**饿汉式单例**：

* 特点：饿汉式单例在类被加载时，就立即初始化其静态成员变量，也就是实例化单例对象，这种方式保证了线程安全性。
* 优点：线程安全，调用效率高，因为实例在类加载时就已经创建好了，所以每次调用`getInstance()`方法时，都可以直接返回该实例，无需再进行判断或同步。
* 缺点：不可延时加载，即使单例对象在程序启动后很长一段时间内都没有被使用，它也会被提前创建，可能会浪费内存资源。

**Meyers' Singleton**：

* 特点：利用了C++11中局部静态变量初始化是线程安全的这一特性，来实现单例。getInstance()方法中的静态局部变量instance在第一次被调用时才会被初始化，并且这个过程是线程安全的。
* 优点：结合了懒汉式和饿汉式的优点，既可以在真正需要的时候才初始化单例对象（避免了资源的浪费），又保证了线程的安全性（不需要额外的同步措施）。
* 缺点：相对饿汉式来说，Meyers' Singleton的实现方式稍显复杂一些。另外，由于它是利用局部静态变量的初始化来保证线程安全性的，所以在某些编译器或平台上可能存在兼容性问题。

总的来说，Meyers' Singleton和饿汉式单例各有优缺点，具体使用哪种方式取决于你的具体需求和场景。如果你希望单例对象在程序启动时就立即被创建，并且不关心资源的浪费问题，那么可以选择饿汉式单例；如果你希望单例对象在真正需要的时候才被创建，并且希望保证线程的安全性，那么可以选择Meyers' Singleton。

## 7. `std::once`方式(供了解)

说明：在下面示例中，`getInstance`方法使用了`std::call_once`来确保`createInstance`方法只被调用一次。

* 由于`std::call_once`是线程安全的，因此无论多少个线程同时调用`getInstance`，`createInstance`都只会被执行一次。
* 它可能不是性能最优的解决方案，因为`std::call_once`在每次调用`getInstance`时都需要检查`flag_`的状态，尽管这种开销在大多数情况下都是可以接受的。（它利用了底层的原子操作来优化性能）
* 相对于`Meyers' Singleton`，`std::once`方式不依赖于特定的编译器或平台，具有广泛的兼容性；`Meyers' Singleton`方式，虽然C++11及以后的标准保证了静态局部变量的线程安全初始化，但一些较旧的编译器可能不支持这一特性、在一些特定的平台或编译器上，静态局部变量的初始化可能不是线程安全的。
    * 如果你需要确保单例模式的线程安全性，并且希望代码具有广泛的兼容性和明确性，那么`std::call_once`是一个很好的选择。
    * 如果你追求代码的简洁性和性能，并且确信你的编译器和平台支持静态局部变量的线程安全初始化，那么`Meyers' Singleton`可能更适合你。

```cpp
#include <memory>  
#include <mutex>  
  
class Singleton {  
private:  
    Singleton() = default; // 构造函数是私有的，防止外部创建实例  
    Singleton(const Singleton&) = delete; // 禁止拷贝构造  
    Singleton& operator=(const Singleton&) = delete; // 禁止拷贝赋值  
  
    static std::unique_ptr<Singleton> instance_;  
    static std::once_flag flag_;  
  
public:  
    static Singleton& getInstance() {  
        std::call_once(flag_, &Singleton::createInstance);  
        return *instance_;  
    }  
  
private:  
    static void createInstance() {  
        instance_ = std::make_unique<Singleton>();  
    }  
};  
  
// 静态成员需要在类外部定义和初始化  
std::unique_ptr<Singleton> Singleton::instance_ = nullptr;  
std::once_flag Singleton::flag_;  
  
// 使用示例  
int main() {  
    Singleton& s1 = Singleton::getInstance();  
    Singleton& s2 = Singleton::getInstance();  
    // s1 和 s2 引用的是同一个实例  
    // ...  
    return 0;  
}
```

## 8. 小结

1、通过代码示例介绍了典型的几种单例模式的关键特点(示例均可编译运行)

2、实际建议参考(大模型建议)

* 如果你的程序是单线程的，或者你对性能要求不高，那么懒汉式和饿汉式都可以选择。但是，请注意懒汉式在多线程环境中的线程安全问题(如上面的加锁示例)。
* 如果你的程序是多线程的，并且你对性能要求较高，那么建议使用饿汉式结合C++11的局部静态变量特性来实现单例模式。这种方法既简单又高效，且线程安全。
* 另外，如果你希望单例模式的实现更加灵活和可配置（例如，允许在运行时更改单例的创建方式），那么可以考虑使用工厂模式或依赖注入等更高级的技术来实现单例模式(在另外的创建型模式文章单独说明)。

3、以当前自己的实际项目经验(仅限个人)，常用到的是饿汉式。

认同文章里的观点：

> 如果初始化耗时长，那我们最好不要等到真正要用它的时候，才去执行这个耗时长的初始化过程，这会影响到系统的性能（比如，在响应客户端接口请求的时候，做这个初始化操作，会导致此请求的响应时间变长，甚至超时）。采用饿汉式实现方式，将耗时的初始化操作，提前到程序启动的时候完成，这样就能避免在程序运行的时候，再去初始化导致的性能问题。

> 如果实例占用资源多，按照 fail-fast 的设计原则（有问题及早暴露），那我们也希望在程序启动时就将这个实例初始化好。如果资源不够，就会在程序启动的时候触发报错（比如 Java 中的 PermGen Space OOM），我们可以立即去修复。这样也能避免在程序运行一段时间后，突然因为初始化这个实例占用资源过多，导致系统崩溃，影响系统的可用性。

## 9. 参考

1、[极客时间：设计模式之美](https://time.geekbang.org/column/article/194068)

2、GPT
