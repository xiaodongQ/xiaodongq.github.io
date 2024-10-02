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

## 2. 智能指针

智能指针往往是基于结构体实现，它与自定义的结构体最大的区别在于它实现了 `Deref` 和 `Drop` 特征：

* `Deref` 可以让智能指针像引用那样工作，这样就可以写出同时支持智能指针和引用的代码，例如 `*T`
* `Drop` 允许指定智能指针超出作用域后自动执行的代码，例如做一些数据清除等收尾工作

Rust中的智能指针有好几种，此处介绍以下最常用的几种：

* `Box<T>`：将值分配到堆上
* `Rc<T>`：引用计数类型，允许多所有权存在
* `Ref<T>` 和 `RefMut<T>`：允许将借用规则检查从编译期移动到运行期进行（通过`RefCell<T>`实现）。

### 2.1. `Box<T>`智能指针

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

        // 下面一行代码将报错，无法隐式调用Deref特征解引用
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

fn test_arr_box() {
    let arr = vec![Box::new(1), Box::new(2)];
    let (first, second) = (&arr[0], &arr[1]);
    let sum = **first + **second;
}
```


## 3. 小结


## 4. 参考

1、[Rust语言圣经(Rust Course) -- 智能指针](https://course.rs/advance/smart-pointer/intro.html)

2、[The Rust Programming Language -- Smart Pointers](https://doc.rust-lang.org/book/ch15-00-smart-pointers.html)
