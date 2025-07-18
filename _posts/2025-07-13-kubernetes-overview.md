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

参考：[安装Kubernetes工具](https://kubernetes.io/zh-cn/docs/tasks/tools/)。

可以通过`kubeadm`、`kind` 或 `minikube`快速搭建集群。看极客时间几个专栏用`kubeadm`比较多，此处也用该工具。

### 3.1. 安装工具

按上面链接对应的操作说明，几个工具都可以`curl`直接下载相应工具的二进制文件。
* `kubeadm`的步骤会添加K8S的yum源，而后统一安装`kubelet`、`kubeadm`、`kubectl`，此处选择按该方式快速安装。可见：[安装 kubeadm](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)。

```sh
# 网络可能比较慢，可以挂梯子试下
[root@xdlinux ➜ ~ ]$ sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
Kubernetes                                                     2.4 kB/s |  12 kB     00:04    
Dependencies resolved.
===============================================================================================
 Package                       Architecture  Version                   Repository         Size
===============================================================================================
Installing:
 kubeadm                       x86_64        1.33.3-150500.1.1         kubernetes         12 M
 kubectl                       x86_64        1.33.3-150500.1.1         kubernetes         11 M
 kubelet                       x86_64        1.33.3-150500.1.1         kubernetes         15 M
Installing dependencies:
 conntrack-tools               x86_64        1.4.7-4.el9_5             appstream         222 k
 cri-tools                     x86_64        1.33.0-150500.1.1         kubernetes        7.5 M
 kubernetes-cni                x86_64        1.6.0-150500.1.1          kubernetes        8.0 M
 libnetfilter_cthelper         x86_64        1.0.0-22.el9              appstream          23 k
 libnetfilter_cttimeout        x86_64        1.0.0-19.el9              appstream          23 k
 libnetfilter_queue            x86_64        1.0.5-1.el9               appstream          28 k

Transaction Summary
===============================================================================================
Install  9 Packages

Total download size: 55 M
Installed size: 301 M
...
```

安装完成后查看版信息：均为v1.33.3

```sh
[root@xdlinux ➜ ~ ]$ kubectl version --client
Client Version: v1.33.3
Kustomize Version: v5.6.0

[root@xdlinux ➜ ~ ]$ kubelet --version
Kubernetes v1.33.3

[root@xdlinux ➜ ~ ]$ kubeadm version
kubeadm version: &version.Info{Major:"1", Minor:"33", EmulationMajor:"", EmulationMinor:"", MinCompatibilityMajor:"", MinCompatibilityMinor:"", GitVersion:"v1.33.3", GitCommit:"80779bd6ff08b451e1c165a338a7b69351e9b0b8", GitTreeState:"clean", BuildDate:"2025-07-15T18:05:14Z", GoVersion:"go1.24.4", Compiler:"gc", Platform:"linux/amd64"}
```

### 3.2. kubeadm创建集群（报错）

2、使用`kubeadm`创建集群，具体见：[使用 kubeadm 创建集群](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)。

初始化集群：`kubeadm init` 报错了

```sh
[root@xdlinux ➜ first git:(main) ]$ kubeadm init
[init] Using Kubernetes version: v1.33.3
[preflight] Running pre-flight checks
W0719 00:31:45.855362  618460 checks.go:1065] [preflight] WARNING: Couldn't create the interface used for talking to the container runtime: failed to create new CRI runtime service: validate service connection: validate CRI v1 runtime API for endpoint "unix:///var/run/containerd/containerd.sock": rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial unix /var/run/containerd/containerd.sock: connect: no such file or directory"
	[WARNING Firewalld]: firewalld is active, please ensure ports [6443 10250] are open or your cluster may not function correctly
	[WARNING Hostname]: hostname "xdlinux" could not be reached
	[WARNING Hostname]: hostname "xdlinux": lookup xdlinux on [fe80::1%enp4s0]:53: no such host
	[WARNING Service-Kubelet]: kubelet service is not enabled, please run 'systemctl enable kubelet.service'
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action beforehand using 'kubeadm config images pull'
error execution phase preflight: [preflight] Some fatal errors occurred:
failed to create new CRI runtime service: validate service connection: validate CRI v1 runtime API for endpoint "unix:///var/run/containerd/containerd.sock": rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial unix /var/run/containerd/containerd.sock: connect: no such file or directory"[preflight] If you know what you are doing, you can make a check non-fatal with `--ignore-preflight-errors=...`
To see the stack trace of this error execute with --v=5 or higher
```

### 3.3. 安装containerd运行时

自己当前环境为`Rocky Linux release 9.5 (Blue Onyx)`，容器运行时为`podman`，而`kubeadm`的支持列表不包含该运行时，具体见：[容器运行时](https://kubernetes.io/zh-cn/docs/setup/production-environment/container-runtimes/)。

* 运行时不支持Docker Engine了：v1.24 之前的 Kubernetes 版本直接集成了 Docker Engine 的一个组件，名为 dockershim，自 1.24 版起，Dockershim 已从 Kubernetes 项目中移除。

安装`containerd`，具体见：[containerd/docs/getting-started.md](https://github.com/containerd/containerd/blob/main/docs/getting-started.md)。
* 1）安装containerd
    * 添加unit文件，设置自启动
* 2）安装runc
    * 安装到/usr/local/sbin
* 3）安装CNI插件
    * 安装到/opt/cni/bin

```sh
[root@xdlinux ➜ workspace ]$ tar Cxzvf /usr/local containerd-2.1.3-linux-amd64.tar.gz 
bin/
bin/containerd
bin/containerd-shim-runc-v2
bin/ctr
bin/containerd-stress
[root@xdlinux ➜ workspace ]$ ll /usr/local/bin 
total 220M
-rwxr-xr-x 1 root root  210 May 23 22:30 compiledb
-rwxr-xr-x 1 root root  42M Jun 20 06:37 containerd
-rwxr-xr-x 1 root root 7.6M Jun 20 06:37 containerd-shim-runc-v2
-rwxr-xr-x 1 root root  21M Jun 20 06:37 containerd-stress
-rwxr-xr-x 1 root root  23M Jun 20 06:37 ctr
-rwxr-xr-x 1 root root 127M Jul 19 00:33 minikube
```

### 3.4. 重试：kubeadm创建集群

```sh
[root@xdlinux ➜ workspace ]$ kubeadm init
[init] Using Kubernetes version: v1.33.3
[preflight] Running pre-flight checks
	[WARNING Firewalld]: firewalld is active, please ensure ports [6443 10250] are open or your cluster may not function correctly
	[WARNING Hostname]: hostname "xdlinux" could not be reached
	[WARNING Hostname]: hostname "xdlinux": lookup xdlinux on [fe80::1%enp4s0]:53: no such host
	[WARNING Service-Kubelet]: kubelet service is not enabled, please run 'systemctl enable kubelet.service'
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action beforehand using 'kubeadm config images pull'
```


## 4. 小结

## 5. 参考

* [Kubernetes Docs](https://kubernetes.io/docs/concepts/overview/)
* [Kubernetes中文文档](https://kubernetes.io/zh-cn/docs/concepts/overview/)
* 极客时间

