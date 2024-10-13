---
layout: post
title: Rust学习实践（六） -- Rust特性：unsafe、macro宏编程、异步编程
categories: Rust
tags: Rust
---

* content
{:toc}

Rust学习实践，进一步学习梳理Rust特性：unsafe、macro宏编程、异步编程。



## 1. 背景

继续进一步学习下Rust特性，本篇学习梳理：unsafe、async异步编程，顺带了解下`macro宏编程`。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. unsafe Rust

通常Rust在编译时会强制执行的内存安全保证，此外还有一种机制，不会强制执行这类内存安全保证：这被称为 **不安全Rust（`unsafe Rust`）**。它与常规 Rust 代码无异，但是会提供额外的超能力。

*进一步了解，可参考：[The Rust Programming Language中文版 -- 不安全的Rust](https://kaisery.github.io/trpl-zh-cn/ch19-01-unsafe-rust.html)。*

`unsafe Rust`存在的原因：

* 一方面，Rust的静态分析本质上是保守的，当编译器尝试确定一段代码是否支持某个保证时，拒绝一些合法的程序比接受无效的程序要好一些。如果 Rust 编译器没有足够的信息来确定代码是否合法，虽然有时**可能**是合法的，它也将拒绝该代码。
* 另一方面是底层计算机硬件固有的不安全性。如果 Rust 不允许进行不安全操作，那么有些任务则根本完成不了。Rust有时需要直接与操作系统交互这样的底层系统编程。

有五类可以在不安全 Rust 中进行而不能用于安全 Rust 的操作，它们称之为 “不安全的超能力。（`unsafe superpowers`）”：

* 解引用裸指针（raw pointers）
* 调用不安全的函数或方法
* 访问或修改可变静态变量
* 实现不安全 trait
* 访问 union 的字段

可通过`unsafe`关键字来切换到不安全Rust代码块。

注意：`unsafe` 并不会关闭借用检查器或禁用任何其他 Rust 安全检查；此外，`unsafe`不意味着块中的代码就一定是危险的或者必然导致内存安全问题：其意图在于作为程序员你将会确保`unsafe` 块中的代码以有效的方式访问内存。

### 2.1. 解引用裸指针

Rust中的`裸指针`（raw pointers）有两个：不可变裸指针（`*const`） 和 可变裸指针（`*mut T`）。这里的星号`*`不是解引用运算符，它是类型名称的一部分。

`裸指针`与`引用`和`智能指针`的区别在于：

* 允许忽略借用规则，可以同时拥有不可变和可变的指针，或多个指向相同位置的可变指针
* 不保证指向有效的内存
* 允许为空
* 不能实现任何自动清理功能

创建裸指针是安全的行为，而解引用裸指针才是不安全的行为，需要`unsafe`标记对应的代码块。示例：

```rust
fn test_raw_pointer() {
    let mut num = 5;

    // 将引用 &num / &mut num 强转为相应的裸指针 *const i32 / *mut i32
    let r1 = &num as *const i32;
    let r2 = &mut num as *mut i32;

    let a: Box<i32> = Box::new(10);
    let b: *const i32 = &*a;
    let c: *const i32 = Box::into_raw(a);

    // 解引用裸指针是不安全的行为，需要放到unsafe语句块中，否则编译报错
    unsafe {
        // 报错：`r1` is a `*const` pointer, so the data it refers to cannot be written
        // *r1 = *r1 + 1;
        
        // 执行结果 r1 is: 5
        println!("r1 is: {}", *r1);
        *r2 = *r2 + 1;
        // 执行结果 r1 is: 6
        println!("r2 is: {}", *r2);
    }

    // 还可根据智能指针创建裸指针
    let a: Box<i32> = Box::new(10);
    // 解引用再取引用创建
    let b: *const i32 = &*a;
    // 使用 into_raw 来创建
    let c: *const i32 = Box::into_raw(a);
    unsafe {
        println!("b:{}, c:{}", *b, *c);
    }
}
```

### 2.2. 调用unsafe函数或方法

使用 `unsafe fn` 来进行定义：

```rust
unsafe fn dangerous() {
    // unsafe函数或方法里，不用重复用unsafe限定了
    println!("dangerous() called");
}

fn test_unsafe_func() {
    // unsafe函数或方法调用时，需要包裹在unsafe语句块中
    unsafe {
        dangerous();
    };
}
```

### 2.3. 访问可变静态变量

Rust 要求必须使用`unsafe`语句块才能访问和修改static变量

```rust
static mut REQUEST_RECV: usize = 0;
fn test_unsafe_static() {
    // 访问或修改可变static变量时，不加unsafe则会报错
    // note: mutable statics can be mutated by multiple threads: 
        // aliasing violations or data races will cause undefined behavior
    unsafe {
        REQUEST_RECV += 1;
        assert_eq!(REQUEST_RECV, 1);
    }
}
```

### 2.4. 实现unsafe特征

若特征（trait）中至少有一个方法包含有编译器无法验证的内容，就需要标记为`unsafe`

```rust
unsafe trait Foo {
    // 方法列表
}
unsafe impl Foo for i32 {
    // 实现相应的方法
}
```

### 2.5. 访问union的字段

`union`主要用于跟`C`代码进行交互，访问 `union` 的字段是不安全的，因为 Rust 无法保证当前存储在 `union` 实例中的数据类型。

此处暂不作梳理。

## 3. Macro宏编程了解

在 Rust 中宏分为两大类：

* 1、声明式宏(declarative macros)：`macro_rules!`
* 2、三种过程宏(procedural macros)
    * 自定义 `#[derive]` 宏，在结构体和枚举上指定通过 `derive` 属性添加的代码
    * 类属性宏(Attribute-like macro)，用于为目标添加自定义的属性
    * 类函数宏(Function-like macro)，看上去就像是函数调用

从根本上来说，宏是一种为写其他代码而写代码的方式，即所谓的 **元编程（metaprogramming）**。这些宏以`展开`的方式来生成更多的代码，元编程对于减少大量编写和维护的代码是非常有用的。

宏和函数对比：

* 一个函数签名必须声明函数参数个数和类型。相比之下，宏能够接收不同数量的参数
    * 比如：用一个参数调用 `println!("hello")` 或用两个参数调用 `println!("hello {}", name)`
* 宏可以在编译器翻译代码前展开，例如，宏可以在一个给定类型上实现 trait。而函数则不行，因为函数是在运行时被调用，同时 trait 需要在编译时实现
* 实现宏不如实现函数的一面是宏定义要比函数定义更复杂
* 宏和函数一个重要的区别是：在一个文件里调用宏 **之前** 必须定义它，或将其引入作用域，而函数则可以在任何地方定义和调用。

**使用 `macro_rules!` 的声明宏（declarative macros）用于通用元编程：**

`vec!`的简化实现示例：

```rust
// #[macro_export] 注释将宏进行导出，这样其它的包就可以将该宏引入到当前作用域
#[macro_export]
// 使用 macro_rules! 进行宏定义。宏的名称是 `vec`（而不是`vec!`，感叹号只在调用时才需要）
macro_rules! vec {
    // vec 的定义结构跟 match 表达式很像，此处只有一个分支，包含一个模式 `( $( $x:expr ),* )`
    // 最外层的圆括号`()` 将整个宏模式包裹其中
    // 紧随其后的是 `$()`，括号里模式匹配的值会被捕获（里面传入Rust源码）
        // `$x:expr`会匹配任何 Rust 表达式并给予该模式一个名称：`$x`
    // `$()`后面的逗号分隔符：`,*`，说明 `*` 之前的模式会被匹配零次或任意多次，类似正则表达式
    ( $( $x:expr ),* ) => {
        {
            let mut temp_vec = Vec::new();
            // $() 中的 temp_vec.push() 将根据模式匹配的次数生成对应的代码
            $(
                temp_vec.push($x);
            )*
            temp_vec
        }
    };
}
```

当调用`vec![1, 2, 3]`时，源代码会展开为：

```rust
{
    let mut temp_vec = Vec::new();
    temp_vec.push(1);
    temp_vec.push(2);
    temp_vec.push(3);
    temp_vec
}
```

3种过程宏，后续按需再梳理学习，此处暂不展开。

## 4. async异步编程

几种并发模型：

* **OS 线程**
    * 线程间的上下文切换损耗较大。使用线程池在一定程度上可以提升性能，但是对于 IO 密集的场景来说，线程池还是不够
    * Rust就选择了原生支持线程级的并发编程
* **事件驱动(Event driven)**
    * 这种模型性能相当的好，但最大的问题就是存在回调地狱的风险，非线性的控制流和结果处理导致了数据流向和错误传播变得难以掌控
* 协程(Coroutines)
    * 协程跟线程类似，无需改变编程模型，可以支持大量的任务并发运行，Go 语言的协程设计就非常优秀
    * 但协程抽象层次过高，导致用户无法接触到底层的细节
* **`actor` 模型**
    * 将所有并发计算分割成一个一个单元，这些单元被称为 `actor`，单元之间通过消息传递的方式进行通信和数据传递。`actor`模型是`erlang` 的杀手锏之一。
* **`async`/`await`**
    * 该模型性能高，还能支持底层编程，同时又像线程和协程那样无需过多的改变编程模型
    * `async`模型的问题就是内部实现机制过于复杂，对于用户来说，理解和使用起来也没有线程和协程简单

Rust 经过权衡取舍后，最终选择了同时提供 `多线程编程` 和 `async`编程：

* 前者通过`标准库`实现
* 后者通过`语言特性` + `标准库` + `三方库`的方式实现

对于 **多线程** 和 **`async`**（其底层实现基于线程封装了一个运行时），需要选择适合的并发模型：

* 有大量 IO 任务需要并发运行时，选 async 模型
* 有部分 IO 任务需要并发运行时，选多线程，如果想要降低线程创建和销毁的开销，可以使用线程池
* 有大量 CPU 密集任务需要并行运行时，例如并行计算，选多线程模型，且让线程数等于或者稍大于 CPU 核心数
* 无所谓时，统一选多线程

**语言和库的支持：**

`async`的底层实现非常复杂，且会导致编译后文件体积显著增加，因此`Rust`没有选择像`Go`语言那样内置了完整的特性和运行时。

通过Rust语言提供了必要的特性支持，再通过社区来提供`async`运行时的支持，要完整使用`async`异步编程，需要依赖：

* 所必须的特征(例如`Futur`)、类型和函数，由标准库提供实现
* 关键字`async`/`await`，由Rust语言提供，并进行了编译器层面的支持
* 众多实用的类型、宏和函数，由官方开发的 [`futures`](https://github.com/rust-lang/futures-rs) 包提供（不是标准库），它们可以用在任何`async`应用中
* `async`代码的执行、IO操作、任务创建和调度等等复杂功能，由社区的`async`运行时提供，例如[`tokio`](https://github.com/tokio-rs/tokio) 和 [`async-std`](https://github.com/async-rs/async-std)

## 5. 小结

梳理学习unsafe、async异步编程、宏编程，在后续实践中进一步理解。

## 6. 参考

1、[Rust语言圣经(Rust Course) -- Unsafe Rust](https://course.rs/advance/unsafe/intro.html)

2、[The Rust Programming Language中文版 -- 不安全的Rust](https://kaisery.github.io/trpl-zh-cn/ch19-01-unsafe-rust.html)

3、[Rust语言圣经(Rust Course) -- Macro宏编程](https://course.rs/advance/macro.html)

4、[Rust语言圣经(Rust Course) -- async/await异步编程](https://course.rs/advance/async/intro.html)
