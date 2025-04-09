---
layout: post
title: CPU及内存调度（五） -- ptmalloc、tcmalloc、jemalloc、mimalloc内存分配器（下）
categories: CPU及内存调度
tags: 内存
---

* content
{:toc}

继续梳理 ptmalloc、tcmalloc、jemalloc 和 mimalloc 内存分配器。



## 1. 背景

上篇梳理了dlmalloc和ptmalloc，继续来看tcmalloc、jemalloc 和 mimalloc几个分配器。

结合源码和几篇参考文章：

* tcmalloc
    * 基于2.7.90分支：[gperftools-2.7.90](https://github.com/gperftools/gperftools/tree/gperftools-2.7.90)
    * [记一次 TCMalloc Debug 经历 #2](https://zhuanlan.zhihu.com/p/81683409)
* jemalloc
    * [Jemalloc内存分配与优化实践](https://mp.weixin.qq.com/s/U3uylVKZ-FsMjdeX3lymog)
* [ptmalloc、tcmalloc与jemalloc对比分析](https://www.cyningsun.com/07-07-2018/memory-allocator-contrasts.html)
* [内存分配器ptmalloc,jemalloc,tcmalloc调研与对比](https://geekdaxue.co/read/ixxw@it/memory_allocators)
    * 原文是：[内存分配器ptmalloc,jemalloc,tcmalloc调研与对比](https://blog.csdn.net/Rong_Toa/article/details/110689404)

## 2. tcmalloc

上述 [记一次 TCMalloc Debug 经历 #2](https://zhuanlan.zhihu.com/p/81683409) 中`dlopen`和`tcmalloc`的死锁问题，在2.7.90分支修复了。

本篇分析的代码分支和自己本地的CentOS8对应版本保持一致：

```sh
[CentOS-root@xdlinux ➜ ~ ]$ rpm -qa|grep gperf
gperftools-devel-2.7-9.el8.x86_64
gperftools-2.7-9.el8.x86_64
gperftools-libs-2.7-9.el8.x86_64
```



## 3. jemalloc


## 4. 小结


## 5. 参考

* [gperftools-2.7.90](https://github.com/gperftools/gperftools/tree/gperftools-2.7.90)
* [记一次 TCMalloc Debug 经历 #2](https://zhuanlan.zhihu.com/p/81683409)
* [ptmalloc、tcmalloc与jemalloc对比分析](https://www.cyningsun.com/07-07-2018/memory-allocator-contrasts.html)
* [内存分配器ptmalloc,jemalloc,tcmalloc调研与对比](https://geekdaxue.co/read/ixxw@it/memory_allocators)
* LLM
