---
layout: _post
title: Rust学习实践（七） -- Rust网络编程和Demo
categories: Rust
tags: Rust
---

* content
{:toc}

Rust学习实践，学习Rust网络编程，并编写Web服务器Demo。



## 1. 背景

继续进一步学习下Rust特性，本篇学习Rust网络编程，并编写Web服务器Demo。

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
        .lines()                              // lines 方法来获取一个迭代器，会按行读取`buf_reader`中的数据
        .map(|result| result.unwrap())        // `map` 操作将 `Result<String>` 类型的项转换为 `String`
        .take_while(|line| !line.is_empty())  // 过滤掉所有在空行之前的项。当遇到空行时，停止读取
        .collect();                           // 剩余的行收集到一个 `Vec<String>`

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

## 3. 单线程webserver

上述代码补全逻辑后的demo：单线程解析请求，并根据不同请求内容，返回不同页面提示

完整代码可见：[web_single_thread.rs](https://github.com/xiaodongQ/rust_learning/tree/master/test_network/src/bin/web_single_thread.rs)

```rust
fn handle_client(mut stream: TcpStream) {
    let buf_reader = BufReader::new(& stream);
    let http_request: Vec<_> = buf_reader
        .lines()
        .map(|result| result.unwrap())
        .take_while(|line| !line.is_empty())
        .collect();
    println!("Request: {:#?}", http_request);

    // 读取请求中的第一行
    let request_line = &http_request[0];
    println!("request_line: {:#?}", request_line);

    let (status_line, filename) = if request_line == "GET / HTTP/1.1" {
        ("HTTP/1.1 200 OK", "hello.html")
    } else {
        ("HTTP/1.1 404 NOT FOUND", "404.html")
    };

    // 应答
    // hello.html和404.html放到cargo项目的根目录
    let contents = std::fs::read_to_string(filename).unwrap();
    let length = contents.len();

    let response =
        format!("{status_line}\r\nContent-Length: {length}\r\n\r\n\n{contents}");

    // write_all 方法接受 &[u8] 类型作为参数，这里需要用 as_bytes 将字符串转换为字节数组
    stream.write_all(response.as_bytes()).unwrap();
}
```

访问不支持的请求：

```shell
[MacOS-xd@qxd ➜ test_network git:(master) ✗ ]$ sudo cargo run --bin test_network
Password:
   Compiling test_network v0.1.0 (/Users/xd/Documents/workspace/src/rust_path/rust_learning/test_network)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 1.11s
     Running `target/debug/test_network`
Request: [
    "GET /sd HTTP/1.1",
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
request_line: "GET /sd HTTP/1.1"
```

浏览器应答页面：

![简单webserver-404](/images/2024-10-17-web-server-404.png)

## 4. 多线程webserver

基于线程池的多线程webserver稍微有点复杂，暂不展开，具体见：[构建多线程 Web 服务器](https://course.rs/advance-practice1/multi-threads.html)，可以看到设计迭代过程和要考虑的点。

demo练习代码见：[web_multi_thread.rs](https://github.com/xiaodongQ/rust_learning/tree/master/test_network/src/bin/web_multi_thread.rs) 和 [lib.rs](https://github.com/xiaodongQ/rust_learning/tree/master/test_network/src/lib.rs)

线程池实现在lib.rs中，main函数如下：

```rust
fn main() {
    let listener = TcpListener::bind("127.0.0.1:80").unwrap();
    let pool = ThreadPool::new(4);

    for stream in listener.incoming() {
        let stream = stream.unwrap();

        pool.execute(|| {
            handle_client(stream);
        });
    }
}
```

运行，并在浏览器请求多次：`http://localhost/`、`http://localhost/ff`，结果如下：

```shell
[MacOS-xd@qxd ➜ test_network git:(master) ✗ ]$ sudo cargo run --bin web_multi_thread
warning: `test_network` (lib) generated 2 warnings
   Compiling test_network v0.1.0 (/Users/xd/Documents/workspace/src/rust_path/rust_learning/test_network)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.76s
     Running `target/debug/web_multi_thread`

Worker 1 got a job; executing.
request_line: "GET / HTTP/1.1"
Worker 0 got a job; executing.
request_line: "GET / HTTP/1.1"
Worker 2 got a job; executing.
Worker 3 got a job; executing.
request_line: "GET /ff HTTP/1.1"
request_line: "GET / HTTP/1.1"
Worker 1 got a job; executing.
Worker 0 got a job; executing.
```

## 5. 小结

学习Rust网络模块的基本使用，跟着参考资料中的小demo进行练习。

## 6. 参考

1、[Rust语言圣经(Rust Course) -- 实践应用：多线程Web服务器](https://course.rs/advance-practice1/intro.html)

2、[std::net](https://doc.rust-lang.org/std/net/index.html)

3、[标准库中文翻译 -- std::net](https://rustwiki.org/zh-CN/std/net/index.html)

4、[TcpListener](https://doc.rust-lang.org/std/net/struct.TcpListener.html)
