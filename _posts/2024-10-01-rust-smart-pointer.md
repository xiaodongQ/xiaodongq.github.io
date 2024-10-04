---
layout: post
title: Rust学习实践（四） -- Rust特性：智能指针
categories: Rust
tags: Rust
---

* content
{:toc}

Rust学习实践，进一步学习梳理Rust特性：智能指针。



## 1. 背景

继续进一步学习下Rust特性，本篇学习梳理：智能指针。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 概要说明

智能指针往往是基于结构体实现，它与自定义的结构体最大的区别在于它实现了 `Deref` 和 `Drop` 特征：

* `Deref` 可以让智能指针像引用那样工作，这样就可以写出同时支持智能指针和引用的代码，例如 `*T`
* `Drop` 允许指定智能指针超出作用域后自动执行的代码，例如做一些数据清除等收尾工作

Rust中的智能指针有好几种，此处介绍以下最常用的几种：

* `Box<T>`：将值分配到堆上
* `Rc<T>`：引用计数类型，允许多所有权存在
* `Ref<T>` 和 `RefMut<T>`：允许将借用规则检查从编译期移动到运行期进行（通过`RefCell<T>`实现）。

## 3. `Box<T>`智能指针

### 3.1. 基本使用

`Box<T>`是Rust中最常见的智能指针，除了将值存储在堆上外，并没有其它性能上的损耗。

**使用场景：**

* 特意的将数据分配在堆上
* 数据较大时，又不想在转移所有权时进行数据拷贝
* 类型的大小在编译期无法确定，但是我们又需要固定大小的类型时
* 特征对象，用于说明对象实现了一个特征，而不是某个特定的类型

**基本用法：**

```rust
fn test_simple() {
    // 创建一个智能指针指向了存储在堆上的 3，并且 a 持有了该指针
    {
        let a = Box::new(3);
        // 智能指针实现了Deref 和 Drop特征，此处会隐式调用Deref特征，对指针进行解引用
        println!("a = {}", a); // a = 3

        // 下面一行代码将报错，表达式无法隐式调用Deref特征解引用
        // let b = a + 1; // cannot add `{integer}` to `Box<{integer}>`
        // 因此需要显式使用`*`，调用Deref特征解引用
        let b = *a + 1;
    }

    // 作用域结束，上面的智能指针就被释放了，因为Box实现了Drop特征
    // 下面使用会报错：cannot find value `a` in this scope
    // let c = *a + 2;
}

fn test_array() {
    // 在栈上创建一个长度为1000的数组
    let arr = [0;1000];
    // 将arr所有权转移arr1，由于 `arr` 分配在栈上，因此这里实际上是直接重新深拷贝了一份数据
    let arr1 = arr;

    // arr 和 arr1 都拥有各自的栈上数组，因此不会报错
    println!("{:?}", arr.len());
    println!("{:?}", arr1.len());

    // 在堆上创建一个长度为1000的数组，然后使用一个智能指针指向它
    let arr = Box::new([0;1000]);
    // 将堆上数组的所有权转移给 arr1，由于数据在堆上，因此仅仅拷贝了智能指针的结构体，底层数据并没有被拷贝
    // 所有权顺利转移给 arr1，arr 不再拥有所有权
    let arr1 = arr;
    println!("{:?}", arr1.len());
    // 由于 arr 不再拥有底层数组的所有权，因此下面代码将报错
    // println!("{:?}", arr.len());
}

fn test_box_arr() {
    let arr = vec![Box::new(1), Box::new(2)];
    // 使用 & 借用数组中的元素，否则会报所有权错误
    let (first, second) = (&arr[0], &arr[1]);
    // 表达式不能隐式的解引用，因此必须使用 ** 做两次解引用，
    // 第一次将 &Box<i32> 类型转成 Box<i32>，第二次将 Box<i32> 转成 i32
    let sum = **first + **second;
}
```

**Box::leak：**

Box中还提供了一个非常有用的关联函数：`Box::leak`，它可以消费掉 Box 并且强制目标值从内存中泄漏。

