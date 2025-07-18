---
title: Kubernetes学习实践（一） -- 总体说明和基本使用
description: Kubernetes学习实践，本篇进行总体说明和基本使用
categories: [云原生, Kubernetes]
tags: [云原生, Kubernetes]
---


## 1. 引言

较早前的项目中有接触过Kubernetes（/ˌkuːbərˈnɛtiːz/，下文简称`K8S`，因为中间有8个字母`ubernete`，可读作`K-eights`），之前极客上也买过课程“看”过，简单搭建过toy环境，但缺乏系统和深入梳理。近期定位一个服务上的网络问题，涉及到K8S环境的`Calico`插件，这块不是太清楚需要补缺。

K8S中包含很多技术栈，如容器、存储、网络、计算等等，信息采集/分布式链路跟踪等等，在之前的博客中也记录了不少这些基础知识相关的学习实践。趁此机会，本篇开始梳理学习K8S的基本原理和应用，过程中可在更上一层看看如何使用这些技术，同时可以补充一些比较薄弱的技能点。

部分补缺，如：
* 存储
    * overlay文件系统
    * CSI相关存储系统对接，Ceph、JuiceFS
* 网络
    * 容器网络底层原理
    * K8S网络插件、CNI
* 调度
    * K8S调度逻辑，etcd，分布式Raft

相关参考文档：
* [Kubernetes Docs](https://kubernetes.io/docs/concepts/overview/)
    * 相应的中文版本：(https://kubernetes.io/zh-cn/docs/home/)
    * [概述](https://kubernetes.io/zh-cn/docs/concepts/overview/)
    * [Kubernetes 架构](https://kubernetes.io/zh-cn/docs/concepts/architecture/)
* 几门极客时间课程：《Kubernetes 从上手到实践》、《Kubernetes 实践入门指南》、《深入剖析Kubernetes》

## 2. 总体说明

### 2.1. 总体架构

Kubernetes这个名字源于希腊语，意为“舵手”或“飞行员”，该项目于2014年由`Google`开源。

Kubernetes是一个可移植、可扩展的开源平台，用于管理**容器化**工作负载和服务。它支持**声明式配置**与**自动化操作**，拥有庞大且快速发展的生态系统。K8S不仅仅是一个编排系统（执行已定义的工作流程），它能做什么，不是什么，可见：[概述](https://kubernetes.io/zh-cn/docs/concepts/overview/)。

组成K8S集群的架构和关键组件：  
![components-of-kubernetes](/images/components-of-kubernetes.svg)  

或这张图：  
![kubernetes-cluster-architecture](/images/kubernetes-cluster-architecture.svg)

K8S集群由 **控制平面** 和 **一个或多个工作节点** 组成。

**1、控制面组件（Control Plane Component）**：管理集群整体状态
* `kube-apiserver`，提供HTTP API服务，并负责处理接收到的请求，是K8S控制平面的**核心**。
* `etcd`，高可用（HA）键值数据库，存储集群API服务的数据
* `kube-scheduler`，负责调度监控`pods`的运行
* `kube-controller-manager`，负责运行控制器进程，通过API服务（kube-apiserver）将当前状态转变到期望的状态
    * 控制器有多种不同的类型，如Node控制器、Job控制器等等
* `cloud-controller-manager`，与特定云驱动集成，允许集群连接到云提供商的API之上

**2、节点组件（Node Component）**：运行在每个节点上，维护Pod并提供K8S运行时环境
* `kubelet`，确保Pod和容器运行正常
    * kubelet保证容器（containers）都运行在 Pod 中，它 **不会管理** 不是由K8S创建的容器
* `kube-proxy`，维护节点上的网络规则，实现服务（`Service`）的功能
    * Kubernetes 中的 Service 是 将运行在一个或一组 Pod 上的网络应用程序公开为网络服务的方法，是一种抽象。
    * 如果使用 **<mark>网络插件</mark>**为Service实现数据包转发，提供和`kube-proxy`等效的行为，那就不需在节点运行该proxy
* 容器运行时（`Container runtime`），负责运行容器的软件，比如`containerd`、`CRI-O`和 支持`CRI（Container Runtime Interface）`的其他实现。

**3、插件（`Addons`）**：扩展了K8S的功能，比如：
* DNS：集群范围内的DNS解析
* Dashboard：通过Web页面管理集群
* 容器资源监控：存储一些时序指标到数据库中，和`OpenMetrics`一起使用（`OpenMetrics`构建于`Prometheus`暴露格式之上，Exposition formats）
* 集群层面日志：将容器日志保存到中央日志存储

### 2.2. 一些重要概念

* **Kubernetes对象（Objects）**：是Kubernetes系统中的**持久化实体**，K8S使用这些实体去表示**整个集群的状态**。
    * Kubernetes 对象是一种“`意向表达（Record of Intent）`”。通过创建对象，你本质上是在告知 Kubernetes 系统，你想要的集群工作负载状态看起来应是什么样子的，这就是 Kubernetes 集群所谓的`期望状态（Desired State）`。
    * 无论是创建、修改或者删除对象，都需要使用 **`Kubernetes API`**。
        * 可以通过 `kubectl`指令式命令（开发项目） 或者 对象配置文件（生产项目） 的方式来管理K8S对象。实际都会用到相关API。
        * K8S集群都会发布其所使用的API规范，有2种发布机制：`Discovery API` 和 `Kubernetes OpenAPI`。
        * 可进一步了解：[Kubernetes API](https://kubernetes.io/zh-cn/docs/concepts/overview/kubernetes-api/)
    * 详情以及配置文件中的各项说明，可见 [Kubernetes 对象](https://kubernetes.io/zh-cn/docs/concepts/overview/working-with-objects/)。

* **节点（Node）**：可以是一个虚拟机或者物理机器，取决于所在的集群配置。
    * 节点上运行Pod，容器则运行在Pod中。节点由**控制面（Control Plane）**负责管理。

下面的一些概念，可先搭建基本的学习环境后再对照理解，见下小节。

## 3. 搭建学习环境

> 参考：[安装Kubernetes工具](https://kubernetes.io/zh-cn/docs/tasks/tools/)。

安装下述工具：
* `kubectl`命令行工具，可用来部署应用、监测和管理集群资源以及查看日志。
    * 按上面文档操作，`curl`会直接下载一个`kubectl`二进制文件，赋执行权限即可使用
* 此外还有 `kind`、`minikube`、`kubeadm`，暂不安装，后续按需使用

```sh
[root@xdlinux ➜ ~ ]$ kubectl version --client
Client Version: v1.33.3
Kustomize Version: v5.6.0
```



## 4. 小结

## 5. 参考

* [Kubernetes Docs](https://kubernetes.io/docs/concepts/overview/)
* [Kubernetes中文文档](https://kubernetes.io/zh-cn/docs/concepts/overview/)
* 极客时间

