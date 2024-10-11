---
layout: post
title: Rust学习实践（六） -- Rust特性：unsafe、异步编程
categories: Rust
tags: Rust
---

* content
{:toc}

Rust学习实践，进一步学习梳理Rust特性：unsafe、异步编程。



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

可通过`unsafe`关键字来切换到不安全Rust代码块。注意：`unsafe` 并不会关闭借用检查器或禁用任何其他 Rust 安全检查；此外，`unsafe`不意味着块中的代码就一定是危险的或者必然导致内存安全问题：其意图在于作为程序员你将会确保`unsafe` 块中的代码以有效的方式访问内存。

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
}
```

## 3. Macro宏编程

## 4. async异步编程

## 5. 小结

梳理学习unsafe、async异步编程、宏编程，在后续实践中进一步理解。

## 6. 参考

1、[Rust语言圣经(Rust Course) -- Unsafe Rust](https://course.rs/advance/unsafe/intro.html)

2、[The Rust Programming Language中文版 -- 不安全的Rust](https://kaisery.github.io/trpl-zh-cn/ch19-01-unsafe-rust.html)

3、[Rust语言圣经(Rust Course) -- Macro宏编程](https://course.rs/advance/macro.html)

4、[Rust语言圣经(Rust Course) -- async/await异步编程](https://course.rs/advance/async/intro.html)