```rust
fn main() {
   let s = gen_static_str();
   println!("{}", s);
}

fn gen_static_str() -> &'static str{
    let mut s = String::new();
    s.push_str("hello, world");

    // 原来的 String 被消费掉，但是它的内容被转移到了堆上，并且被标记为 'static，返回了不可变的引用
    Box::leak(s.into_boxed_str())
}
```

Box 背后是调用 `jemalloc` 来做内存管理（glibc默认使用`ptmalloc`），所以堆上的空间无需我们手动管理。

### 3.2. Deref解引用

当我们对智能指针 Box 进行解引用时，实际上 Rust 为我们调用了以下方法：`*(y.deref())`

* 即：首先调用 `deref` 方法返回值的常规**引用**（由于所有权系统存在，不直接返回值，因而不涉及所有权转移），然后通过 `*` 对常规引用进行解引用，最终获取到目标值。
* 需要注意的是，`*` 不会无限递归替换，从 `*y` 到 `*(y.deref())` 只会发生一次，而不会继续进行替换然后产生形如 `*((y.deref()).deref())` 这样的表达式。

以下面示例进一步理解解引用动作：自定义简单的智能指针，实现`Deref`特征

```rust
use std::ops::Deref;

// newtype MyBox<T>，定义一个结构体，其中包含一个泛型 T
struct MyBox<T>(T);

impl<T> MyBox<T> {
    fn new(x: T) -> MyBox<T> {
        MyBox(x)
    }
}

// 为智能指针实现 Deref 特征
impl<T> Deref for MyBox<T> {
    // 类型别名（关联类型 Target，主要用于提升代码可读性）
    type Target = T;

    // 当解引用 MyBox 智能指针时，返回元组结构体中的元素 &self.0
    fn deref(&self) -> &Self::Target {
        // 返回的是一个常规引用，可以被 * 进行解引用
        &self.0
    }
}

fn test_deref() {
    let x = 5;
    let y = MyBox::new(x);

    println!("x = {}, y = {}", x, *y);
}
```

### 3.3. 隐式Deref转换

对于函数和方法的传参，Rust 提供了一个极其有用的隐式转换：`Deref`转换。

若一个类型实现了 `Deref` 特征，那它的引用在传给函数或方法时，会根据参数签名来决定是否进行隐式的 `Deref` 转换。

规则总结：一个类型为 T 的对象 foo，如果 `T: Deref<Target=U>`，那么，相关 foo 的引用 `&foo` 在应用的时候会自动转换为 `&U`。

```rust
// 隐式 Deref
fn test_auto_deref() {
    // String 实现了 Deref 特征，可以在需要时自动被转换为 &str 类型
    let s = String::from("hello world");
    // &s 是一个 &String 类型，当它被传给 display 函数时，自动通过 Deref 转换成了 &str
    display(&s)
}

fn display(s: &str) {
    println!("{}", s);
}
```

可通过 [标准库手册](https://doc.rust-lang.org/std/index.html) 查询`String`类型（`Struct std::string::String`），及其实现的`Deref`特征：[impl-Deref-for-String](https://doc.rust-lang.org/std/string/struct.String.html#impl-Deref-for-String)。

### 3.4. 三种Deref转换

除了上面的 `Deref` 不可变引用转换，Rust还提供了另外两种 `Deref` 转换，3种转换规则如下：

* 当`T: Deref<Target=U>`，可以将`&T`转换为`&U`
* 当`T: DerefMut<Target=U>`，可以将`&mut T`转换为`&mut U`
    * 注意：要实现 `DerefMut` 必须要先实现 `Deref` 特征
* 当`T: Deref<Target=U>`，可以将`&mut T`转换为`&U`
    * Rust 可以把可变引用隐式的转换成不可变引用，但反之则不行

### 3.5. Drop特征



## 4. 小结


## 5. 参考

1、[Rust语言圣经(Rust Course) -- 智能指针](https://course.rs/advance/smart-pointer/intro.html)

2、[The Rust Programming Language -- Smart Pointers](https://doc.rust-lang.org/book/ch15-00-smart-pointers.html)

3、[标准库手册](https://doc.rust-lang.org/std/index.html)