---
layout: _post
title: 内存调试检测工具Valgrind简介
categories: C/C++
tags: 内存泄漏
---

* content
{:toc}

[应用Valgrind发现Linux程序的内存问题](https://www.ibm.com/developerworks/cn/linux/l-cn-valgrind/)

Valgrind是一款用于内存调试、内存泄漏检测以及性能分析的软件开发工具。Valgrind这个名字取自北欧神话中英灵殿的入口。

使用gcc -g编译源程序，执行 valgrind executename查看检测输出。
