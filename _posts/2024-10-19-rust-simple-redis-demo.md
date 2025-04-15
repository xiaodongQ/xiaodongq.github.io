---
title: Rust学习实践（八） -- Demo项目：实现简易Redis
categories: [编程语言, Rust]
tags: Rust
---

Rust学习实践，实现简易Redis Demo，学习`tokio`异步运行时用法。

## 1. 背景

实践Demo：实现简易Redis Demo，学习`tokio`异步运行时用法。

参考：

* [Rust语言圣经(Rust Course) -- 进阶实战: 实现一个简单 redis](https://course.rs/advance-practice/intro.html)
* 也可见tokio官网教程：[hello-tokio](https://tokio.rs/tokio/tutorial/hello-tokio)

下面的练习代码可见：[my-redis demo](https://github.com/xiaodongQ/rust_learning/tree/master/demo/my-redis)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 目录结构和客户端

1、demo的目录结构：

```sh
[MacOS-xd@qxd ➜ my-redis git:(master) ✗ ]$ tree -L 2
.
├── Cargo.lock
├── Cargo.toml
├── examples
│   └── hello_redis.rs
├── src
└── target
    ├── CACHEDIR.TAG
    └── debug
```

**cargo使用说明：**

* `Crate`被翻译为`包`，`Package`就不能也称为"包"了，可理解为`项目`、`工程`。`cargo new`创建的就是`Package`，称作创建新项目。
* cargo项目中的目录结构还有`benches`、`tests`等，具体可查看 [典型的 Cargo Package 目录结构](https://course.rs/cargo/guide/package-layout.html)

2、在Cargo.toml中，添加依赖：`tokio`、`mini-redis`：

```toml
[package]
name = "my-redis"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version="1",  features = ["full"] }
mini-redis = "0.4"
```

3、简单客户端 `hello_redis.rs`：

```rust
use mini_redis::{client, Result};

// 通过该属性（实际是个宏），标记为 异步main函数
#[tokio::main]
async fn main() -> Result<()> {
    // 和服务端建立连接
    // mini-redis提供的client::connect函数也是一个async函数，返回一个 Future（实现了该特征的类型）
    let mut client = client::connect("127.0.0.1:6379").await?;

    // 设置值
    client.set("hello", "world".into()).await?;
    // 获取值
    let result = client.get("hello").await?;
    println!("get result:{:?}", result);

    Ok(())
}
```

可通过 `--example` 选项来 编译(`build`) 或 运行(`run`) 示例对象（examples target）：

```sh
[MacOS-xd@qxd ➜ my-redis git:(master) ✗ ]$ cargo run --example hello_redis
   Compiling my-redis v0.1.0 (/Users/xd/Documents/workspace/src/rust_path/rust_learning/demo/my-redis)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 1.54s
     Running `target/debug/examples/hello_redis`
get result:Some(b"world")
```

Cargo有**对象自动发现**机制，基于目录布局发现和确定对象；也可以在Cargo.toml里显式添加`[[example]]`（大部分时候不需要）。

**Cargo.toml 清单说明：**

* Cargo.toml 又被称为清单(`manifest`)，文件格式是 TOML
* `[package]` Cargo.toml 中第一个部分就是 package，用于设置项目的相关信息
* `[dependencies]` 项目依赖包
* Cargo Target 列表
    * `[lib]` 库对象设置（Library targe）
        * 一个项目中只能指定一个库对象
    * `[[bin]]` 二进制对象设置（Binary target）
        * toml数组，一个项目中可以指定多个bin、example、test等
    * `[[example]]` 示例对象设置（Example target）
    * `[[test]]` 集成测试设置（Test target）
    * `[[bench]]` 基准测试设置（Benchmark target）
* 可进一步参考 [Cargo.toml 格式讲解](https://course.rs/cargo/reference/manifest.html) 和 [Cargo Target](https://course.rs/cargo/reference/cargo-target.html)

> 默认情况下，Cargo 会基于项目的目录文件布局自动发现和确定对象，而之前的配置项则允许我们对其进行手动的配置修改(若项目布局跟标准的不一样时)。
>
> 大部分时候都无需手动配置，因为默认的配置通常由项目目录的布局自动推断出来。

## 3. 服务端

> Tokio 中大多数类型的名称都和标准库中对应的同步类型名称相同，而且，如果没有特殊原因，Tokio 的 API 名称也和标准库保持一致，只不过用 `async fn` 取代 `fn` 来声明函数。

[上一篇](https://xiaodongq.github.io/2024/10/15/rust-network-program/)学习过标准库的 `TcpListener` 和 `TcpStream`（`std::net`）。

对应`tokio`用的是 `tokio::net::TcpListener` 和 `tokio::net::TcpStream`。

### 3.1. 基本通信流程

本节暂时先完成 接收 和 简单应答 的基本通信流程：

```rust
use tokio::net::{TcpListener, TcpStream};
use mini_redis::{Connection, Frame};

#[tokio::main]
async fn main() {
    let listener = TcpListener::bind("127.0.0.1:6379").await.unwrap();
    loop {
        let (socket, _) = listener.accept().await.unwrap();
        process(socket).await;
    }
}

async fn process(socket: TcpStream) {
    let mut connection = Connection::new(socket);
    if let Some(frame) = connection.read_frame().await.unwrap() {
        println!("GOT: {:?}", frame);

        // 回复
        let response = Frame::Error("unimplemented".to_string());
        connection.write_frame(&response).await.unwrap();
    }
}
```

### 3.2. key-value实现

把上面实现移到bin下面：`mkdir bin; mv main.rs bin/simple_server.rs`，并在main.rs里实现基本的`key-value`操作：

```rust
// demo/my-redis/src/main.rs
// ...（其他内容暂省略）
async fn process(socket: TcpStream) {
    use mini_redis::Command::{self, Get, Set};
    use std::collections::HashMap;

    // 使用 hashmap 来存储 redis 的数据
    let mut db = HashMap::new();

    // `mini-redis` 提供的便利函数，使用返回的 `connection` 可以用于从 socket 中读取数据并解析为数据帧
    let mut connection = Connection::new(socket);

    // 使用 `read_frame` 方法从连接获取一个数据帧：一条redis命令 + 相应的数据
    while let Some(frame) = connection.read_frame().await.unwrap() {
        let response = match Command::from_frame(frame).unwrap() {
            Set(cmd) => {
                // 值被存储为 `Vec<u8>` 的形式
                db.insert(cmd.key().to_string(), cmd.value().to_vec());
                Frame::Simple("OK".to_string())
            }
            Get(cmd) => {
                if let Some(value) = db.get(cmd.key()) {
                    // `Frame::Bulk` 期待数据的类型是 `Bytes`， 该类型会在后面章节讲解，
                    // 此时，你只要知道 `&Vec<u8>` 可以使用 `into()` 方法转换成 `Bytes` 类型
                    Frame::Bulk(value.clone().into())
                } else {
                    Frame::Null
                }
            }
            cmd => panic!("unimplemented {:?}", cmd),
        };

        // 将请求响应返回给客户端
        connection.write_frame(&response).await.unwrap();
    }
}
```

## 4. 小结

跟着参考链接学习实践简单redis demo，同时了解典型cargo项目结构和规范。当前仅实践了一部分，其他部分涉及特性和功能在后续进一步学习实践。

这篇开篇到现在，耗时比较久了（近期投入了一些时间在 [LeetCode刷题学习（二） -- 数组篇](https://xiaodongq.github.io/2000/01/01/leetcode-2-array/)）。后面还有几个练习demo，要加快点节奏，快速过完后开启新的篇章。

## 5. 参考

1、[Rust语言圣经(Rust Course) -- 进阶实战: 实现一个简单 redis](https://course.rs/advance-practice/intro.html)

2、[典型的 Cargo Package 目录结构](https://course.rs/cargo/guide/package-layout.html)

3、[Cargo.toml 格式讲解](https://course.rs/cargo/reference/manifest.html)

4、[Cargo Target对象](https://course.rs/cargo/reference/cargo-target.html)

5、[hello-tokio](https://tokio.rs/tokio/tutorial/hello-tokio)
