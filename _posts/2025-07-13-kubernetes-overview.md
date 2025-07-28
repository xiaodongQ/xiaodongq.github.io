---
title: Kubernetes学习实践（一） -- 总体说明和基本使用
description: Kubernetes学习实践，本篇进行总体说明和基本环境搭建
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
    * 相应的 [中文版本](https://kubernetes.io/zh-cn/docs/home/)
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
    * `Pod`是可以在Kubernetes中创建和管理的、最小的可部署的计算单元。`Pod`包含**一组容器（一个或多个）**，这些容器共享存储、网络、以及怎样运行这些容器的规约。
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

下面先搭建基本的学习环境后再对照理解其他一些概念。

## 3. kubeadm创建集群环境

参考：[安装Kubernetes工具](https://kubernetes.io/zh-cn/docs/tasks/tools/)。

可以通过`kubeadm`、`kind` 或 `minikube`快速搭建集群。看极客时间几个专栏用`kubeadm`比较多，此处也用该工具。

### 3.1. 安装kubelet、kubeadm、kubectl工具

按上面链接对应的操作说明，几个工具都可以`curl`直接下载相应工具的二进制文件。
* `kubeadm`的步骤会添加K8S的yum源，而后统一安装`kubelet`、`kubeadm`、`kubectl`，此处选择按该方式快速安装。可见：[安装 kubeadm](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)。

安装工具：kubelet kubeadm kubectl

```sh
# 网络可能比较慢，可以挂梯子试下
# crictl包含在cri-tools包中，此处一并安装了
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

如果安装还是慢，yum源也可改为国内的阿里云镜像源：

```sh
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF
```

### 3.2. kubeadm创建集群（报错）

使用`kubeadm`创建集群，具体见：[使用 kubeadm 创建集群](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)。

初始化集群：`kubeadm init` 报错了（完整内容可见：[kubeadm_init.log](https://github.com/xiaodongQ/prog-playground/tree/main/kubernetes/hello/kubeadm_init.log)）

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

报错 `failed to create new CRI runtime service`，容器运行时需要另外安装，见下小节。

### 3.3. containerd运行时说明

containerd 是一个开源的容器运行时（Container Runtime），主要用于管理容器的生命周期，包括容器的创建、启动、停止、删除等核心操作。它最初是 Docker 引擎的一部分，2017 年被分离出来并捐赠给云原生计算基金会（CNCF），成为独立的开源项目，目前已成为容器生态中广泛使用的基础组件。

#### 3.3.1. K8S为什么不再默认支持docker作为运行时

可了解：[containerd简介](https://www.cnblogs.com/yangmeichong/p/16661444.html)

> 在 2016 年 12 月 14 日，Docker 公司宣布将containerd 从 Docker 中分离，由开源社区独立发展和运营。Containerd 完全可以单独运行并管理容器，而 Containerd 的主要职责是镜像管理和容器执行。同时，Containerd 提供了 containerd-shim 接口封装层，
向下继续对接 runC 项目，使得容器引擎 Docker Daemon 可以独立升级。

Docker与containerd的关系：
* Docker中包含`containerd`，`containerd`专注于**运行时的容器管理**，而Docker除了容器管理之外，还可以完成**镜像构建**之类的功能。

K8S为什么要放弃使用Docker作为容器运行时，而使用containerd：
* 使用Docker作为K8S容器运行时的话，`kubelet`需要先要通过`dockershim`去调用Docker，再通过Docker去调用`containerd`；如果使用`containerd`作为K8S容器运行时的话，`kubelet`可以直接调用`containerd`。
    * Docker作为运行时：`kubelet --> docker shim （在 kubelet 进程中） --> dockerd --> containerd`
    * containerd作为运行时：`kubelet --> cri plugin（在 containerd 进程中） --> containerd`
* 使用`containerd`不仅性能提高了（调用链变短了），而且资源占用也会变小（Docker不是一个纯粹的容器运行时，具有大量其他功能）。

#### 3.3.2. containerd操作命令

CLI工具：
* 1、`crictl`：是Kubernetes社区定义的专门CLI工具
* 2、`ctr`：是containerd本身的CLI

此处仅使用`crictl`，相关命令示例：
* 常用的跟docker功能对应的命令
    * 显示运行的容器列表 `crictl ps`
    * 查看状态 `crictl stats`
    * 登陆容器 `crictl exec`
    * 启停 `crictl start/stop`
    * 日志 `crictl logs`
* 查看本地镜像列表
    * `crictl images`
* 查看、删除导入的镜像：
    * `crictl rmi`

### 3.4. 安装containerd运行时

自己当前环境为`Rocky Linux release 9.5 (Blue Onyx)`，容器运行时为`podman`，而`kubeadm`的支持列表中不包含该运行时，支持列表具体见：[容器运行时](https://kubernetes.io/zh-cn/docs/setup/production-environment/container-runtimes/)。

* 运行时不支持Docker Engine了：v1.24 之前的 Kubernetes 版本直接集成了 Docker Engine 的一个组件，名为 dockershim，自 1.24 版起，Dockershim 已从 Kubernetes 项目中移除。

手动安装`containerd`，可见：[containerd/docs/getting-started.md](https://github.com/containerd/containerd/blob/main/docs/getting-started.md)。
* 1）安装containerd
    * 添加unit文件，设置自启动
        * uint: [containerd.service](https://raw.githubusercontent.com/containerd/containerd/main/containerd.service)
        * 路径：`/usr/local/lib/systemd/system/containerd.service`
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
```

安装运行时后，再`kubeadm init`安装，`-v 5`跟踪更详细的日志，可看到一直在处理pull容器镜像，比如`registry.k8s.io/kube-apiserver:v1.33.3`，最后都pull超时失败了。

```sh
[root@xdlinux ➜ ~ ]$ kubeadm init -v 5
I0719 19:26:59.866585  667392 initconfiguration.go:123] detected and using CRI socket: unix:///var/run/containerd/containerd.sock
I0719 19:26:59.866705  667392 interface.go:432] Looking for default routes with IPv4 addresses
I0719 19:26:59.866710  667392 interface.go:437] Default route transits interface "enp4s0"
...
[preflight] You can also perform this action beforehand using 'kubeadm config images pull'
I0719 19:27:01.366724  667392 checks.go:832] using image pull policy: IfNotPresent
I0719 19:27:01.367032  667392 checks.go:844] failed to detect the sandbox image for local container runtime, no 'sandboxImage' field in CRI info config
...
I0719 19:27:01.367247  667392 checks.go:868] pulling: registry.k8s.io/kube-apiserver:v1.33.3
I0719 19:32:06.046226  667392 checks.go:868] pulling: registry.k8s.io/kube-scheduler:v1.33.3
I0719 19:34:37.832502  667392 checks.go:868] pulling: registry.k8s.io/kube-proxy:v1.33.3
I0719 19:37:10.742377  667392 checks.go:868] pulling: registry.k8s.io/coredns/coredns:v1.12.0
I0719 19:39:42.004031  667392 checks.go:868] pulling: registry.k8s.io/pause:3.10
I0719 19:42:13.522274  667392 checks.go:868] pulling: registry.k8s.io/etcd:3.5.21-0
...
[preflight] Some fatal errors occurred:
	[ERROR ImagePull]: failed to pull image registry.k8s.io/kube-apiserver:v1.33.3: failed to pull image registry.k8s.io/kube-apiserver:v1.33.3: rpc error: code = DeadlineExceeded desc = failed to pull and unpack image "registry.k8s.io/kube-apiserver:v1.33.3": failed to resolve image: failed to do request: Head "https://asia-east1-docker.pkg.dev/v2/k8s-artifacts-prod/images/kube-apiserver/manifests/v1.33.3": dial tcp 64.233.189.82:443: i/o timeout
```

### 3.5. 重试：kubeadm创建集群（使用阿里云镜像后init成功）

#### 3.5.1. 指定国内K8S镜像源

`--image-repository`指定阿里云镜像（参考自 [Kubernetes k8s拉取镜像失败解决方法](https://blog.csdn.net/weixin_43168190/article/details/107227626)）

```sh
[root@xdlinux ➜ ~ ]$ kubeadm init -v 5 --image-repository=registry.aliyuncs.com/google_containers
I0719 23:08:54.583750  677329 initconfiguration.go:123] detected and using CRI socket: unix:///var/run/containerd/containerd.sock
I0719 23:08:54.583881  677329 interface.go:432] Looking for default routes with IPv4 addresses
I0719 23:08:54.583887  677329 interface.go:437] Default route transits interface "enp4s0"
...
# pull K8S相关镜像
I0719 23:08:56.147496  677329 checks.go:868] pulling: registry.aliyuncs.com/google_containers/kube-apiserver:v1.33.3
I0719 23:08:59.965427  677329 checks.go:868] pulling: registry.aliyuncs.com/google_containers/kube-controller-manager:v1.33.3
I0719 23:09:03.257804  677329 checks.go:868] pulling: registry.aliyuncs.com/google_containers/kube-scheduler:v1.33.3
I0719 23:09:06.120594  677329 checks.go:868] pulling: registry.aliyuncs.com/google_containers/kube-proxy:v1.33.3
I0719 23:09:09.923887  677329 checks.go:868] pulling: registry.aliyuncs.com/google_containers/coredns:v1.12.0
I0719 23:09:12.736095  677329 checks.go:868] pulling: registry.aliyuncs.com/google_containers/pause:3.10
I0719 23:09:13.678343  677329 checks.go:868] pulling: registry.aliyuncs.com/google_containers/etcd:3.5.21-0
[certs] Using certificateDir folder "/etc/kubernetes/pki"
I0719 23:09:20.299402  677329 certs.go:112] creating a new certificate authority for ca
[certs] Generating "ca" certificate and key
...
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods from directory "/etc/kubernetes/manifests"
[kubelet-check] Waiting for a healthy kubelet at http://127.0.0.1:10248/healthz. This can take up to 4m0s
[kubelet-check] The kubelet is healthy after 501.465606ms
[control-plane-check] Waiting for healthy control plane components. This can take up to 4m0s
[control-plane-check] Checking kube-apiserver at https://192.168.1.150:6443/livez
[control-plane-check] Checking kube-controller-manager at https://127.0.0.1:10257/healthz
[control-plane-check] Checking kube-scheduler at https://127.0.0.1:10259/livez

# 健康状态报错
[control-plane-check] kube-controller-manager is not healthy after 4m0.000452992s
[control-plane-check] kube-apiserver is not healthy after 4m0.000586746s
[control-plane-check] kube-scheduler is not healthy after 4m0.000835841s

# 排查建议
A control plane component may have crashed or exited when started by the container runtime.
To troubleshoot, list all containers using your preferred container runtimes CLI.
Here is one example how you may list all running Kubernetes containers by using crictl:
    - 'crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock ps -a | grep kube | grep -v pause'
    Once you have found the failing container, you can inspect its logs with:
    - 'crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock logs CONTAINERID'
...
```

虽然跑起来了，但最后 **<mark>状态检查还是没通过</mark>**，所以不算创建成功。

#### 3.5.2. 问题定位和修改

1、**核心原因**：

`/var/log/messages`里面，查看各类报错信息，可看到虽然指定了阿里云镜像，但还是出现了pull失败的记录：`failed to pull and unpack image \\\"registry.k8s.io/pause:3.10\\\"`

```sh
 E0720 18:52:30.994969    9662 pod_workers.go:1301] "Error syncing pod, skipping" err="failed to \"CreatePodSandbox\" for \"kube-apiserver-xdlinux_kube-system(32a78a7f4b016e3715c0097719578050)\" with CreatePodSandboxError: \"Failed to create sandbox for pod \\\"kube-apiserver-xdlinux_kube-system(32a78a7f4b016e3715c0097719578050)\\\": rpc error: code = DeadlineExceeded desc = failed to start sandbox \\\"4b81dfeaa424dd7e8511a6d98ed2eadbaff65c9f13117b8b59bb07c139c53705\\\": failed to get sandbox image \\\"registry.k8s.io/pause:3.10\\\": failed to pull image \\\"registry.k8s.io/pause:3.10\\\": failed to pull and unpack image \\\"registry.k8s.io/pause:3.10\\\": failed to resolve image: failed to do request: Head \\\"https://asia-east1-docker.pkg.dev/v2/k8s-artifacts-prod/images/pause/manifests/3.10\\\": dial tcp 64.233.188.82:443: i/o timeout\"" pod="kube-system/kube-apiserver-xdlinux" podUID="32a78a7f4b016e3715c0097719578050" 
```

原因：Kubernetes组件仍尝试从默认的 `registry.k8s.io` 拉取`sandbox`对应的`pause`镜像。

解决方式：修改`containerd`的配置，调整`pause`的镜像地址为国内镜像。

```sh
sudo mkdir -p /etc/containerd
# 生成默认的containerd配置文件
containerd config default | sudo tee /etc/containerd/config.toml
# 修改配置文件的内容：将 sandbox = 'registry.k8s.io/pause:3.10' 修改为国内镜像地址：
sandbox = 'registry.aliyuncs.com/google_containers/pause:3.10'

# 而后重启containerd
sudo systemctl restart containerd
```

`kubeadm reset -f`重置之前的创建记录；  
而后再次创建集群`kubeadm init  --image-repository=registry.aliyuncs.com/google_containers`，**<mark>创建成功</mark>**。

```sh
[root@xdlinux ➜ ~ ]$ kubeadm init --image-repository=registry.aliyuncs.com/google_containers
...
[mark-control-plane] Marking the node xdlinux as control-plane by adding the labels: [node-role.kubernetes.io/control-plane node.kubernetes.io/exclude-from-external-load-balancers]
[mark-control-plane] Marking the node xdlinux as control-plane by adding the taints [node-role.kubernetes.io/control-plane:NoSchedule]
[bootstrap-token] Using token: 7rchgj.xjjxkx17xcihxmpt
[bootstrap-token] Configuring bootstrap tokens, cluster-info ConfigMap, RBAC Roles
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to get nodes
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to post CSRs in order for nodes to get long term certificate credentials
[bootstrap-token] Configured RBAC rules to allow the csrapprover controller automatically approve CSRs from a Node Bootstrap Token
[bootstrap-token] Configured RBAC rules to allow certificate rotation for all node client certificates in the cluster
[bootstrap-token] Creating the "cluster-info" ConfigMap in the "kube-public" namespace
[kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/
```

可查看到当前容器：

```sh
[root@xdlinux ➜ ~ ]$ crictl ps
CONTAINER      IMAGE          CREATED      STATE     NAME                      ATTEMPT  POD ID         POD                               NAMESPACE
456a0bf265a53  af855adae7960  2 hours ago  Running   kube-proxy                0        1b92f4255e32a  kube-proxy-4lgws                  kube-system
ab6a6e94fce12  41376797d5122  2 hours ago  Running   kube-scheduler            0        969028fcaf67b  kube-scheduler-xdlinux            kube-system
0aa7b90dfefe3  a92b4b92a9916  2 hours ago  Running   kube-apiserver            0        1347840cb6b03  kube-apiserver-xdlinux            kube-system
a1b3571e04878  499038711c081  2 hours ago  Running   etcd                      0        bfe9069b1f118  etcd-xdlinux                      kube-system
6ee08a166f4c0  bf97fadcef430  2 hours ago  Running   kube-controller-manager   0        e803930d15f8e  kube-controller-manager-xdlinux   kube-system
```

另外还有些其他警告和报错问题，下述也进行记录说明。

2、修复上述警告和`crictl`命令执行不了的问题：

`crictl`命令执行报错的问题，需要创建配置文件并指定套接字路径。`crictl`则是Kubernetes社区定义的专门CLI工具。

```sh
[root@xdlinux ➜ hello git:(main) ✗ ]$ crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock ps -a | grep kube | grep -v pause
WARN[0000] Config "/etc/crictl.yaml" does not exist, trying next: "/usr/bin/crictl.yaml"
```

创建配置文件（指定 containerd 套接字路径）

```sh
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF
```

而后可以用`crictl`命令了，如 查看镜像：

```sh
# 或直接 crictl images
[root@xdlinux ➜ hello git:(main) ✗ ]$ crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock images
IMAGE                                                             TAG                 IMAGE ID            SIZE
registry.aliyuncs.com/google_containers/coredns                   v1.12.0             1cf5f116067c6       20.9MB
registry.aliyuncs.com/google_containers/etcd                      3.5.21-0            499038711c081       58.9MB
registry.aliyuncs.com/google_containers/kube-apiserver            v1.33.3             a92b4b92a9916       30.1MB
registry.aliyuncs.com/google_containers/kube-controller-manager   v1.33.3             bf97fadcef430       27.6MB
registry.aliyuncs.com/google_containers/kube-proxy                v1.33.3             af855adae7960       31.9MB
registry.aliyuncs.com/google_containers/kube-scheduler            v1.33.3             41376797d5122       21.8MB
registry.aliyuncs.com/google_containers/pause                     3.10                873ed75102791       320kB
```

3、端口白名单，主机名，kubelet自启动修改、关swap

```sh
# 开放端口
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --reload

# 主机名解析警告
sudo echo "127.0.0.1   xdlinux" >> /etc/hosts

# kubelet自启动
systemctl enable --now kubelet

# 关swap，并注释掉/etc/fstab的swap挂载
swapoff -a
```

4、开启转发参数

`/etc/sysctl.conf`里增加 `net.ipv4.ip_forward = 1`，而后`sysctl -p`

### 3.6. 相关配置文件

5、另外记录下相关排查命令和配置文件：

* 查看日志：
    * `journalctl -u kubelet -f`
    * `journalctl -xeu kubelet --no-pager | grep -i -E "error|fail"`
* 重置`kubeadm`方式：`kubeadm reset -f`，会把之前init的操作都清理掉
* 各pod的配置文件路径
    * 在 `/etc/kubernetes/manifests/`目录下
    * 如 `/etc/kubernetes/manifests/kube-apiserver.yaml`
* kubelet配置文件：
    * `/etc/kubernetes/kubelet.conf`

## 4. 集群创建后的操作

上面`kubeadm init`已经成功创建集群了（提示：`Your Kubernetes control-plane has initialized successfully!`），还需要进行一些操作。

其最后的日志提示需要2个操作：

* 1、若为root用户，`export KUBECONFIG=/etc/kubernetes/admin.conf`，直接终端操作即可，并可加到`.bashrc`/`.zshrc`中启动时进行设置
* 2、安装pod网络插件，可见：
    * [安装Pod网络插件](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#pod-network)
    * 多种插件：[Addon--网络策略](https://kubernetes.io/zh-cn/docs/concepts/cluster-administration/addons/#networking-and-network-policy)

LLM给的插件简要对比：

| 插件          | 特点                                            | 适用场景                |
| ------------- | ----------------------------------------------- | ----------------------- |
| **Calico**    | 支持网络策略（NetworkPolicy）、高性能、BGP 路由 | 生产环境、需要安全策略  |
| **Flannel**   | 简单易用、基于 VXLAN 或 host-gw                 | 测试/开发环境、快速部署 |
| **Cilium**    | 基于 eBPF、高性能、支持网络策略和观测           | 高性能集群、云原生环境  |
| **Weave Net** | 自动加密、去中心化设计                          | 简单部署、小规模集群    |

> **推荐**：
> - **生产环境** → **Calico**（功能全）或 **Cilium**（高性能）
> - **测试环境** → **Flannel**（最简单）

### 4.1. 安装Pod网络插件：Calico（失败）

必须安装一个基于`CNI（Container Network Interface）`的Pod网络插件，用于Pod间的通信。
* 此处选择 [Calico](https://www.tigera.io/project-calico/)
* 另外后续可以研究一下 [Cilium](https://github.com/cilium/cilium)，支持`eBPF`

安装之前，可以看到当前环境里`/var/log/messages`一直在提示`cni plugin not initialized`：
```sh
Jul 20 21:54:38 xdlinux kubelet[13264]: E0720 21:54:38.519066   13264 kubelet.go:3117] "Container runtime network not ready" networkReady="NetworkReady=false reason:NetworkPluginNotReady message:Network plugin returns error: cni plugin not initialized"
```

查看节点状态，可看到还是`NotReady`，因为需要网络插件。
```sh
[root@xdlinux ➜ ~ ]$ kubectl get nodes 
NAME      STATUS     ROLES           AGE    VERSION
xdlinux   NotReady   control-plane   150m   v1.33.3
```

安装`Calico`，v3.30.2：
* 1、下载yaml到本地修改，因为其中的镜像是在`docker.io`，pull会失败
    * `wget https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/calico.yaml -O calico_modified.yaml`
* 2、`docker.io/calico`修改为`registry.aliyuncs.com/google_containers/calico`（阿里云镜像）
    * `sed -i 's|docker.io/calico|registry.aliyuncs.com/google_containers/calico|g' calico_modified.yaml`
* 3、应用修改后的yaml
    * `kubectl apply -f calico_modified.yaml`
* 其他功能操作命令
    * 删除：`kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/calico.yaml`

```sh
[root@xdlinux ➜ ~ ]$ kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/calico.yaml
poddisruptionbudget.policy/calico-kube-controllers created
serviceaccount/calico-kube-controllers created
serviceaccount/calico-node created
serviceaccount/calico-cni-plugin created
configmap/calico-config created
customresourcedefinition.apiextensions.k8s.io/bgpconfigurations.crd.projectcalico.org created
...
clusterrolebinding.rbac.authorization.k8s.io/calico-node created
clusterrolebinding.rbac.authorization.k8s.io/calico-cni-plugin created
daemonset.apps/calico-node created
deployment.apps/calico-kube-controllers created
```

```sh
# 查看所有pod
[root@xdlinux ➜ ~ ]$  kubectl get pods --all-namespaces
NAMESPACE     NAME                              READY   STATUS    RESTARTS   AGE
kube-system   coredns-757cc6c8f8-nxw7g          0/1     Pending   0          35h
kube-system   coredns-757cc6c8f8-v2mgf          0/1     Pending   0          35h
kube-system   etcd-xdlinux                      1/1     Running   2          35h
kube-system   kube-apiserver-xdlinux            1/1     Running   2          35h
kube-system   kube-controller-manager-xdlinux   1/1     Running   0          35h
kube-system   kube-proxy-v682x                  1/1     Running   0          35h
kube-system   kube-scheduler-xdlinux            1/1     Running   2          35h

# 过滤检查所有 Calico Pod 是否 Running
kubectl get pods -n kube-system -l k8s-app=calico-node
kubectl get pods -n kube-system -l k8s-app=calico-kube-controllers
```

开始默认镜像地址为`docker.io`，pull失败：
```sh
Jul 20 22:31:54 xdlinux containerd[12607]: time="2025-07-20T22:31:54.295953417+08:00" level=error msg="PullImage \"docker.io/calico/cni:v3.27.0\" failed" error="rpc error: code = DeadlineExceeded desc = failed to pull and unpack image \"docker.io/calico/cni:v3.27.0\": failed to resolve image: failed to do request: Head \"https://registry-1.docker.io/v2/calico/cni/manifests/v3.27.0\": dial tcp [2a03:2880:f10e:83:face:b00c:0:25de]:443: i/o timeout"
```

切换阿里云地址，还是pull失败（鉴权问题？）：`registry.aliyuncs.com/google_containers/calico/cni:v3.30.2`
```sh
Jul 20 23:07:17 xdlinux containerd[26160]: time="2025-07-20T23:07:17.337678802+08:00" level=info msg="fetch failed" error="pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed" host=registry.aliyuncs.com
Jul 20 23:07:17 xdlinux containerd[26160]: time="2025-07-20T23:07:17.338977261+08:00" level=error msg="PullImage \"registry.aliyuncs.com/google_containers/calico/cni:v3.30.2\" failed" error="rpc error: code = Unknown desc = failed to pull and unpack image \"registry.aliyuncs.com/google_containers/calico/cni:v3.30.2\": failed to resolve image: pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed"
```

折腾了好几个来回，也找了一些别的国内镜像，还是不行，先使用简单点的`flannel`插件吧。

另外，Calico对应的cidr需要使用`192.168.0.0/16`：`kubeadm init --image-repository=registry.aliyuncs.com/google_containers --pod-network-cidr=192.168.0.0/16`

### 4.2. 网络插件切换成：flannel（成功）

重新初始化：

1、重置 `kubeadm reset -f`

2、重新初始化，指定CIDR：`kubeadm init --image-repository=registry.aliyuncs.com/google_containers --pod-network-cidr=10.244.0.0/16`

3、安装flannel：`kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml`

镜像pull直接成功了：`ghcr.io/flannel-io/flannel-cni-plugin:v1.7.1-flannel1`

```sh
Jul 22 19:48:52 xdlinux containerd[26160]: time="2025-07-22T19:48:52.976885795+08:00" level=info msg="Pulled image \"ghcr.io/flannel-io/flannel-cni-plugin:v1.7.1-flannel1\" with image id \"sha256:cca2af40a4a9ea852721be08a315aa3cbb9e119fbbbffbc388a5b178a89f6a59\", repo tag \"ghcr.io/flannel-io/flannel-cni-plugin:v1.7.1-flannel1\", repo digest \"ghcr.io/flannel-io/flannel-cni-plugin@sha256:cb3176a2c9eae5fa0acd7f45397e706eacb4577dac33cad89f93b775ff5611df\", size \"4878976\" in 5.094745543s"
```

但是看系统日志还是一直报错：提示找不到`/run/flannel/subnet.env`

```sh
Jul 22 21:13:05 xdlinux containerd[170753]: time="2025-07-22T21:13:05.202071815+08:00" level=error msg="RunPodSandbox for &PodSandboxMetadata{Name:coredns-757cc6c8f8-v2mgf,Uid:3728bb94-a452-4245-864a-a369c4dfe138,Namespace:kube-system,Attempt:0,} failed, error" error="rpc error: code = Unknown desc = failed to setup network for sandbox \"c0f99a92d509c419f0b95d90d545e3cc24148bc59695b761ab5c9e4ca7f176df\": plugin type=\"flannel\" failed (add): loadFlannelSubnetEnv failed: open /run/flannel/subnet.env: no such file or directory"
```

基于LLM的建议方式，先手动创建配置：手动获取集群网络CIDR，并如下新建`/run/flannel/subnet.env`文件

```sh
[root@xdlinux ➜ hello git:(main) ✗ ]$ kubectl cluster-info dump | grep -m1 cluster-cidr
                            "--cluster-cidr=10.244.0.0/16",
[root@xdlinux ➜ hello git:(main) ✗ ]$ POD_NETWORK_CIDR="10.244.0.0/16"
[root@xdlinux ➜ hello git:(main) ✗ ]$ 
[root@xdlinux ➜ hello git:(main) ✗ ]$ cat > /run/flannel/subnet.env <<EOF   
FLANNEL_NETWORK=${POD_NETWORK_CIDR}
FLANNEL_SUBNET=${POD_NETWORK_CIDR%.*}.100/24
FLANNEL_MTU=1450
FLANNEL_IPMASQ=true
EOF
```

可看到，`CoreDNS` Pod的状态正常了：一旦CoreDNS Pod启用并运行，就可以继续加入节点。

```sh
[root@xdlinux ➜ hello git:(main) ✗ ]$ kubectl get pods --all-namespaces
NAMESPACE     NAME                              READY   STATUS    RESTARTS   AGE
kube-system   coredns-757cc6c8f8-nxw7g          1/1     Running   0          37h
kube-system   coredns-757cc6c8f8-v2mgf          1/1     Running   0          37h
kube-system   etcd-xdlinux                      1/1     Running   2          37h
kube-system   kube-apiserver-xdlinux            1/1     Running   2          37h
kube-system   kube-controller-manager-xdlinux   1/1     Running   0          37h
kube-system   kube-proxy-v682x                  1/1     Running   0          37h
kube-system   kube-scheduler-xdlinux            1/1     Running   2          37h
```

查看控制面节点，状态也从`NotReady` 变为 `Ready`了：

```sh
[root@xdlinux ➜ hello git:(main) ✗ ]$ kubectl get nodes
NAME      STATUS   ROLES           AGE   VERSION
xdlinux   Ready    control-plane   37h   v1.33.3
```

### 4.3. 添加工作节点（单机不需要）

工作节点是工作负载运行的地方，使用`kubeadm join`方式添加，可见 [添加 Linux 工作节点](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/kubeadm/adding-linux-nodes/)。

当前是单机环境，且上面`kubectl get nodes`结果中，本机为控制面节点（Master节点）且为`Ready`正常状态，**不需要**再`join`了。

若还有**其他**的工作节点，可在新节点上执行`kubeadm join`，操作如下：

`kubeadm init`时，最后会打印一条`kubeadm join`的命令示例，不过当时日志没保存下来。
* `sudo kubeadm join --token <token> <control-plane-host>:<control-plane-port> --discovery-token-ca-cert-hash sha256:<hash>`
* 比如：`kubeadm join 172.16.59.30:6443 --token yup5oo.s5ui8hfrrcm5jf2j --discovery-token-ca-cert-hash sha256:3fe816c50e13da9491b277711e6e77dc0d6d10c03b23f2d7487d5b3bea9b9525`

通过 `kubeadm token create --print-join-command`，可以**重新创建新令牌并生成完整命令**：

```sh
[root@xdlinux ➜ lib ]$ kubeadm token create --print-join-command
kubeadm join 192.168.1.150:6443 --token zzm9zc.ewdtn9oq3pztckaw --discovery-token-ca-cert-hash sha256:f929ef5b39a4b7901ffdeb3e9e095a1671521c6e773ff26a171072f57fd4407e
```

## 5. 小结

介绍了K8S基本架构和关键概念，并基于`kubeadm`搭建本地环境，由于容器运行时和镜像地址问题，踩了不少坑。

后续基于刚搭建的环境继续熟悉相关概念和操作。

## 6. 参考

* [Kubernetes Docs](https://kubernetes.io/docs/concepts/overview/)
    * [Kubernetes中文文档](https://kubernetes.io/zh-cn/docs/concepts/overview/)
* [使用 kubeadm 创建集群](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
* [添加 Linux 工作节点](https://kubernetes.io/zh-cn/docs/tasks/administer-cluster/kubeadm/adding-linux-nodes/)
* [containerd简介](https://www.cnblogs.com/yangmeichong/p/16661444.html)
* [Kubernetes k8s拉取镜像失败解决方法](https://blog.csdn.net/weixin_43168190/article/details/107227626)
* 极客时间：Kubernetes从上手到实践
* LLM
