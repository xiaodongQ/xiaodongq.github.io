---
title: Kubernetes学习实践（二） -- 熟悉K8S相关概念和实操印证
description: 继续熟悉K8S的相关概念，并实操印证增强理解和体感
categories: [云原生, Kubernetes]
tags: [云原生, Kubernetes]
---


## 1. 引言

上篇搭建了一个单机K8S环境，本篇基于环境进行操作印证，熟悉理解相关概念和操作命令。

## 2. kubectl基本操作命令

K8S提供了CLI工具：`kubectl`用于完成大多数集群管理相关的功能，上篇提到其会通过`Kubernetes API`进行`C/S`方式调用。
* 可使用`kubectl -h`/`--help`方式查看帮助信息
* 另外可用`kubectl explain`方式解释一些K8S中的组件和包含的字段(Field)。支持查看的组件列表可通过`kubectl api-resources`获取，比如`nodes`/`services`

下述相关命令结果详情，可见：[kubectl_cmd_operation.md](https://github.com/xiaodongQ/prog-playground/tree/main/kubernetes/hello/kubectl_cmd_operation.md)。

### 2.1. `kubectl describe`查看节点/Pod信息

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

### 2.2. `kubectl get`查看节点/Pod信息

用法：`kubectl get node xxx`，也可`-o`指定不同的信息输出格式，比如`-o yaml`、`-o json`、`-o wide`，会有不同详细程度的信息展示。

```sh
[root@xdlinux ➜ ~ ]$ kubectl get node xdlinux
NAME      STATUS   ROLES           AGE     VERSION
xdlinux   Ready    control-plane   2d14h   v1.33.3
# 也支持`get no`、`get node xd`等模糊匹配方式
[root@xdlinux ➜ ~ ]$ kubectl get nodes
NAME      STATUS   ROLES           AGE     VERSION
xdlinux   Ready    control-plane   2d14h   v1.33.3
```

`kubectl get node xdlinux -o json`获取详情，可看到也包含了`kubectl describe`中的信息。

```sh
[root@xdlinux ➜ ~ ]$ kubectl get node xdlinux -o json
{
    "apiVersion": "v1",
    "kind": "Node",
    "metadata": {
        ...
        "name": "xdlinux",
        "resourceVersion": "297356",
        "uid": "0ba29438-6540-4fce-892e-a8564389d942"
    },
    "spec": {
        "podCIDR": "10.244.0.0/24",
        "podCIDRs": [
            "10.244.0.0/24"
        ],
        "taints": [
            {
                "effect": "NoSchedule",
                "key": "node-role.kubernetes.io/control-plane"
            }
        ]
    },
    "status": {
        "addresses": [
            {
                "address": "192.168.1.150",
                "type": "InternalIP"
            },
            {
                "address": "xdlinux",
                "type": "Hostname"
            }
        ],
        "allocatable": {
            "cpu": "16",
            "ephemeral-storage": "53671152756",
            "hugepages-1Gi": "0",
            "hugepages-2Mi": "0",
            "memory": "31827108Ki",
            "pods": "110"
        },
        "capacity": {
            "cpu": "16",
            "ephemeral-storage": "56872Mi",
            "hugepages-1Gi": "0",
            "hugepages-2Mi": "0",
            "memory": "31929508Ki",
            "pods": "110"
        },
        "conditions": [
            {
                "lastHeartbeatTime": "2025-07-23T14:03:39Z",
                "lastTransitionTime": "2025-07-20T23:47:51Z",
                "message": "kubelet has sufficient memory available",
                "reason": "KubeletHasSufficientMemory",
                "status": "False",
                "type": "MemoryPressure"
            },
            ...
        ],
        "daemonEndpoints": {
            "kubeletEndpoint": {
                "Port": 10250
            }
        },
        "features": {
            "supplementalGroupsPolicy": true
        },
        "images": [
            {
                "names": [
                    "registry.aliyuncs.com/google_containers/etcd@sha256:1532bbb923776a79310fa81c1a4955aeb7f4e220d5f64a9c5bf9cdf6ba364794",
                    "registry.aliyuncs.com/google_containers/etcd:3.5.21-0"
                ],
                "sizeBytes": 58937859
            },
            ...
        ],
        "nodeInfo": {
            "architecture": "amd64",
            "bootID": "28911b0d-93b1-4ba3-9f90-4d3c61270498",
            "containerRuntimeVersion": "containerd://2.1.3",
            "kernelVersion": "5.14.0-503.40.1.el9_5.x86_64",
            "kubeProxyVersion": "",
            "kubeletVersion": "v1.33.3",
            "machineID": "fedf1414bf654cf090067b7374c2a61a",
            "operatingSystem": "linux",
            "osImage": "Rocky Linux 9.5 (Blue Onyx)",
            "systemUUID": "3adbd480-702c-11ec-8165-1ad318f15100"
        },
        ...
    }
}
```

### 2.3. `kubectl run`运行一个Pod

Pod是K8S中最小的调度单元，所以无法直接在K8S中运行一个`container`，但是可以运行一个`Pod`，而这个`Pod`中只包含一个`container`。

下面以`kubectl run`来启动一个包含`Redis`的Pod，参考：[集群管理：以 Redis 为例-部署及访问](https://learn.lianglianglee.com/%e4%b8%93%e6%a0%8f/Kubernetes%20%e4%bb%8e%e4%b8%8a%e6%89%8b%e5%88%b0%e5%ae%9e%e8%b7%b5/07%20%e9%9b%86%e7%be%a4%e7%ae%a1%e7%90%86%ef%bc%9a%e4%bb%a5%20Redis%20%e4%b8%ba%e4%be%8b-%e9%83%a8%e7%bd%b2%e5%8f%8a%e8%ae%bf%e9%97%ae.md)。

1、执行 `kubectl run redis --image='redis:alpine'`

```sh
[root@xdlinux ➜ ~ ]$ kubectl run redis --image='redis:alpine'
pod/redis created
```

2、`kubectl get pods`查看Pod状态

查看了多次，一直是`Pending`状态

```sh
[root@xdlinux ➜ ~ ]$ kubectl get pods
NAME    READY   STATUS    RESTARTS   AGE
redis   0/1     Pending   0          11s

# 也可get all查看所有类型的信息
[root@xdlinux ➜ ~ ]$ kubectl get all
NAME        READY   STATUS    RESTARTS   AGE
pod/redis   0/1     Pending   0          9m17s

NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   2d14h
```

3、定位：`kubectl describe pod redis`查看这个Pod的事件

关注`Events`信息，下述信息明确表示：集群中有一个节点，但它有一个污点（taint）`node-role.kubernetes.io/control-plane: `，而Pod没有容忍（toleration）这个污点，因此无法调度。

**原因：**在单节点集群（例如minikube或只有一个控制平面节点的集群）中，**控制平面节点默认带有污点**，以防止普通工作负载运行在上面。

```sh
[root@xdlinux ➜ ~ ]$ kubectl describe pod redis
Name:             redis
Namespace:        default
...
Status:           Pending
IP:               
...
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:
  Type     Reason            Age                From               Message
  ----     ------            ----               ----               -------
  Warning  FailedScheduling  55s (x3 over 11m)  default-scheduler  0/1 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
```

4、解决方式

两种方式：
* 1）允许Pod调度到控制平面节点，移除控制平面节点的污点，命令如下所示（适用于测试环境）
* 2）为Redis Pod添加容忍，指定`tolerations`，此处暂不展开。（适合生产环境）

移除"控制平台节点"的`taint`后，可看到就自动开始创建容器了：

```sh
# 移除控制平面节点的污点（taint）
[root@xdlinux ➜ ~ ]$ kubectl taint nodes --all node-role.kubernetes.io/control-plane-
node/xdlinux untainted

# 移除后就开始创建容器了
[root@xdlinux ➜ ~ ]$ kubectl get all
NAME        READY   STATUS              RESTARTS   AGE
pod/redis   0/1     ContainerCreating   0          18m

NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   2d15h
```

但是状态变成`ImagePullBackOff`了，系统日志可看到还是pull镜像失败了，`docker.io/library/redis:alpine`

```sh
[root@xdlinux ➜ ~ ]$ kubectl get pod redis
NAME    READY   STATUS             RESTARTS   AGE
redis   0/1     ImagePullBackOff   0          23m

# tail -f /var/log/messages
Jul 23 22:57:43 xdlinux kubelet[197244]: E0723 22:57:43.256904  197244 pod_workers.go:1301] "Error syncing pod, skipping" err="failed to \"StartContainer\" for \"redis\" with ImagePullBackOff: \"Back-off pulling image \\\"redis:alpine\\\": ErrImagePull: failed to pull and unpack image \\\"docker.io/library/redis:alpine\\\": failed to resolve image: failed to do request: Head \\\"https://registry-1.docker.io/v2/library/redis/manifests/alpine\\\": dial tcp 162.220.12.226:443: connect: connection refused\"" pod="default/redis" podUID="c21adea0-dbfc-4936-bce2-8db56b48d4fb"
```

5、修改`containerd`镜像源，修改`/etc/containerd/config.toml`配置并重启`containerd`服务

```sh
# 在/etc/containerd/config.toml中新增下述项（存在则修改）。不存在文件则创建，参考上篇
  [plugins."io.containerd.grpc.v1.cri".registry]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
      endpoint = ["https://docker.m.daocloud.io"]

# 重启并查看是否正常启动
[root@xdlinux ➜ ~ ]$ systemctl restart containerd.service
[root@xdlinux ➜ ~ ]$ systemctl status containerd.service
```

直接指定`docker.m.daocloud.io/library/redis:alpine`（相对于`--image='redis:alpine'`）是可以正常pull的：  
`kubectl run redis --image=docker.m.daocloud.io/library/redis:alpine`

```sh
# 删除pod
[root@xdlinux ➜ containerd ]$ kubectl delete pod redis
pod "redis" deleted
```


## 3. 小结


## 4. 参考

* [Kubernetes Docs](https://kubernetes.io/docs/concepts/overview/)
    * [Kubernetes中文文档](https://kubernetes.io/zh-cn/docs/concepts/overview/)
* 极客时间：Kubernetes从上手到实践
* LLM
