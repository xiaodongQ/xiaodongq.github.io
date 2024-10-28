---
layout: post
title: Rust学习实践（九） -- Demo项目：几个Demo练习
categories: Rust
tags: Rust
---

* content
{:toc}

Rust学习实践，几个Demo练习。



## 1. 背景

跟着 [陈天 · Rust 编程第一课](https://time.geekbang.org/column/article/408400) 中的几个Demo学习实践：

* HTTPie小工具 Demo
* 简易图片服务器 Demo
* SQL查询工具 Demo

学习一些实用的第三方库，另外也可了解 [日常开发三方库精选](https://course.rs/practice/third-party-libs.html)。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. HTTPie小工具

### 2.1. 说明

> [HTTPie](https://httpie.io/) 是用 Python 开发的，一个类似 `cURL` 但对用户更加友善的命令行工具，它可以帮助我们更好地诊断 HTTP 服务。

专栏的github仓库：[04_httpie](https://github.com/tyrchen/geektime-rust/tree/master/04_httpie)

需要用到的库：

* 命令行解析：[clap](https://github.com/clap-rs/clap)
* HTTP客户端：[reqwest](https://github.com/seanmonstar/reqwest)
* 终端格式化输出，支持多彩显示的库：[colored](https://github.com/colored-rs/colored)
* 错误处理：[anyhow](https://github.com/dtolnay/anyhow)
* JSON格式化：[jsonxf](https://github.com/gamache/jsonxf)
* mime类型处理：[mime](https://github.com/hyperium/mime)
* 异步处理：[tokio](https://github.com/tokio-rs/tokio)

### 2.2. 练习

[代码行数统计工具 tokei](https://github.com/XAMPPRocky/tokei)，可以显示文件行、代码、评论、空格行等。


## 3. 简易图片服务器

## 4. SQL查询小工具

## 5. 小结

## 6. 参考

1、[陈天 · Rust 编程第一课](https://time.geekbang.org/column/article/408400) 

2、GPT
