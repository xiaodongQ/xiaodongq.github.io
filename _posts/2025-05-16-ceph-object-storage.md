---
title: Ceph学习笔记（三） -- Ceph对象存储
description: 梳理Ceph对象存储和相关流程。
categories: [存储和数据库, Ceph]
tags: [存储, Ceph]
---


## 1. 引言

前面梳理了Ceph的基本架构，并简单搭建了Ceph集群。现在进入到代码层，对Ceph功能进行进一步深入，本篇梳理 **<mark>对象存储</mark>**，并跟踪梳理代码处理流程。

## 2. 简要介绍

Ceph`对象存储`包含一个`Ceph存储集群`和一个`对象网关`（Ceph Object Gateway）。

* **Ceph存储集群**：如前面 [Ceph集群构成](https://xiaodongq.github.io/2025/05/03/ceph-overview/#22-ceph%E9%9B%86%E7%BE%A4%E6%9E%84%E6%88%90) 中所述，一个Ceph存储集群中至少包含`monitor`、`manager`、`osd`，文件存储则还包含`mds`。
* **对象网关**：构建在`librados`之上，通过`radosgw`守护进程提供服务，为应用程序提供对象存储`RESTful API`，用于操作Ceph存储集群。

支持两种接口，两者共享一个命名空间（namespace），意味着一类接口写的数据可以通过另一类接口读取。

* `S3`兼容接口，Amazon S3 RESTful API
* `Swift`兼容接口，OpenStack Swift API

![ceph-object-storage](/images/ceph-object-storage.png)

## 3. 小结


## 4. 参考

* [Ceph Object Gateway](https://docs.ceph.com/en/squid/radosgw/#object-gateway)
* [Ceph Git仓库](https://github.com/ceph/ceph)
* LLM