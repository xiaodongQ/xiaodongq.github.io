---
layout: post
title: Rust学习实践（五） -- Rust特性：并发编程
categories: Rust
tags: Rust
---

* content
{:toc}

Rust学习实践，进一步学习梳理Rust特性：多线程并发编程。



## 1. 背景

继续进一步学习下Rust特性，本篇学习梳理：多线程并发编程。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 概要说明

Rust中由于语言设计理念、安全、性能的多方面考虑，并不像Go中简化到一个`go`关键字就可以使用`go routine`实现并发，而是选择了多线程与 `async/await` 相结合，优点是可控性更强、性能更高，缺点是复杂度并不低。

并发和并行：如果某个系统支持两个或者多个动作的**同时存在**，那么这个系统就是一个`并发`系统。如果某个系统支持两个或者多个动作**同时执行**，那么这个系统就是一个`并行`系统。

**编程语言的并发模型**，大致有下面几类：

* 程序内的线程数和该程序占用的操作系统线程数相等，一般称之为`1:1 线程模型`，例如 **Rust**。
* 有些语言在内部实现了自己的线程模型（绿色线程、协程），程序内部的 `M` 个线程最后会以某种映射方式使用 `N` 个操作系统线程去运行，因此称之为`M:N 线程模型`，其中 `M` 和 `N` 并没有特定的彼此限制关系。一个典型的代表就是 Go 语言。
* 有些语言使用了 Actor 模型，基于消息传递进行并发，例如 Erlang 语言

每一种模型都有其优缺点及选择上的权衡，而 Rust 在设计时考虑的权衡就是`运行时(Runtime)`。出于 Rust 的系统级使用场景，且要保证调用 `C` 时的极致性能，它最终选择了尽量小的运行时实现。

> 运行时是那些会被打包到所有程序可执行文件中的 Rust 代码，根据每个语言的设计权衡，运行时虽然有大有小（例如 Go 语言由于实现了协程和 GC，运行时相对就会更大一些），但是除了汇编之外，每个语言都拥有它。小运行时的其中一个好处在于最终编译出的可执行文件会相对较小，同时也让该语言更容易被其它语言引入使用。
>
> 绿色线程/协程的实现会显著增大运行时的大小，因此 Rust 只在`标准库`中提供了 1:1 的线程模型，如果你愿意牺牲一些性能来换取更精确的线程控制以及更小的线程上下文切换成本，那么可以选择 Rust 中的 `M:N 模型`，这些模型由`三方库`提供了实现，例如大名鼎鼎的 `tokio`。

本篇学习涉及到的内容：

* 如何创建线程来同时运行多段代码。
* `消息传递（Message passing）`并发，其中`信道（channel）`被用来在线程间传递消息。
* `共享状态（Shared state）`并发，其中多个线程可以访问同一片数据。
* `Sync` 和 `Send` trait，将 Rust 的并发保证扩展到用户定义的以及标准库提供的类型中。

## 3. 创建线程

使用`thread::spawn`函数创建线程，并传递一个闭包作为线程执行的代码。（spawn, [spɔn], 产生、产卵、引起）

并可：

* 通过`join`等待新建线程执行结束，否则主线程结束时，新建线程会被强制终止。
* 通过`move`关键字，将闭包中引用的所有变量所有权转移到闭包中，避免闭包中引用的变量在线程执行时被释放。

```rust
use std::thread;
use std::time::Duration;
fn test_spwan() {
    // 获取thread::spawn返回的JoinHandle，用于下面的join等待
    // 可在闭包前面添加 move 关键字，这样闭包就会获取所有被引用变量的所有权
    let handle = thread::spawn(move || {
        for i in 1..10 {
            println!("hi number {i} from the spawned thread!");
            thread::sleep(Duration::from_millis(1));
        }
    });

    // 主线程
    for i in 1..5 {
        println!("hi number {i} from the main thread!");
        thread::sleep(Duration::from_millis(1));
    }

    // join 会阻塞当前线程直到 handle 所代表的线程结束
    // 不join则主线程结束时子线程会被强制结束
    handle.join().unwrap();
}
```

## 4. 线程控制

### 4.1. 线程屏障Barrier

可以通过线程屏障（`Barrier`）来让多个线程在某个点同步，即等待所有线程都执行到某个点后，再一起继续执行。

