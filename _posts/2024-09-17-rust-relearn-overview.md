---
layout: post
title: Rust学习实践（一） -- 总体说明和基本使用
categories: Rust
tags: Rust
---

* content
{:toc}

Rust学习实践，本篇为开篇，总体说明和基本使用。



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
* [学习Rust](https://www.rust-lang.org/zh-CN/learn) 里面推荐了一些开源学习资料，包括下面的一些开源书籍
    * 核心文档
        * [标准库](https://doc.rust-lang.org/std/index.html)：详尽的 Rust 标准库 API 手册
        * [Rust 版本指南](https://doc.rust-lang.org/edition-guide/index.html)：介绍各版本特性及兼容性说明
        * [Cargo手册](https://doc.rust-lang.org/cargo/index.html)：Rust包管理器使用指南
        * [rustdoc手册](https://doc.rust-lang.org/rustdoc/index.html)：编写规范的Rust项目文档
        * [rustc手册](https://doc.rust-lang.org/rustc/index.html)：Rust编译器使用指南，理解各选项含义
        * [编译错误索引表](https://doc.rust-lang.org/error_codes/error-index.html)：可能会遇到的编译错误

一、基础内容

* [The Rust Programming Language](https://doc.rust-lang.org/book/)
    * 中文翻译版：[Rust 程序设计语言](https://kaisery.github.io/trpl-zh-cn/)
        * `Rustacean`中文意思为 Rust 开发者，Rust 用户，Rust 爱好者。注意，Rust开发者**不要**写成 `Ruster`，另外 Rustacean 一般第一个字母为大写形式，就和 Rust 一样，[参考](https://rustwiki.org/wiki/translate/other-translation/#the-rust-programing-language)
    * 《Rust 程序设计语言》被亲切地称为“圣经”，其中文出版书名为《Rust 权威指南》
* [Rust开源教程：Rust Course](https://course.rs/about-book.html)
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

## 3. Rust基础

前置说明：

* 1、基于《Rust 程序设计语言》（中文版：[Rust 程序设计语言](https://kaisery.github.io/trpl-zh-cn/)）大概过一下，之前的初步学习笔记在：[Rust.md](https://github.com/xiaodongQ/devNoteBackup/blob/master/%E5%90%84%E5%88%86%E7%B1%BB%E8%AE%B0%E5%BD%95/Rust/Rust.md)
* 2、上述资料大概看了一下，[Rust开源教程：Rust Course](https://course.rs/about-book.html) 的内容比较贴合自己当前的偏好，先基于该教程学习梳理，其他作为辅助。
* 3、代码练习还是复用之前的仓库：[rust_learning](https://github.com/xiaodongQ/rust_learning)
* 4、VSCode插件（《Rust编程第一课》中推荐的插件）
    + `rust-analyzer`：它会实时编译和分析你的 Rust 代码，提示代码中的错误，并对类型进行标注。你也可以使用官方的 Rust 插件取代。
        + 官方的`Rust`插件已经不维护了
    + ~~`crates`~~ `Dependi`：帮助你分析当前项目的依赖是否是最新的版本。
        + crates插件已经不维护了，主页中推荐切换为`Dependi`，支持多种语言的依赖管理：Rust, Go, JavaScript, TypeScript, Python and PHP
    + ~~`better toml`~~ `Even Better TOML`：Rust 使用 toml 做项目的配置管理。该插件可以帮你语法高亮，并展示 toml 文件中的错误。
        + better toml插件也不维护了，其主页推荐切换为`Even Better TOML`
    + 其他插件，暂不安装
        + `rust syntax`：为代码提供语法高亮（有必要性？前面插件会提供语法高亮）
        + `rust test lens`：rust test lens：可以帮你快速运行某个 Rust 测试（也不维护了）
        + `Tabnine`：基于 AI 的自动补全，可以帮助你更快地撰写代码（暂时用的`CodeGeeX`，当作`Copilot`平替）

### 3.1. 编译说明

* `rustc`方式：`rustc main.rs`
* `cargo`方式：`cargo build`编译、`cargo run`运行（若未编译则会先编译）、`cargo check`只检查不编译

以 [hello_cargo](https://github.com/xiaodongQ/rust_learning/tree/master/hello_cargo) 为例，说明下cargo编译生成的内容：

* `Cargo.lock`：记录了所有直接依赖和间接依赖的确切版本，确保了项目的依赖关系在每次构建时都保持一致
* `target目录`：这是Cargo用来存放所有编译输出的地方
    * `CACHEDIR.TAG`：一个特殊的文件，用来标记这个目录是一个缓存目录，不应该被包含在版本控制中
    * `debug`或者`release`：分别对应debug模式和release模式，debug模式会包含调试信息，release模式则会进行优化
    * `debug/deps`目录：存放了所有依赖的编译输出，包含二进制文件（`hello_cargo-70b7650f2196efb1`和`debug/hello_cargo`是同一个文件）
    * `target/debug/build`目录：若toml里通过`build`指定了构建脚本，则对应输出会在该目录
    * `target/debug/examples`目录：如果项目包含示例程序（在examples目录下的.rs文件），那么这些程序会被编译并放置在这个目录下
    * `target/debug/hello_cargo`：项目的主可执行文件
    * `target/debug/incremental`：该目录存储了增量编译的信息，使得Cargo能够在再次编译时跳过那些没有变化的代码部分，从而加快编译速度
    * `target/debug/hello_cargo.d` 和其他`.d`文件：这些文件用于支持增量编译。它们记录了编译过程中的依赖关系，帮助Cargo决定哪些模块需要重新编译

```sh
# build编译前
[CentOS-root@xdlinux ➜ hello_cargo git:(master) ✗ ]$ tree 
.
├── Cargo.toml
└── src
    └── main.rs

# cargo build
[CentOS-root@xdlinux ➜ hello_cargo git:(master) ✗ ]$ cargo build
   Compiling hello_cargo v0.1.0 (/home/workspace/rust_path/rust_learning/hello_cargo)
    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.19s
[CentOS-root@xdlinux ➜ hello_cargo git:(master) ✗ ]$ tree
.
├── Cargo.lock
├── Cargo.toml
├── src
│   └── main.rs
└── target
    ├── CACHEDIR.TAG
    └── debug
        ├── build
        ├── deps
        │   ├── hello_cargo-70b7650f2196efb1
        │   └── hello_cargo-70b7650f2196efb1.d
        ├── examples
        ├── hello_cargo
        ├── hello_cargo.d
        └── incremental
            └── hello_cargo-3haf20exhib74
                ├── s-h00uhsc9pb-05zloq4-45etctwclne9bdzz71m5zmpm7
                │   ├── 0bcqf7ztek5t6s4d87ed816uz.o
                │   ├── 0vf1n5voilrp7673zix3s1mk8.o
                │   ├── 48zynk25prcjtyan91sp1xfvo.o
                │   ├── 53zmz46glgdq0hhcx61nbxdn6.o
                │   ├── 61k02pkquc42pjwqtetozi8sf.o
                │   ├── 6oeh93pcajoe4x07y2xnxmueg.o
                │   ├── 76cr3fg6p6n8csy70e1d5ugvs.o
                │   ├── al8okrhaqv7m0kggosakeijdw.o
                │   ├── b4wsfus5ugvvekyy3brvvakrf.o
                │   ├── dep-graph.bin
                │   ├── dqqzbj9vq1ggxsduc75riz3xs.o
                │   ├── e39bv2imh011dqqelnop4qaf6.o
                │   ├── query-cache.bin
                │   └── work-products.bin
                └── s-h00uhsc9pb-05zloq4.lock

9 directories, 23 files
```

结果物说明：相对于go编译产物，rust运行时还是需要依赖系统libc库（go自带运行时库，不需要libc库）

## 4. 小结


## 5. 参考

1、[学习 Rust](https://www.rust-lang.org/zh-CN/learn)

2、[进入 Rust 编程世界](https://course.rs/into-rust.html)

3、[陈天 · Rust 编程第一课](https://time.geekbang.org/column/article/408400)