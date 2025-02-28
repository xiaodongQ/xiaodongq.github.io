---
layout: post
title: 梳理redis和nginx中的epoll机制
categories: 网络
tags: 网络 epoll redis nginx
---

* content
{:toc}

梳理学习 redis 和 nginx 中的epoll机制。



## 1. 背景

[前面](https://xiaodongq.github.io/2025/02/25/ioserver2-epoll-dive/)的ioserver demo中进行了基本的epoll机制使用和学习，并梳理了开源网络库 muduo 的muduo使用和线程池实现。

本篇继续学习epoll在redis和nginx中的使用。跟踪的源码分支保持和对比本地CentOS8环境安装的服务版本一致。

参考：

* [深度解析单线程的 Redis 如何做到每秒数万 QPS 的超高处理能力！](https://mp.weixin.qq.com/s/2y60cxUjaaE2pWSdCBX1lA)
    * 说明：redis 6.0后支持了多线程，可参考学习：[Redis 6 中的多线程是如何实现的！？](https://mp.weixin.qq.com/s/MU8cxoKS3rU9mN_CY3WxWQ)
* [redis 5.0.3源码](https://github.com/redis/redis/tree/5.0.3)
* [万字多图，搞懂 Nginx 高性能网络工作原理！](https://mp.weixin.qq.com/s/AX6Fval8RwkgzptdjlU5kg)
* [nginx 1.14源码](https://github.com/nginx/nginx/tree/stable-1.14)

## 2. redis中的epoll流程

## 3. nginx中的epoll流程

## 4. 小结


## 5. 参考

* [深度解析单线程的 Redis 如何做到每秒数万 QPS 的超高处理能力！](https://mp.weixin.qq.com/s/2y60cxUjaaE2pWSdCBX1lA)
* [redis 5.0.3源码](https://github.com/redis/redis/tree/5.0.3)
* [万字多图，搞懂 Nginx 高性能网络工作原理！](https://mp.weixin.qq.com/s/AX6Fval8RwkgzptdjlU5kg)
* [nginx 1.14源码](https://github.com/nginx/nginx/tree/stable-1.14)

