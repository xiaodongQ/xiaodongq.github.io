---
layout: post
title: CPU及内存调度（三） -- tcmalloc、jemalloc内存分配器
categories: CPU及内存调度
tags: 内存
---

* content
{:toc}

梳理 ptmalloc、tcmalloc 和 jemalloc 内存分配器，并进行相关实验，工具：[Massif](https://valgrind.org/docs/manual/ms-manual.html)、[AddressSanitizer](https://github.com/google/sanitizers/wiki/AddressSanitizer)。



## 1. 背景

[CPU及内存调度（二） -- Linux内存管理](https://xiaodongq.github.io/2025/03/20/memory-management/) 中梳理学习了Linux的虚拟内存结构，以及进程、线程创建时的大致区别，本篇梳理 ptmalloc、tcmalloc和 jemalloc 几个内存分配器。

并利用 [Massif](https://valgrind.org/docs/manual/ms-manual.html)、[AddressSanitizer](https://github.com/google/sanitizers/wiki/AddressSanitizer) 进行内存相关实验。

找到几篇文章也学习一下：

* [ptmalloc、tcmalloc与jemalloc对比分析](https://www.cyningsun.com/07-07-2018/memory-allocator-contrasts.html)
* [使用 jemalloc profile memory](https://www.jianshu.com/p/5fd2b42cbf3d)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 说明

Go 使用 `tcmalloc` 作为内存分配器
Rust 使用 `jemalloc` 作为内存分配器

## 2. 小结



## 3. 参考


