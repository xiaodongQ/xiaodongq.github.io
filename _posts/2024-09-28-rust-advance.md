---
layout: post
title: Rust学习实践（三） -- Rust特性进阶学习（上）
categories: Rust
tags: Rust
---

* content
{:toc}

Rust学习实践，进一步学习梳理Rust特性。



## 1. 背景

上两节过了一遍Rust基础语法并进行demo练习，本篇继续进一步学习下Rust特性。

相关特性主要包含：生命周期、函数式编程（迭代器和闭包）、智能指针、循环引用、多线程并发编程；异步编程、Macro宏编程、Unsafe等，分两篇博客笔记梳理记录。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 生命周期

[之前](https://xiaodongq.github.io/2024/09/17/rust-relearn-overview/)过基础语法时，简单提到过生命周期的基本使用，这次进一步理解下。

基于下述链接梳理学习：

* [Rust语言圣经(Rust Course) -- 基础入门：认识生命周期](https://course.rs/basic/lifetime.html)
* [Rust语言圣经(Rust Course) -- 进阶学习：生命周期](https://course.rs/advance/lifetime/intro.html)
* [The Rust Programming Language -- Validating References with Lifetimes](https://doc.rust-lang.org/book/ch10-03-lifetime-syntax.html)

> 在大多数时候，我们无需手动的声明生命周期，因为编译器可以自动进行推导。但是当多个生命周期存在，且编译器无法推导出某个引用的生命周期时，就需要我们手动标明生命周期。

**生命周期标注并不会改变任何引用的实际作用域。**

### 2.1. 函数中的生命周期示例

再贴一个上述基础入门中的例子：`longest`函数的参数和返回值标注，表示返回值的生命周期取作用域最小的那个。

**函数的返回值如果是一个引用类型，那么它的生命周期只会来源于：**

* 从参数获取 （称为`输入生命周期`，返回值的生命周期则称为`输出生命周期`）
* 从函数体内部新创建的变量获取（典型的悬垂引用，编译器会报错拦截）

```rust
// 编译会出错，因为result的访问超出了string2的作用域（最小的那个生命周期）
fn return_lifetime() {
    let string1 = String::from("long string is long");
    let result;
    {
        let string2 = String::from("xyz");
        // 此处会编译报错（括号外使用了result），
        // 因为 longest 返回的生命周期是 string1和string2中较小的那个生命周期，离开括号后string2的生命周期已经结束
        result = longest(string1.as_str(), string2.as_str());
    }
    // 注释下面这条访问result的语句，则不会报错，只是警告上面的result没使用
    println!("The longest string is {}", result);
}

// 此处生命周期标注仅仅说明，这两个参数 x、y 和返回值至少活得和 'a 一样久(因为返回值要么是 x，要么是 y)
// 实际上，这意味着返回值的生命周期与参数生命周期中的较小值一致
// 由于返回值的生命周期也被标记为 'a，因此返回值的生命周期也是 x 和 y 中作用域较小的那个
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() {
        x
    } else {
        y
    }
}
```

另外举例说明下面几种函数生命周期相关的情况，可在IDE中修改验证：

* `longest`中写死返回第一个参数`x`的引用，则`y`不需要标注生命周期，此时可编译通过
    * `fn longest2<'a>(x: &'a str, y: & str) -> &'a str { x }` （编译成功，注意此处y并没有生命周期标注）
* 悬垂引用
    * `fn longest3<'a>(x: & str, y: &str) -> &'a str { String::from("hello") }` （编译失败）
* 针对上述悬垂引用的问题，一个解决方式是：返回所有权，并把内部新建字符串的所有权转移给调用者
    * `fn longest4<'a>(x: &'a str, y: &str) -> String { String::from("hello") }` （编译成功）

### 2.2. 结构体中的生命周期

调整cargo项目中的目录结构，不同文件验证不同场景，如 main_struct.rs 中验证struct结构体的生命周期。

并通过 `cargo build --bin test_lifetime` 或 `cargo run --bin main_function` 的方式进行编译和运行验证。

```sh
[MacOS-xd@qxd ➜ test_lifetime git:(master) ✗ ]$ tree -L 3                    
.
├── Cargo.lock
├── Cargo.toml
├── src
│   ├── bin
│   │   ├── main_function.rs
│   │   └── main_struct.rs
│   └── main.rs
```

结构体定义示例：

```rust
// 先声明声明周期，再使用标注
struct ImportantExcerpt<'a> {
    part: &'a str,
}
```

* 其中有一个引用成员字段，因此必须标注生命周期
* 该生命周期标注说明，结构体 ImportantExcerpt `所引用的字符串str` 必须比该`结构体`活得更久

以下述两个case进行说明：

```rust
// 需要保证结构体中引用字段的生命周期 比 结构体本身的生命周期 **更长**
fn test_success() {
    let novel = String::from("Call me Ishmael. Some years ago...");
    let first_sentence = novel.split('.').next().expect("Could not find a '.'");
    let text = ImportantExcerpt {
        part: first_sentence,
    };
    println!("info: {:?}", text);
}

// 编译失败
fn test_failed() {
    // 结构体定义
    let text;

    {
        let novel = String::from("Call me Ishmael. Some years ago...");
        // next() 返回一个 Option<&'a str>，成功时，返回一个切片引用
        let first_sentence = novel.split('.').next().expect("Could not find a '.'");
        // 引用字段的生命周期 比 结构体本身的生命周期 短，而大括号外又访问了，所以会编译失败（注释外面访问则可正常编译运行）
        text = ImportantExcerpt {
            part: first_sentence,
        };
        // 正常打印
        println!("info1: {:?}", text);
    }
    
    // 大括号外访问，结构体和其中字段引用的生命周期不满足生命周期条件，所以会编译失败
    println!("info2: {:?}", text);
}
```

### 2.3. 方法中的生命周期



### 2.4. 生命周期消除规则

生命周期消除的三条规则（是否需显式地去标注生命周期）：

* 1、每一个引用参数都会获得独自的生命周期
    * `fn foo<'a, 'b>(x: &'a i32, y: &'b i32)`
* 2、若只有一个`输入生命周期`(函数参数中只有一个引用类型)，那么该生命周期会被赋给所有的`输出生命周期`
    * 也就是所有返回值的生命周期都等于该输入生命周期
    * `fn foo(x: &i32) -> &i32` 等同于 `fn foo<'a>(x: &'a i32) -> &'a i32`
* 3、若存在多个输入生命周期，且其中一个是 `&self` 或 `&mut self`，则 `&self` 的生命周期被赋给所有的输出生命周期
    * 拥有 `&self` 形式的参数，说明该函数是一个**方法**，该规则让方法的使用便利度大幅提升
    * 上面是未显式标记时的默认表现，也可手动标注生命周期进行指定。比如将部分输出生命周期指定得更短

示例：`fn first_word(s: &str) -> &str { xxx }`，编译器应用上述规则的简化过程如下

* 首先，应用第1条规则，为每个参数标注一个生命周期
    * `fn first_word<'a>(s: &'a str) -> &str { xxx }`
* 然后，应用第2条规则，因为只有一个`输入生命周期`，所以返回值生命周期（`输出生命周期`）也是 `'a`
    * `fn first_word<'a>(s: &'a str) -> &'a str { xxx }`
* 此时，编译器为函数签名中的所有引用都自动添加了具体的生命周期，因此编译通过，且用户无需手动去标注生命周期

## 3. 小结


## 4. 参考

1、[Rust语言圣经(Rust Course) -- Rust 进阶学习](https://course.rs/advance/intro.html)

2、[Rust语言圣经(Rust Course) -- 基础入门：认识生命周期](https://course.rs/basic/lifetime.html)

3、[The Rust Programming Language -- Validating References with Lifetimes](https://doc.rust-lang.org/book/ch10-03-lifetime-syntax.html)
