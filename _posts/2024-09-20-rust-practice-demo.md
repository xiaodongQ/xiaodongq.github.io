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

上篇过完了Rust的基础语法，接下来进行Rust的一个Demo练习。跟着几个参考项目练手，先基于：[入门实战：文件搜索工具](https://course.rs/basic-practice/intro.html)。

虽然是一个练习项目，本篇尝试假装按一个正式项目的基本流程进行管理迭代，如：项目需求分析、项目结构设计、项目开发、项目测试、项目发布。

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
    * 可维护性：支持CI持续集成，测试用例要覆盖所有功能（可选）
* 进阶需求：
    * 支持指定目录搜索（可选）
    * 支持通配符、正则表达式搜索（可选）
    * 持续集成模块：CI脚本编写，支持自动构建、测试、发布（可选）

暂实现必须需求，后续根据需要再迭代实现。

### 2.2. 需求分解

需求分解为任务项：

* Rust项目框架搭建（不用方案设计了）
* 命令行参数解析模块
    * 基本参数解析：文件名和字符串
    * 高级参数解析：支持`-i`忽略大小写，并支持`-r`目录递归搜索参数
* 文件搜索模块
    * 基于“基本参数”：遍历文件内容，找到包含字符串的文件，打印对应行号和内容
    * 基于“高级参数”：支持目录递归搜索，支持`-i`忽略大小写搜索

假设工具名为`minigrep`，流程示意图：

![流程示意图](/images/2024-09-27-minigrep.png)

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

### 3.3. 文件行匹配

```rust
fn main() {
    // 省略参数解析
    ...
    // 通过std::fs模块的 read_to_string 读取文件内容
    // 返回结果为 std::io::Result<String>，对应于 Result<T, E>，T为String，E为Error
    let contents = std::fs::read_to_string(filename);
    ...

    let mut file_contents = String::new();
    match contents {
        // 此处Ok的模式匹配，绑定变量text，尽量不要用同名变量contents，会发生变量遮蔽，容易混淆
        Ok(text) => {
            file_contents = text;
            println!("file contents:\n{}", file_contents);
        }
        Err(error) => println!("Problem opening the file: {:?}", error),
    }

    // 匹配逻辑
    println!("\n==============result:==============");
    for line in file_contents.lines() {
        if line.contains(query) {
            println!("{}", line);
        }
    }
}
```

执行：

```shell
[MacOS-xd@qxd ➜ minigrep git:(master) ✗ ]$ cargo run --bin main1 name Cargo.toml 
   Compiling minigrep v0.1.0 (/Users/xd/Documents/workspace/src/rust_path/rust_learning/minigrep)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.55s
     Running `target/debug/main1 name Cargo.toml`
cmd:target/debug/main1, query:name, file_path:Cargo.toml
file contents:
[package]
name = "minigrep"
version = "0.1.0"
edition = "2021"

[dependencies]


==============result:==============
name = "minigrep"
```

完整代码在：[minigrep main1](https://github.com/xiaodongQ/rust_learning/tree/master/minigrep/src/main1.rs)

## 4. 模块化设计

上述代码都放在一个文件甚至一个main函数里，且部分逻辑不够简洁，进行模块化拆分和逻辑优化。

* 程序分割为 main.rs 和 lib.rs，并将程序的逻辑代码移动到 lib.rs 内。
    * 关注点分离(Separation of Concerns)
* 命令行解析是比较基础的功能，还是放在 main.rs 中

代码逐步优化：（过程代码见：[minigrep main](https://github.com/xiaodongQ/rust_learning/tree/master/minigrep/src/)）

* 优化1：解析传入参数抽取为函数；匹配逻辑由 `match` 调整为 `unwrap()` 处理
    * 抽取函数：`fn parse_args(args : &Vec<String>) -> (&str, &str) { xxx }`
    * `match`模式匹配调整为`unwarp()`：`let file_contents = std::fs::read_to_string(file_path).unwrap();`
        * unwrap 方法用于处理 Result 类型，如果 Result 类型是 Ok，则返回 Ok 中的值，否则程序会 panic
    * 对应代码：[minigrep main2](https://github.com/xiaodongQ/rust_learning/tree/master/minigrep/src/bin/main2.rs)
* 优化2：解析函数返回值由 2个元素的元组 调整为 struct结构体(定义`struct Config`)
    * `fn parse_args(args : &Vec<String>) -> Config { xxx }`
    * 对应代码：[minigrep main3](https://github.com/xiaodongQ/rust_learning/tree/master/minigrep/src/bin/main3.rs)
* 优化3：创建Config实例的方式，由函数调整为`impl`实现结构体方法（关联函数）`new`，面向对象编程
    * `impl Config { fn new(args : &[String]) -> Config { xxx} }`
        * 处理：`let config = Config::new(&args);`
    * 对应代码：[minigrep main4](https://github.com/xiaodongQ/rust_learning/tree/master/minigrep/src/bin/main4.rs)
* 优化4：使用`Result<T, E>`方式处理错误，方法名调整为`build`（语义更合适），并通过`闭包`处理错误
    * `impl Config { fn build(args : &[String]) -> Result<Config, &'static str> { xxx } }`
        * 处理：`let config = Config::build(&args).unwrap_or_else(|err| { xxx }`
        * `unwrap_or_else` 是定义在 `Result<T,E>` 上的常用方法，如果`Result`是`Ok`，那该方法就类似`unwrap`：返回`Ok`内部的值；如果是`Err`，就调用闭包中的自定义代码对错误进行进一步处理
    * 对应代码：[minigrep main5](https://github.com/xiaodongQ/rust_learning/tree/master/minigrep/src/bin/main5.rs)
* 优化5：分离main里的业务逻辑，抽取为 run 函数
    * `fn run(config : Config) -> Result<(), Box<dyn std::error::Error>> { xxx }`
        * std::error::Error 是Rust标准库的一个 trait，定义了错误处理的行为
        * dyn 表示动态分派，是Rust中的一种动态分派机制
    * 对应代码：[minigrep main6](https://github.com/xiaodongQ/rust_learning/tree/master/minigrep/src/bin/main6.rs)
* 优化6：分离业务逻辑到库包`lib.rs`中，并在`main.rs`里`use`引入；同时业务逻辑 `run` 中的匹配部分，继续抽取为 `search` 函数
    * 注意分离到`lib.rs`中的结构体和函数定义，需要标记为`pub`，否则在`main.rs`中无法使用
    * 可通过`use minigrep::Config;`，引入`lib.rs`中的`Config`结构体，然后使用`Config`；也可按`minigrep::Config`使用，显式指定包名
    * 对应代码：[minigrep main](https://github.com/xiaodongQ/rust_learning/tree/master/minigrep/src/main.rs) 和 [minigrep lib](https://github.com/xiaodongQ/rust_learning/tree/master/minigrep/src/lib.rs)

最后优化后的`main.rs`代码如下（`minigrep::run`逻辑则定义在`lib.rs`包中，完整内容见上述链接）：

```rust
use std::env;
use minigrep::Config;

fn main() {
    // 模块化代码
    // 通过 env::args() 获取命令行参数，返回一个迭代器。而后用 collect 方法输出一个集合类型 Vector
    let args : Vec<String> = env::args().collect();
    // 此处 unwrap_or_else 是Result实现的方法，使用闭包来处理错误
    let config = Config::build(&args).unwrap_or_else(|err| {
        println!("Problem parsing arguments: {}", err);
        // 标准库，处理进程退出
        std::process::exit(1);
    });
    println!("cmd:{}, query:{}, file_path:{}", &args[0], config.query, config.file_path);

    // 匹配业务逻辑
    // 用 if...let语法替换上一个文件中的match语法，更为简洁
    if let Err(err) = minigrep::run(config) {
        println!("run error: {}", err);
        std::process::exit(1);
    }
}
```

运行结果：

```shell
[MacOS-xd@qxd ➜ minigrep git:(master) ✗ ]$ cargo run --bin minigrep name Cargo.toml 
   Compiling minigrep v0.1.0 (/Users/xd/Documents/workspace/src/rust_path/rust_learning/minigrep)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.65s
     Running `target/debug/minigrep name Cargo.toml`
cmd:target/debug/minigrep, query:name, file_path:Cargo.toml

========grep result:========
name = "minigrep"
```

## 5. 单元测试

### 5.1. 典型结构

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn it_works() {
        assert_eq!(2 + 2, 4);
    }
}
```

* tests 就是一个**测试模块**，里面可以包含多个测试函数，比如`it_works`、`another_test`等
* 测试函数需要使用 **`test`属性** 进行标注。测试模块既可以定义测试函数又可以定义非测试函数
    * 相关断言：`assert_eq!`、`panic!`等
* 运行测试用例：`cargo test`
* 进一步学习可参考：[如何在 Rust 中编写测试代码](https://course.rs/test/intro.html)

### 5.2. minigrep用例

在lib.rs中新增如下单元测试，测试`search`匹配逻辑：

```rust
// 测试用例，测试 search 匹配逻辑
#[cfg(test)]
mod tests {
    use super::*;

    // 通过 test属性 标注该函数为 测试函数
    #[test]
    fn one_result() {
        let query = "duct";
        let contents = "\
Rust:
safe, fast, productive.
Pick three.
Duct tape.";
        assert_eq!(search(query, contents), vec!["safe, fast, productive."]);
    }
}
```

运行`cargo test`结果：

```shell
[MacOS-xd@qxd ➜ minigrep git:(master) ✗ ]$ cargo test
   Compiling minigrep v0.1.0 (/Users/xd/Documents/workspace/src/rust_path/rust_learning/minigrep)
    Finished `test` profile [unoptimized + debuginfo] target(s) in 1.09s
     Running unittests src/lib.rs (target/debug/deps/minigrep-4f47be9d45c4d8b6)

# 可看到运行了一个单元测试
running 1 test
test tests::one_result ... ok

# 统计执行情况
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s

# 下面还会检查 src/bin/main1.rs、main2.rs ... 等文件中是否有单元测试，如果有则运行
...
```

## 6. 小结

通过demo项目实践，对前面涉及的Rust基础语法和部分高级特性有了进一步的体感。前面看起来都懂了但是写起来还是得回头翻，果然还是需要多动手，做会而不是看会。

前面章节列的进一步功能需求，暂未实现，后续考虑继续完善。

## 7. 参考

1、[入门实战：文件搜索工具](https://course.rs/basic-practice/intro.html)

2、[Module std::env](https://doc.rust-lang.org/std/env/index.html)

3、[如何在 Rust 中编写测试代码](https://course.rs/test/intro.html)
