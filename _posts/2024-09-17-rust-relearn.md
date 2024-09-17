---
layout: post
title: Rust学习实践（一） -- Rust基本使用
categories: Rust
tags: Rust
---

* content
{:toc}

Rust学习实践，本篇为开篇，介绍。



## 1. 背景

之前学过Rust基本使用，间隔时间有点长且实践较少，遗忘了很多，重新学习一下。

Rust的优势此处不做过多描述，可参见这篇介绍（“自夸”）：[进入 Rust 编程世界](https://course.rs/into-rust.html)

前面还留了不少坑待填，暂时放一放：

* 网络方面，[TCP发送接收过程（二） -- 实际案例看TCP性能和窗口、Buffer的关系拥塞](https://xiaodongq.github.io/2024/07/02/tcp-window-size-case/) 占了坑但一直还没去实践：BDP，结合Wireshark的TCP Stream Graghs看网络性能变化
* 6.824，目前只看了MapReduce、GFS、Raft的论文和课程，还没做lab，以及结合Go相关特性实验，etcd/braft的raft实现待看
* 深入MySQL系列还未完结又开新坑，[MySQL学习实践（三） -- MySQL索引](https://xiaodongq.github.io/2024/09/15/mysql-index/) 目前（9.17）只梳理了小部分，而且其他内容还有不少
* 关于基础，网络、存储目前还算看了一些，CPU（进程）、内存还没投入进去看
* ...

几点随想：

* 之前看文章看到[Draven](https://draveness.me/)大佬[2020总结](https://draveness.me/2020-summary/)里提到用`OKR`管理个人目标，正好在尝试用工作上的Scrum敏捷模式管理自己的工作以外部分事项的进度，收获不少，自己后续也可以这个方式调整下（OKR+Scrum）
    * [如何管理自己的时间资产](https://draveness.me/few-words-time-management/)
* 看[木鸟杂记](https://www.qtmuniao.com/)大佬的文章，提到[课代表立正](https://space.bilibili.com/491306902/)，去看了下up主讲的一些方法论和思路，让自己的想法拓展和清晰不少，也很有收获，工作/学习/生活里可以借鉴参考
* 想法：多输入，多输出，产生正循环，让“飞轮”滚动起来

学习实践环境说明：

* Mac：原来学习时是`rustc 1.44.0`（2020），升级一下：`rustup update`，升级后当前版本为`rustc 1.81.0`（2024-09-04）
* CentOS 8.5：[之前](https://xiaodongq.github.io/2024/06/12/record-failed-expend-space/)重装过系统，这次安装下rust
    * `curl https://sh.rustup.rs -sSf | sh`，安装的版本也是当前最新的stable版本：`rust version 1.81.0 (eeb90cda1 2024-09-04)`

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 学习参考资料

**网站：**

* [官网](https://www.rust-lang.org/zh-CN/)
* [官方GitHub](https://github.com/rust-lang)
* [官网-Learn Rust](https://www.rust-lang.org/zh-CN/learn) 里面推荐了一些开源学习资料，包括下面的一些开源书籍
    * 核心文档
        * [标准库](https://doc.rust-lang.org/std/index.html)：详尽的 Rust 标准库 API 手册
        * [Rust 版本指南](https://doc.rust-lang.org/edition-guide/index.html)：介绍各版本特性及兼容性说明
        * [Cargo手册](https://doc.rust-lang.org/cargo/index.html)：Rust包管理器使用指南
        * [rustdoc手册](https://doc.rust-lang.org/rustdoc/index.html)：编写规范的Rust项目文档
        * [rustc手册](https://doc.rust-lang.org/rustc/index.html)：Rust编译器使用指南，理解各选项含义
        * [编译错误索引表](https://doc.rust-lang.org/error_codes/error-index.html)：可能会遇到的编译错误

一、基础内容

* [The Rust Programming Language](https://doc.rust-lang.org/book/)
    * 中文版：[Rust 程序设计语言](https://kaisery.github.io/trpl-zh-cn/title-page.html)
    * 《Rust 程序设计语言》被亲切地称为“圣经”
* [Rust开源教程](https://course.rs/about-book.html)
* [Rust Cookbook](https://rust-lang-nursery.github.io/rust-cookbook/)
    * [中文版](https://rustwiki.org/zh-CN/rust-cookbook/)

* 极客时间：[陈天 · Rust 编程第一课](https://time.geekbang.org/column/article/408400)
* [rust常用的crates](https://github.com/daheige/rs-cookbook?tab=readme-ov-file#rust%E5%B8%B8%E7%94%A8%E7%9A%84crates)

二、进阶

* [The Rustonomicon](https://doc.rust-lang.org/nomicon/)
    * 中文版：[Rust 秘典（死灵书）](https://nomicon.purewhite.io/intro.html)
    * 《Rust 秘典》是 Unsafe Rust 的黑魔法指南。它有时被称作“死灵书”
* [Rust官方RFC文档](https://github.com/rust-lang/rfcs)
* [Rust设计模式](https://rust-unofficial.github.io/patterns/)
    * [中文版](https://chuxiuhong.com/chuxiuhong-rust-patterns-zh/)

## 3. 小结


## 4. 参考

1、[学习 Rust](https://www.rust-lang.org/zh-CN/learn)

2、[进入 Rust 编程世界](https://course.rs/into-rust.html)

