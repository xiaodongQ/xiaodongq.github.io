---
layout: post
title: Rust学习实践（二） -- Demo项目：文件搜索工具
categories: Rust
tags: Rust
---

* content
{:toc}

Rust学习实践，进行Rust的“实战”（Demo）练习：文件搜索工具。



## 1. 背景

上篇过完了Rust的基础语法，接下来进行Rust的一个Demo练习。跟着几个参考项目，基于：[入门实战：文件搜索工具](https://course.rs/basic-practice/intro.html)。

虽然是一个练习项目，本篇尝试假装按一个正式项目的基本流程进行管理迭代，包含：项目需求分析、项目结构设计、项目开发、项目测试、项目发布。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 项目需求分析

需求：构建一个简化版本的`grep`命令行程序，能够实现文件搜索功能。（客户需求比较模糊）

### 2.1. 需求列表

对需求进行分析拆分，梳理需求列表如下：

* 支持从命令行参数中读取指定的文件名和字符串（必须）
* 在相应的文件中找到包含该字符串的内容，最终打印出来（必须）
* DFX
    * 性能：搜索速度要快，内存占用要低，支持多线程（可选）
    * 易用性：命令行参数要简洁，支持通配符（可选）
    * 可测试性：代码要模块化，便于测试（必须）
    * 可维护性：支持CI持续集成，测试用例要覆盖所有功能（必须）
* 进阶需求：
    * 支持指定目录搜索（必须）
    * 支持通配符、正则表达式搜索（可选）

暂实现必须需求，后续根据需要再迭代实现。

### 2.2. 需求分解

需求分解为任务项：

* Rust项目框架搭建（不用方案设计了）
* 命令行参数解析模块
    * 基本参数解析：文件名和字符串
    * 高级参数解析：支持`-i`忽略大小写，并支持`-r`目录递归搜索参数
* 文件搜索模块
    * 基于“基本参数”：遍历文件，找到包含字符串的文件，打印对应行号和内容
    * 基于“高级参数”：支持目录递归搜索，支持`-i`忽略大小写搜索
* 持续集成模块
    * CI脚本编写，支持自动构建、测试、发布

### 2.3. 迭代设计

**迭代安排：**

分2个迭代，第一个迭代完成总体设计和基本框架搭建，及基本功能实现；第二个迭代实现进阶需求。

**任务分配：**

上述需求和任务拆分后，可以根据实际情况进行任务分配。此处就自己一个人，自己完成所有任务。

* 各特性完成自身任务并进行单元测试
* 模块集成后进行集成测试，通过后进行发测交付并进入下一个迭代

## 3. 基本功能实现

说明：先跟着参考文章实现，熟悉标准库使用。

创建项目：`cargo new minigrep`。

### 3.1. 参数解析

借助标准库中`std::env`模块的 `args()`函数进行命令参数解析。

* `std::env`模块
    * 进程环境的检查和操作，例如获取环境变量、命令行参数等
    * [Module std::env](https://doc.rust-lang.org/std/env/index.html)
* `std::env::args()`函数
    * [Function std::env::args]((https://doc.rust-lang.org/std/env/fn.args.html))

```rust
use std::env;

fn main() {
    // 通过 collect 方法输出一个集合类型 Vector
    let args : Vec<String> = env::args().collect();
    // dbg!(&args);

    // 暂只支持传入1个文件
    if args.len() != 3 {
        println!("usage: minigrep <query> <filename>");
        return;
    }

    let query = &args[1];
    let filename = &args[2];
    println!("query:{}, filename:{}", query, filename);
}
```

### 3.2. 文件读取

借助标准库中`std::fs`模块，提供文件系统控制操作，例如文件读写、目录遍历等。

* `std::fs`模块
    * 文件系统控制操作，例如文件读写、目录遍历等
    * [Module std::fs](https://doc.rust-lang.org/std/fs/index.html)
* `std::fs::read_to_string`函数
    * 读取整个文件内容到字符串中
    * [Function std::fs::read_to_string](https://doc.rust-lang.org/std/fs/fn.read_to_string.html)

读取参数指定的文件内容：

```rust
use std::env;
use std::fs;

fn main() {
    // 省略参数解析
    ...
    // 通过std::fs模块的 read_to_string 读取文件内容
    // 返回结果为 std::io::Result<String>，对应于 Result<T, E>，T为String，E为Error
    let contents = std::fs::read_to_string(filename);
    match contents {
        Ok(contents) => println!("{}", contents),
        Err(error) => println!("Problem opening the file: {:?}", error),
    }
}
```

运行：

```shell
[MacOS-xd@qxd ➜ minigrep git:(master) ✗ ]$ cargo run a Cargo.toml 
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.01s
     Running `target/debug/minigrep a Cargo.toml`
query:a, filename:Cargo.toml
[package]
name = "minigrep"
version = "0.1.0"
edition = "2021"

[dependencies]
```

不存在的文件：

```shell
[MacOS-xd@qxd ➜ minigrep git:(master) ✗ ]$ cargo run a Cargo.toml1
   Compiling minigrep v0.1.0 (/Users/xd/Documents/workspace/src/rust_path/rust_learning/minigrep)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.46s
     Running `target/debug/minigrep a Cargo.toml1`
query:a, filename:Cargo.toml1
Problem opening the file: Os { code: 2, kind: NotFound, message: "No such file or directory" }
```

### 3.3. 文件搜索

## 4. 模块化设计

上述代码都放在一个文件甚至一个main函数里，进行模块化拆分。

* 程序分割为 main.rs 和 lib.rs，并将程序的逻辑代码移动到 lib.rs 内。
    * 关注点分离(Separation of Concerns)
* 命令行解析是比较基础的功能，还是放在 main.rs 中

代码逐步优化：（过程代码见：[minigrep bin](https://github.com/xiaodongQ/rust_learning/tree/master/minigrep/src/bin) 和 [minigrep main](https://github.com/xiaodongQ/rust_learning/tree/master/minigrep/src/)）

* 参数解析处理抽取为函数
    * `fn parse_args(args : &Vec<String>) -> (&str, &str) { xxx }`
* 解析函数返回值由 2个元素的元组 调整为 struct结构体(定义`struct Config`)
    * `fn parse_args(args : &Vec<String>) -> Config { xxx }`
* 创建Config实例的方式，由函数调整为`impl`实现结构体方法（关联函数） `new`，面向对象编程
    * `impl Config { fn new(args : &[String]) -> Config { xxx} }`
    * 处理：`let config = Config::new(&args);`
* 方法返回`Result<T, E>`错误码，方法名调整为`build`（语义更合适），并通过`闭包`处理错误
    * `impl Config { fn build(args : &[String]) -> Result<Config, &'static str> { xxx } }`
    * 处理：`let config = Config::build(&args).unwrap_or_else(|err| { xxx }`
    * `unwrap_or_else` 是定义在 `Result<T,E>` 上的常用方法，如果`Result`是`Ok`，那该方法就类似`unwrap`：返回`Ok`内部的值；如果是`Err`，就调用闭包中的自定义代码对错误进行进一步处理


## 5. 小结


## 6. 参考

1、[入门实战：文件搜索工具](https://course.rs/basic-practice/intro.html)

2、[Module std::env](https://doc.rust-lang.org/std/env/index.html)
