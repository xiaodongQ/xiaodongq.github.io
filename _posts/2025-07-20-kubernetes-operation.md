---
title: Kubernetes学习实践（二） -- 熟悉K8S相关概念和实操印证
description: 继续熟悉K8S的相关概念，并实操印证增强理解和体感
categories: [云原生, Kubernetes]
tags: [云原生, Kubernetes]
---


## 1. 引言

上篇搭建了一个单机K8S环境，本篇基于环境进行操作印证，熟悉理解相关概念和操作命令。

## 2. 基本操作命令

下述相关命令结果详情，可见：[kubectl_cmd_operation.md](https://github.com/xiaodongQ/prog-playground/tree/main/kubernetes/hello/kubectl_cmd_operation.md)。

### 2.1. 查看节点/Pod的状态和细节信息

**命令：**`kubectl describe TYPE NAME_PREFIX`，其中名称支持**前缀模糊匹配**
* 查看节点详细信息，`kubectl describe node xdlinux`
    * 由于支持名称前缀匹配，也可以`kubectl describe node xd`查看到`xdlinux`节点的信息
    * `kubectl describe node`、`kubectl describe nodes`也查询了到节点详情信息
* 除此之外，`TYPE`还可以是`pod`、`pods`，进一步信息可以`kubectl describe -h`查看

**关键信息：**
* 地址，下述的`Addresses`部分
    * `InternalIP:  192.168.1.150`
    * `Hostname:    xdlinux`
* 状况，`Conditions`，描述所有`Running`节点的状态
    * 如下述展示的几类状态：`MemoryPressure`内存压力、`DiskPressure`磁盘压力、`PIDPressure`进程压力、`Ready`：true表示节点健康，可接收Pod
    * 每种类型都有：当前的状态和状态发生变化的时间、出现该状态的原因信息
    * 当节点出现问题时，K8S会自动创建和相应状态的 **<mark>污点（Taint）</mark>** ，其和节点的 **<mark>亲和性（affinity）</mark>**相反，使节点排斥一类特定的Pod。
* 容量（`Capacity`）和可分配（`Allocatable`）
    * 这两个值描述节点上的可用资源：CPU、内存和可以调度到节点上的 Pod 的个数上限
* 信息（`Info`）
    * 节点的一般信息，如内核版本、Kubernetes 版本（kubelet 和 kube-proxy 版本）、 容器运行时详细信息，以及节点使用的操作系统。 
    * `kubelet` 从节点收集这些信息并将其发布到 Kubernetes API
* 进一步的信息，可见：[节点状态](https://kubernetes.io/zh-cn/docs/reference/node/node-status/)。

```sh
[root@xdlinux ➜ hello git:(main) ]$ kubectl describe node xdlinux
Name:               xdlinux
Roles:              control-plane
Labels:             beta.kubernetes.io/arch=amd64
...
CreationTimestamp:  Mon, 21 Jul 2025 07:47:52 +0800
Taints:             node-role.kubernetes.io/control-plane:NoSchedule
Unschedulable:      false
Lease:
  HolderIdentity:  xdlinux
  AcquireTime:     <unset>
  RenewTime:       Tue, 22 Jul 2025 22:57:36 +0800
Conditions:
  Type             Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----             ------  -----------------                 ------------------                ------                       -------
  MemoryPressure   False   Tue, 22 Jul 2025 22:57:34 +0800   Mon, 21 Jul 2025 07:47:51 +0800   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure     False   Tue, 22 Jul 2025 22:57:34 +0800   Mon, 21 Jul 2025 07:47:51 +0800   KubeletHasNoDiskPressure     kubelet has no disk pressure
  PIDPressure      False   Tue, 22 Jul 2025 22:57:34 +0800   Mon, 21 Jul 2025 07:47:51 +0800   KubeletHasSufficientPID      kubelet has sufficient PID available
  Ready            True    Tue, 22 Jul 2025 22:57:34 +0800   Tue, 22 Jul 2025 20:08:06 +0800   KubeletReady                 kubelet is posting ready status
Addresses:
  InternalIP:  192.168.1.150
  Hostname:    xdlinux
Capacity:
  cpu:                16
  ephemeral-storage:  56872Mi
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  memory:             31929508Ki
  pods:               110
Allocatable:
  cpu:                16
  ephemeral-storage:  53671152756
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  memory:             31827108Ki
  pods:               110
System Info:
  Machine ID:                 fedf1414bf654cf090067b7374c2a61a
  System UUID:                3adbd480-702c-11ec-8165-1ad318f15100
  Boot ID:                    28911b0d-93b1-4ba3-9f90-4d3c61270498
  Kernel Version:             5.14.0-503.40.1.el9_5.x86_64
  OS Image:                   Rocky Linux 9.5 (Blue Onyx)
  Operating System:           linux
  Architecture:               amd64
  Container Runtime Version:  containerd://2.1.3
  Kubelet Version:            v1.33.3
  Kube-Proxy Version:         
PodCIDR:                      10.244.0.0/24
PodCIDRs:                     10.244.0.0/24
Non-terminated Pods:          (7 in total)
  Namespace                   Name                               CPU Requests  CPU Limits  Memory Requests  Memory Limits  Age
  ---------                   ----                               ------------  ----------  ---------------  -------------  ---
  kube-system                 coredns-757cc6c8f8-nxw7g           100m (0%)     0 (0%)      70Mi (0%)        170Mi (0%)     39h
  kube-system                 coredns-757cc6c8f8-v2mgf           100m (0%)     0 (0%)      70Mi (0%)        170Mi (0%)     39h
  kube-system                 etcd-xdlinux                       100m (0%)     0 (0%)      100Mi (0%)       0 (0%)         39h
  kube-system                 kube-apiserver-xdlinux             250m (1%)     0 (0%)      0 (0%)           0 (0%)         39h
  kube-system                 kube-controller-manager-xdlinux    200m (1%)     0 (0%)      0 (0%)           0 (0%)         39h
  kube-system                 kube-proxy-v682x                   0 (0%)        0 (0%)      0 (0%)           0 (0%)         39h
  kube-system                 kube-scheduler-xdlinux             100m (0%)     0 (0%)      0 (0%)           0 (0%)         39h
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests    Limits
  --------           --------    ------
  cpu                850m (5%)   0 (0%)
  memory             240Mi (0%)  340Mi (1%)
  ephemeral-storage  0 (0%)      0 (0%)
  hugepages-1Gi      0 (0%)      0 (0%)
  hugepages-2Mi      0 (0%)      0 (0%)
Events:              <none>
```

## 3. 小结


## 4. 参考

* [Kubernetes Docs](https://kubernetes.io/docs/concepts/overview/)
    * [Kubernetes中文文档](https://kubernetes.io/zh-cn/docs/concepts/overview/)
* 极客时间
* LLM
