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

## 3. 搭建学习环境记录

参考：[安装Kubernetes工具](https://kubernetes.io/zh-cn/docs/tasks/tools/)。

可以通过`kubeadm`、`kind` 或 `minikube`快速搭建集群。看极客时间几个专栏用`kubeadm`比较多，此处也用该工具。

### 3.1. 安装工具

按上面链接对应的操作说明，几个工具都可以`curl`直接下载相应工具的二进制文件。
* `kubeadm`的步骤会添加K8S的yum源，而后统一安装`kubelet`、`kubeadm`、`kubectl`，此处选择按该方式快速安装。可见：[安装 kubeadm](https://kubernetes.io/zh-cn/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)。

安装工具：kubelet kubeadm kubectl

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

报错 `failed to create new CRI runtime service`，容器运行时需要另外安装，见下小节。

### 3.3. 安装containerd运行时

自己当前环境为`Rocky Linux release 9.5 (Blue Onyx)`，容器运行时为`podman`，而`kubeadm`的支持列表不包含该运行时，具体见：[容器运行时](https://kubernetes.io/zh-cn/docs/setup/production-environment/container-runtimes/)。

* 运行时不支持Docker Engine了：v1.24 之前的 Kubernetes 版本直接集成了 Docker Engine 的一个组件，名为 dockershim，自 1.24 版起，Dockershim 已从 Kubernetes 项目中移除。

手动安装`containerd`，具体见：[containerd/docs/getting-started.md](https://github.com/containerd/containerd/blob/main/docs/getting-started.md)。关于containerd的介绍见本篇中的后续小节。
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

安装运行时后，再`kubeadm init`安装，`-v 5`跟踪更详细的日志，可看到一直在处理pull容器镜像，如`registry.k8s.io/kube-apiserver:v1.33.3`，最后都pull超时失败了。

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

### 3.4. 重试：kubeadm创建集群（使用阿里云镜像后成功）

`--image-repository`指定阿里云镜像（[Kubernetes k8s拉取镜像失败解决方法](https://blog.csdn.net/weixin_43168190/article/details/107227626)）

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

[control-plane-check] kube-controller-manager is not healthy after 4m0.000452992s
[control-plane-check] kube-apiserver is not healthy after 4m0.000586746s
[control-plane-check] kube-scheduler is not healthy after 4m0.000835841s
...
```

虽然跑起来了，但最后停止了。重置`kubeadm`方式：`kubeadm reset -f`

修复上述警告和报错：

**1）错误**

crictl命令报错：

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

而后可以执行了，如 查看镜像：

```sh
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

**2）警告**

```sh
# 开放端口
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --reload

# 主机名解析警告
sudo echo "127.0.0.1   xdlinux" >> /etc/hosts

# kubelet自启动
systemctl enable --now kubelet
```

重置重来：

```sh
[root@xdlinux ➜ hello git:(main) ✗ ]$ kubeadm reset -f
...
W0719 23:42:22.336336  680838 removeetcdmember.go:106] [reset] No kubeadm config, using etcd pod spec to get data directory
[reset] Stopping the kubelet service
[reset] Unmounting mounted directories in "/var/lib/kubelet"
[reset] Deleting contents of directories: [/etc/kubernetes/manifests /var/lib/kubelet /etc/kubernetes/pki]
[reset] Deleting files: [/etc/kubernetes/admin.conf /etc/kubernetes/super-admin.conf /etc/kubernetes/kubelet.conf /etc/kubernetes/bootstrap-kubelet.conf /etc/kubernetes/controller-manager.conf /etc/kubernetes/scheduler.conf]
...
```

## 4. containerd运行时说明

containerd 是一个开源的容器运行时（Container Runtime），主要用于管理容器的生命周期，包括容器的创建、启动、停止、删除等核心操作。它最初是 Docker 引擎的一部分，2017 年被分离出来并捐赠给云原生计算基金会（CNCF），成为独立的开源项目，目前已成为容器生态中广泛使用的基础组件。

### 4.1. K8S为什么不再默认支持docker作为运行时

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

### 4.2. containerd操作命令

CLI工具：
* 1、`ctr`：是containerd本身的CLI
* 2、`crictl`：是Kubernetes社区定义的专门CLI工具

相关命令示例：
* 常用的跟docker功能对应的命令
    * 显示运行的容器列表 `crictl ps`
    * 查看状态 `crictl stats`
    * 登陆容器 `crictl exec`
    * 启停 `crictl start/stop`
    * 日志 `crictl logs`
* 查看本地镜像列表
    * `ctr images list`
    * `crictl images`
* 查看、删除导入的镜像：
    * `ctr images ls`
    * `crictl rmi`
* 下载镜像
    * `ctr images pull xxx`
* 打标签
    * `ctr images tag docker.io/docker/alpine:latest host/test/alping:v1`
* 导入、导出镜像
    * `ctr images import app.tar`
    * `ctr images exporter busybox-1.28.tar.gz docker.io/library/busybox:1.28`

## 5. 小结

## 6. 参考

* [Kubernetes Docs](https://kubernetes.io/docs/concepts/overview/)
* [Kubernetes中文文档](https://kubernetes.io/zh-cn/docs/concepts/overview/)
* [containerd简介](https://www.cnblogs.com/yangmeichong/p/16661444.html)
* [Kubernetes k8s拉取镜像失败解决方法](https://blog.csdn.net/weixin_43168190/article/details/107227626)
* 极客时间

