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

Kubernetes这个名字源于希腊语，意为“舵手”或“飞行员”，该项目于2014年由`Google`开源。

Kubernetes是一个可移植、可扩展的开源平台，用于管理**容器化**工作负载和服务。它支持**声明式配置**与**自动化操作**，拥有庞大且快速发展的生态系统。K8S不仅仅是一个编排系统（执行已定义的工作流程），它能做什么，不是什么，可见：[概述](https://kubernetes.io/zh-cn/docs/concepts/overview/)。

组成K8S集群的架构和关键组件：  
![components-of-kubernetes](/images/components-of-kubernetes.svg)  

或这张图：  
![kubernetes-cluster-architecture](/images/kubernetes-cluster-architecture.svg)


## 3. 小结

## 4. 参考

* [Kubernetes Docs](https://kubernetes.io/docs/concepts/overview/)
* 极客时间

