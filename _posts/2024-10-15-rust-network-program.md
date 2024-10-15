---
layout: post
title: Rust学习实践（七） -- Rust网络编程和Demo
categories: Rust
tags: Rust
---

* content
{:toc}

Rust学习实践，学习Rust网络编程，并编写Web服务器Demo。



## 1. 背景

继续进一步学习下Rust特性，本篇学习Rust网络编程，并编写Web服务器Demo。

分别基于多线程和async/await实现。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. Rust网络模块

标准库中的网络模块：[std::net](https://doc.rust-lang.org/std/net/index.html)，提供了 TCP/UDP 通信的网络原语。主要内容如下：

* `TcpListener` 和 `TcpStream` (均为`struct`) 提供了通过 `TCP` 进行通信的功能
* `UdpSocket` 提供通过 `UDP` 进行通信的功能
* `IpAddr` 代表 `IPv4` 或 `IPv6` 的 IP 地址； `Ipv4Addr` 和 `Ipv6Addr` 分别是 `IPv4` 和 `IPv6` 地址
* `SocketAddr` 代表 `IPv4` 或 `IPv6` 的套接字地址； `SocketAddrV4` 和 `SocketAddrV6` 分别是 `IPv4` 和 `IPv6` 套接字地址
* `ToSocketAddrs` 特征(trait)，用于网络交互时的通用地址解析

详情参考：[std::net](https://doc.rust-lang.org/std/net/index.html) 或 [标准库中文翻译 -- std::net](https://rustwiki.org/zh-CN/std/net/index.html)，尽量基于英文原链接学习。

此处先只关注基于TCP的网络服务，学习 `TcpListener` 和 `TcpStream` 用法。

下述涉及代码，也可见：[test_network](https://github.com/xiaodongQ/rust_learning/tree/master/test_network)

### 2.1. TcpListener 和 TcpStream

参考学习标准库：[TcpListener](https://doc.rust-lang.org/std/net/struct.TcpListener.html)。扩展了解：[TCP协议 -- rfc793](https://datatracker.ietf.org/doc/html/rfc793)。

`TcpListener`创建时通过`bind`接口绑定一个socket地址，其会自动监听TCP连接的输入，  
并可通过`accept`接口 或 `incoming`接口返回的迭代器（`Incoming`类型）来进行接收处理。

示例：（其中用到`std::io::BufReader`进行数据处理）

```rust
use std::net::{TcpListener, TcpStream};
use std::io::{BufReader, prelude::*};

fn handle_client(stream: TcpStream) {
    let buf_reader = BufReader::new(& stream);
    let http_request: Vec<_> = buf_reader
        .lines()
        .map(|result| result.unwrap())
        .take_while(|line| !line.is_empty())
        .collect();

    println!("Request: {:#?}", http_request);
}

fn main() -> std::io::Result<()> {
    let listener = TcpListener::bind("127.0.0.1:80")?;

    // accept connections and process them serially
    for stream in listener.incoming() {
        let stream = stream.unwrap();
        handle_client(stream);
    }
    Ok(())
}
```

先编译再运行，并在浏览器访问：`localhost:80`，可看到服务端收到了请求，由于没有应答信息，浏览器会提示异常


```shell
[MacOS-xd@qxd ➜ test_network git:(master) ✗ ]$ cargo build
   Compiling test_network v0.1.0 (/Users/xd/Documents/workspace/src/rust_path/rust_learning/test_network)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.70s

# 由于在本地Mac运行，不加sudo无权限监听：
[MacOS-xd@qxd ➜ test_network git:(master) ✗ ]$ ./target/debug/test_network 
Error: Os { code: 13, kind: PermissionDenied, message: "Permission denied" }

# 加sudo运行
[MacOS-xd@qxd ➜ test_network git:(master) ✗ ]$ sudo ./target/debug/test_network
# 在浏览器访问： localhost:80，服务端打印如下（间隔一段时间浏览器会重试，下面会重复打印）
Request: [
    "GET / HTTP/1.1",
    "Host: localhost",
    "Connection: keep-alive",
    "Cache-Control: max-age=0",
    "sec-ch-ua: \"Google Chrome\";v=\"129\", \"Not=A?Brand\";v=\"8\", \"Chromium\";v=\"129\"",
    "sec-ch-ua-mobile: ?0",
    "sec-ch-ua-platform: \"macOS\"",
    "DNT: 1",
    "Upgrade-Insecure-Requests: 1",
    "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36",
    "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
    "Sec-Fetch-Site: none",
    "Sec-Fetch-Mode: navigate",
    "Sec-Fetch-User: ?1",
    "Sec-Fetch-Dest: document",
    "Accept-Encoding: gzip, deflate, br, zstd",
    "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8,zh-TW;q=0.7,ja;q=0.6",
]
```


## 3. 小结


## 4. 参考

1、[Rust语言圣经(Rust Course) -- 实践应用：多线程Web服务器](https://course.rs/advance-practice1/intro.html)

2、[std::net](https://doc.rust-lang.org/std/net/index.html)

3、[标准库中文翻译 -- std::net](https://rustwiki.org/zh-CN/std/net/index.html)

4、[TcpListener](https://doc.rust-lang.org/std/net/struct.TcpListener.html)
