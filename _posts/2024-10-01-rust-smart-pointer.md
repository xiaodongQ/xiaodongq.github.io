---
layout: _post
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

下述涉及代码，也可见：[test_smart_ptr](https://github.com/xiaodongQ/rust_learning/tree/master/test_smart_ptr)

## 3. `Box<T>`智能指针

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

## 4. Deref 和 Drop 特征

### 4.1. Deref解引用

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

### 4.2. 隐式Deref转换

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

### 4.3. 三种Deref转换

除了上面的 `Deref` 不可变引用转换，Rust还提供了另外两种 `Deref` 转换，3种转换规则如下：

* 当`T: Deref<Target=U>`，可以将`&T`转换为`&U`
* 当`T: DerefMut<Target=U>`，可以将`&mut T`转换为`&mut U`
    * 注意：要实现 `DerefMut` 必须要先实现 `Deref` 特征
* 当`T: Deref<Target=U>`，可以将`&mut T`转换为`&U`
    * Rust 可以把可变引用隐式的转换成不可变引用，但反之则不行

### 4.4. Drop释放资源

在Rust中，可以指定在一个变量超出作用域时，执行一段特定的代码，最终编译器将帮你自动插入这段收尾代码。该段代码就是 `Drop` 特征的 `drop` 方法。（和C++中的析构函数类似）

简单实现示例：

```rust
struct Foo;

impl Drop for Foo {
    fn drop(&mut self) {
        println!("Dropping Foo!")
    }
}
fn test_drop() {
    let _foo = Foo;
    println!("Running!");
}
```

运行：函数最后会调用到`drop`函数

```shell
Running!
Dropping Foo!
```

**Drop 的顺序：**

* 变量级别，按照逆序的方式，比如：若`_x` 在 `_foo` 之前创建，则 `_x` 在 `_foo` 之后被 `drop`
* 结构体内部，按照顺序的方式，比如：结构体 `_x` 中的字段按照定义中的顺序依次 `drop`

Rust **自动**为几乎所有类型都实现了 `Drop` 特征，因此就算不手动为结构体实现 `Drop`，它依然会调用默认实现的 `drop` 函数，同时再调用每个字段的 `drop` 方法。

**手动释放：**

针对编译器实现的 `drop` 函数，会拿走变量的所有权，因此，如果想要手动释放资源，可以使用 `std::mem::drop` 函数。

`std::mem::drop` 函数的签名为：`pub fn drop<T>(_x: T)`，可见 [标准库手册：mem drop](https://doc.rust-lang.org/std/mem/fn.drop.html)

示例：

```rust
fn test_mem_drop() {
    let mut foo = Foo;

    // 报错：explicit destructor calls not allowed
    // foo.drop();

    // 调用编译器自动生成的drop函数，释放内存
    drop(foo);
    // 以下代码会报错：借用了所有权被转移的值
    // println!("Running!:{:?}", foo);
}
```

使用场景：

* 回收内存资源，比如文件描述符、网络socket 等
* 执行一些收尾工作

无法为一个类型同时实现`Copy`和`Drop`特征：因为实现了`Copy`的类型会被编译器隐式的复制，因此非常难以预测析构函数执行的时间和频率。因此这些实现了`Copy`的类型无法拥有析构函数。

```rust
// 编译报错：error[E0184]: the trait `Copy` cannot be implemented for this type; the type has a destructor
#[derive(Copy)]
struct Foo;

impl Drop for Foo {
    fn drop(&mut self) {
        println!("Dropping Foo!")
    }
}
```

## 5. 引用计数智能指针`Rc<T>`和`Arc<T>`

Rust的所有权机制，只允许一个数据在同一时刻只有一个所有者，但部分场景需要多个所有者，比如：

* 在图数据结构中，多个边可能会拥有同一个节点
* 在多线程中，多个线程可能会持有同一个数据，但受限于Rust的安全机制，无法同时获取该数据的可变引用

为了解决此类问题，Rust通过引用计数的方式，允许一个数据资源在同一时刻拥有多个所有者。有两种实现机制：

* `Rc<T>`，Rc的全称是`reference counting`，引用计数
    * 一旦最后一个拥有者消失，则资源会自动被回收，这个生命周期是在**编译期**就确定下来的
    * `Rc`只能用于同一线程内部，想要用于线程之间的对象共享，需要使用`Arc`
* `Arc<T>`，Arc的全称是`atomic reference counting`，原子引用计数
    * `Arc<T>`能保证线程安全，它使用原子操作来保证线程安全，因此它比`Rc<T>`慢
    * `Arc`和`Rc`并没有定义在同一个模块，前者通过 `use std::sync::Arc` 来引入，后者通过 `use std::rc::Rc`

`Rc<T>`和`Arc<T>`指向的数据都是**不可变引用**。

示例：

```rust
use std::rc::Rc;
fn rc_ptr() {
    let s = String::from("hello, world");
    // 使用Rc类型，Rc::new 创建一个引用计数类型的智能指针
    // 智能指针 Rc<T> 在创建时，引用计数会加1，可通过关联函数 Rc::strong_count(&a) 获取引用计数
    let a = Rc::new(s);
    println!("a referce count1: {}", Rc::strong_count(&a));
    
    // 用 Rc::clone 克隆了一份智能指针，引用计数也会加1
    // 此处clone不是深拷贝，仅仅复制了智能指针并增加了引用计数，并没有克隆底层数据
    let b = Rc::clone(&a);
    println!("a referce count2: {}", Rc::strong_count(&a));
    println!("b referce count: {}", Rc::strong_count(&b));

    // 使用 Arc::new 创建智能指针
    use std::sync::Arc;
    let s1 = Arc::new(String::from("test arc"));
    // 可通过 *s1 解引用获取值
    println!("s1 referce count: {}, *s1:{}", Arc::strong_count(&s1), *s1);
}
```

## 6. 可变智能指针`Cell<T>`和`RefCell<T>`

上节中的`Rc<T>`和`Arc<T>`是不可变的，Rust提供了 `Cell` 和 `RefCell` 用于**内部可变性**，即在拥有不可变引用的同时修改目标数据。

内部可变性：内部可变性是Rust中的一种设计模式，它允许在数据存在不可变引用时对数据进行修改（通常情况下，借用规则不允许此操作），底层基于`unsafe`机制修改。

`Cell` 和 `RefCell` 在功能上没有区别，区别在于 `Cell<T>` 适用于 `T` 实现 `Copy` 的情况。比如，下述示例中可以`Cell::new("asdf")`，但不能`Cell::new(String::from("asdf"))`。

Cell示例：

```rust
use std::cell::Cell;
fn cell_ptr() {
    // 此处的"asdf"是&str类型，实现了Copy
    let c = Cell::new("asdf");

    // String 没有实现 Copy 特征，所以Cell中不能存放String类型
    // let c2 = Cell::new(String::from("asdf"));
    // 编译报错：error[E0599]: the method `get` exists for struct `Cell<String>`, but its trait bounds were not satisfied
        // doesn't satisfy `String: Copy`
    // println!("c2:{}", c2.get());

    // 获取当前值，不是实时指针，后面修改不影响此处
    let one = c.get();
    // 获取值到one里后，通过c还能做修改，修改c不影响one的值
    c.set("qwer");
    let two = c.get();
    // 结果：one:asdf, two:qwer, c.get():qwer
    println!("one:{}, two:{}, c.get():{}", one, two, c.get());
    // 不可通过 *c 解引用获取值
    // println!("*c:{}", *c);
}
```

RefCell示例：

```rust
use std::cell::RefCell;
fn refcell_ptr() {
    let s = RefCell::new(String::from("hello, world"));
    let s1 = s.borrow();
    // 编译器不会报错，但违背了借用规则，会导致运行期 panic
    let s2 = s.borrow_mut();

    println!("{},{}", s1, s2);
}
```

`Cell`和`RefCell`说明：

* 与 `Cell` 用于可 `Copy` 的值不同，`RefCell` 用于引用
* `RefCell` 只是将借用规则从编译期推迟到程序运行期，并不能帮你绕过这个规则
* `RefCell` 适用于编译期误报或者一个引用被在多处代码使用、修改以至于难于管理借用关系时
* 使用 `RefCell` 时，违背借用规则会导致运行期的 panic
* `Cell` 没有额外的性能损耗，`RefCell` 有少量运行时开销，因为 `RefCell` 需要维护借用状态

注意：

* `Cell` 和 `RefCell`类型都可以看作是智能指针，但它们并不像 `Box<T>` 或 `Rc<T>` 那样直接实现 `Deref` 和 `DerefMut` traits 来支持解引用操作。这是因为它们的设计目的是为了提供特定的内部可变性机制，而不仅仅是封装所有权和生命周期。
* 即不能直接通过`*`解引用获取值，需要使用对应的方法进行访问，比如 Cell：`get`/`set`，RefCell：`borrow`/`borrow_mut`，具体见[标准库](https://doc.rust-lang.org/std/cell/struct.RefCell.html)。

**`Rc` 和 `RefCell` 组合使用：**

在 Rust 中，一个常见的组合就是 `Rc` 和 `RefCell` 在一起使用，前者可以实现一个数据拥有多个所有者，后者可以实现数据的可变性。

```rust
use std::cell::RefCell;
use std::rc::Rc;
fn rc_refcell() {
    // 用 RefCell<String> 包裹一个字符串，并通过 Rc 创建了它的三个所有者
    let s = Rc::new(RefCell::new("hello world".to_string()));

    let s1 = s.clone();
    let s2 = s.clone();
    // 通过其中一个所有者 s2 对字符串内容进行修改
    s2.borrow_mut().push_str(", xxxxx!");

    // let mut s2 = s.borrow_mut();
    // s2.push_str("xxxxx");

    // 打印结果如下：三者共享同一个底层数据，都发生了变化
    // RefCell { value: "hello world, xxxxx!" }
    // RefCell { value: "hello world, xxxxx!" }
    // RefCell { value: "hello world, xxxxx!" }
    println!("{:?}\n{:?}\n{:?}", s, s1, s2);
}
```

## 7. 循环引用与自引用

循环引用可能引起**内存泄漏**。一个典型的例子就是同时使用 `Rc<T>` 和 `RefCell<T>` 创建循环引用，最终这些引用的计数都无法被归零，因此 `Rc<T>` 拥有的值也不会被释放清理。

循环引用示例：`a-> b -> a -> b`

可通过`Weak`来解决循环引用问题，通过`use std::rc::Weak`引入。

* `Weak` 非常类似于 `Rc`，但是与 `Rc` 持有所有权不同，`Weak` 不持有所有权，它仅仅保存一份指向数据的弱引用
    * 弱引用不保证引用关系依然存在，如果不存在，就返回一个 `None`
* 如果想要访问数据，需要通过 `Weak` 指针的 `upgrade` 方法实现，该方法返回一个类型为 `Option<Rc<T>>` 的值。

此处暂时留个印象，后续再进一步学习，需要再结合更多的实际项目和实践加强体感。

## 8. 小结

学习Rust的几种智能指针。

## 9. 参考

1、[Rust语言圣经(Rust Course) -- 智能指针](https://course.rs/advance/smart-pointer/intro.html)

2、[The Rust Programming Language -- Smart Pointers](https://doc.rust-lang.org/book/ch15-00-smart-pointers.html)

3、[标准库手册](https://doc.rust-lang.org/std/index.html)

4、[标准库手册：impl-Deref-for-String](https://doc.rust-lang.org/std/string/struct.String.html#impl-Deref-for-String)
