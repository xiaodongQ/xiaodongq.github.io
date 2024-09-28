---
layout: post
title: Rust学习实践（三） -- Rust特性进阶学习（上）
categories: Rust
tags: Rust
---

* content
{:toc}

Rust学习实践，进一步学习梳理Rust进阶特性。



## 1. 背景

上两节过了一遍Rust基础语法并进行demo练习，本篇继续进一步学习下Rust特性。

相关特性主要包含：生命周期、函数式编程（迭代器和闭包）、智能指针、循环引用、多线程并发编程；异步编程、Macro宏编程、Unsafe等，分两篇博客笔记梳理记录。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 生命周期

[之前](https://xiaodongq.github.io/2024/09/17/rust-relearn-overview/)过基础语法时，提到过生命周期的基本使用，这次深入理解下。

基于下述链接梳理学习：

* [Rust语言圣经(Rust Course) -- 基础入门：认识生命周期](https://course.rs/basic/lifetime.html)
* [Rust语言圣经(Rust Course) -- 进阶学习：生命周期](https://course.rs/advance/lifetime/intro.html)
* [The Rust Programming Language -- Validating References with Lifetimes](https://doc.rust-lang.org/book/ch10-03-lifetime-syntax.html)

在大多数时候，我们无需手动的声明生命周期，因为编译器可以自动进行推导。但是当多个生命周期存在，且编译器无法推导出某个引用的生命周期时，就需要我们手动标明生命周期。



## 3. 小结


## 4. 参考

1、[Rust语言圣经(Rust Course) -- Rust 进阶学习](https://course.rs/advance/intro.html)

2、[Rust语言圣经(Rust Course) -- 基础入门：认识生命周期](https://course.rs/basic/lifetime.html)

3、[The Rust Programming Language -- Validating References with Lifetimes](https://doc.rust-lang.org/book/ch10-03-lifetime-syntax.html)