```rust
// use std::thread; // 前面已经引入了
use std::sync::{Arc, Barrier};
fn test_barriers() {
    // 数组用于保存线程句柄
    let mut handles = Vec::with_capacity(6);
    // 创建一个线程屏障，等待6个线程，通过线程安全的Arc智能指针来共享
    let barrier = Arc::new(Barrier::new(6));

    for _ in 0..6 {
        let b = barrier.clone();
        handles.push(thread::spawn(move|| {
            println!("before wait");
            // 增加一个线程屏障
            b.wait();
            println!("after wait");
        }));
    }

    for handle in handles {
        handle.join().unwrap();
    }
}
```

运行结果：所有的线程都打印出before wait后，各个线程才会继续执行

```shell
========= test_barriers... =======
before wait
before wait
before wait
before wait
before wait
before wait
after wait
after wait
after wait
after wait
after wait
after wait
```

### 4.2. 条件变量Condvar

`条件变量(Condition Variables)`经常和 `Mutex` 一起使用，可以让线程挂起，直到某个条件发生后再继续执行。

```rust
use std::sync::{Mutex, Condvar};
fn test_condvar() {
    // 创建一个Mutex和Condvar的元组，通过Arc原子引用计数智能指针来共享
    let pair = Arc::new((Mutex::new(false), Condvar::new()));
    // 通过clone来克隆一个智能指针，引用计数+1
    let pair2 = pair.clone();

    thread::spawn(move|| {
        let (lock, cvar) = &*pair2;
        // 获取锁，并且获取锁保护的值
            // lock.lock()返回的是一个Result<MutexGuard<bool>, Error>
            // 由于MutexGuard是一个结构体，它实现了Deref和DerefMut trait，可以像引用一样使用
            // 因此可以直接将MutexGuard<bool>赋值给mut started，而不需要显式地解引用
        // 暂时使用unwrap()处理错误，生产代码中不推荐，会导致程序在遇到错误时panic
        let mut started = lock.lock().unwrap();
        println!("changing started");
        // 修改共享状态：started的值设置为true
        *started = true;
        // 通知等待的线程，此处的cvar和主线程中的cvar是同一个
        cvar.notify_one();
    });

    let (lock, cvar) = &*pair;
    // 获取锁
    let mut started = lock.lock().unwrap();
    // 等待started的值变为true，如果为false则通过条件变量的wait函数挂起当前线程
    while !*started {
        // wait函数等待满足条件
            // wait返回一个Result<MutexGuard<T>, Error>，该方法会释放Mutex的锁，并使当前线程进入等待状态
            // 当其他线程调用notify_one或notify_all方法通知条件变量时，wait方法会重新获取锁，并返回一个新的MutexGuard
        started = cvar.wait(started).unwrap();
    }

    println!("started changed");
}
```

运行结果：

```shell
========= test_condvar... =======
changing started
started changed
```

### 4.3. 函数只调用一次sync::Once

通过`sync::Once`，可让某个函数在多线程环境下只被调用一次，例如初始化全局变量，无论是哪个线程先调用函数来初始化，都会保证全局变量只会被初始化一次，随后的其它线程调用就会忽略该函数。

如下述示例中，代码运行的VAL结果取决于哪个线程先调用 `INIT.call_once`

```rust
// use std::thread;
use std::sync::Once;
static mut VAL: usize = 0;
static INIT: Once = Once::new();
fn test_call_once() {
    let handle1 = thread::spawn(move || {
        INIT.call_once(|| {
            unsafe {
                VAL = 1;
            }
        });
    });

    let handle2 = thread::spawn(move || {
        INIT.call_once(|| {
            unsafe {
                VAL = 2;
            }
        });
    });

    handle1.join().unwrap();
    handle2.join().unwrap();

    println!("{}", unsafe { VAL });
}
```

## 5. 线程同步



## 6. 小结


## 7. 参考

1、[Rust语言圣经(Rust Course) -- 多线程并发编程](https://course.rs/advance/concurrency-with-threads/intro.html)

2、[The Rust Programming Language -- Fearless Concurrency](https://doc.rust-lang.org/book/ch16-00-concurrency.html)

3、[The Rust Programming Language中文版 -- 无畏并发](https://kaisery.github.io/trpl-zh-cn/ch16-00-concurrency.html)

4、[标准库手册](https://doc.rust-lang.org/std/index.html)
