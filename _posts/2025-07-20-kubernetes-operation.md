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
        ...
        "daemonEndpoints": {
            "kubeletEndpoint": {
                "Port": 10250
            }
        },
        ...
    }
}
```

### 2.3. `kubectl run`运行一个Pod

`kubectl run redis --image=docker.m.daocloud.io/library/redis:alpine` 可以启动一个Pod，此处指定了一个代理镜像，默认的镜像暂时连不上。

## 3. 使用K8S部署一个Redis服务

Pod是K8S中最小的调度单元，所以无法直接在K8S中运行一个`container`，但是可以运行一个`Pod`，而这个`Pod`中只包含一个`container`。

下面以`kubectl run`来启动一个包含`Redis`的Pod，参考：[集群管理：以 Redis 为例-部署及访问](https://learn.lianglianglee.com/%e4%b8%93%e6%a0%8f/Kubernetes%20%e4%bb%8e%e4%b8%8a%e6%89%8b%e5%88%b0%e5%ae%9e%e8%b7%b5/07%20%e9%9b%86%e7%be%a4%e7%ae%a1%e7%90%86%ef%bc%9a%e4%bb%a5%20Redis%20%e4%b8%ba%e4%be%8b-%e9%83%a8%e7%bd%b2%e5%8f%8a%e8%ae%bf%e9%97%ae.md)。

### 3.1. 正常运行Redis镜像

1、执行 `kubectl run redis --image='redis:alpine'`（使用的基础镜像为`Alpine Linux`，镜像体积最小）

```sh
[root@xdlinux ➜ ~ ]$ kubectl run redis --image='redis:alpine'
pod/redis created
```

此外，直接指定`docker.m.daocloud.io/library/redis:alpine`是可以正常pull的：  
`kubectl run redis --image=docker.m.daocloud.io/library/redis:alpine`。但此处来定位下为什么`--image='redis:alpine'`无法成功拉取镜像。

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

### 3.2. 调整：设置控制面允许运行普通工作负载

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

### 3.3. 调整：修改containerd镜像源

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

但是toml解析这些新增的项都失败了，`unknown key`：
```sh
Jul 24 23:45:14 xdlinux containerd[358071]: time="2025-07-24T23:45:14.978826944+08:00" level=info msg="loading plugin" id=io.containerd.grpc.v1.cri type=io.containerd.grpc.v1
Jul 24 23:45:14 xdlinux containerd[358071]: time="2025-07-24T23:45:14.978870876+08:00" level=warning msg="Ignoring unknown key in TOML for plugin" error="strict mode: fields in the document are missing in the target struct" key=registry plugin=io.containerd.grpc.v1.cri
Jul 24 23:45:14 xdlinux containerd[358071]: time="2025-07-24T23:45:14.978881352+08:00" level=warning msg="Ignoring unknown key in TOML for plugin" error="strict mode: fields in the document are missing in the target struct" key="registry mirrors" plugin=io.containerd.grpc.v1.cri
Jul 24 23:45:14 xdlinux containerd[358071]: time="2025-07-24T23:45:14.978889454+08:00" level=warning msg="Ignoring unknown key in TOML for plugin" error="strict mode: fields in the document are missing in the target struct" key="registry mirrors docker.io" plugin=io.containerd.grpc.v1.cri
```

原因是 `plugins."io.containerd.grpc.v1.cri".registry.mirrors` 在 containerd v2.2里已经弃用了，具体见：[deprecated-config-properties](https://github.com/containerd/containerd/blob/main/RELEASES.md#deprecated-config-properties)。

解决方式：使用 [config_path](https://github.com/containerd/containerd/blob/main/docs/hosts.md) 方式进行替换。

* `/etc/containerd/config.toml` 文件中，修改`config_path`：

```sh
[plugins."io.containerd.cri.v1.images".registry]
   config_path = "/etc/containerd/certs.d"
```

* 而后在 `/etc/containerd/certs.d`下面新建需要mirror的仓库，如：`docker.io`就新增同名目录

由于上面报 `https://registry-1.docker.io/v2/library/redis/manifests/alpine\\\": dial tcp 162.220.12.226:443: connect: connection refused`，所以再新增一个 `registry-1.docker.io`目录，拷贝一份`hosts.toml`

```sh
[root@xdlinux ➜ certs.d ]$ tree /etc/containerd/certs.d
/etc/containerd/certs.d
├── docker.io
│   └── hosts.toml
└── registry-1.docker.io
    └── hosts.toml

# 内容如下
[root@xdlinux ➜ docker.io ]$ cat /etc/containerd/certs.d/docker.io/hosts.toml 
server = "https://docker.m.daocloud.io"

[host."https://docker.m.daocloud.io"]
  capabilities = ["pull", "resolve"]
```

删除pod后重新创建：
```sh
# 删除pod
[root@xdlinux ➜ containerd ]$ kubectl delete pod redis
pod "redis" deleted

[root@xdlinux ➜ certs.d ]$ kubectl run redis --image='redis:alpine'
pod/redis created
```

可看到正常创建了：
```sh
[root@xdlinux ➜ ~ ]$ kubectl get all
NAME        READY   STATUS    RESTARTS   AGE
pod/redis   1/1     Running   0          34m

NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   6d14h
```

### 3.4. 镜像踩坑小结

调整containerd镜像源折腾了挺久，从网上和LLM得到的配置方式存在一些滞后，主要是有些配置项已经弃用了（`Deprecation`），最后还是通过官方文档 [deprecated-config-properties](https://github.com/containerd/containerd/blob/main/RELEASES.md#deprecated-config-properties) 确认了问题，上面同时提供了新的配置方式：[config_path](https://github.com/containerd/containerd/blob/main/docs/hosts.md)。进一步了解最好后续看看containerd的功能实现和文档。

### 3.5. 对外暴露(expose)Redis服务

上面`Redis`已部署但尚未创建对应的`Service`，要访问上述创建的`Redis`服务，还需要创建`Redis` Service。操作如下：

#### 3.5.1. 创建Redis Service

创建 `redis-service.yaml`来定义Redis Service，其内容如下，并`kubectl apply`（之前selector里`app: redis`不对，调整为`run: redis`，可`kubectl get pods redis --show-labels`查看pod的标签）

```sh
# Service文件
[root@xdlinux ➜ hello git:(main) ✗ ]$ cat redis-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: redis-service
spec:
  selector:
    run: redis  # 匹配Pod的标签（需根据实际标签调整）
  ports:
    - protocol: TCP
      port: 6379        # Service端口
      targetPort: 6379  # Pod端口（Redis默认端口）
  type: ClusterIP       # 集群内部访问，也可改为NodePort暴露到外部

# 应用配置
[root@xdlinux ➜ hello git:(main) ✗ ]$ kubectl apply -f redis-service.yaml
service/redis-service created
```

可看到服务起来了：
```sh
[root@xdlinux ➜ hello git:(main) ✗ ]$ kubectl get all
NAME        READY   STATUS    RESTARTS   AGE
pod/redis   1/1     Running   0          38m

NAME                    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/kubernetes      ClusterIP   10.96.0.1       <none>        443/TCP    6d14h
service/redis-service   ClusterIP   10.105.22.241   <none>        6379/TCP   11s
```

但此时还是不能连的：
```sh
[root@xdlinux ➜ hello git:(main) ✗ ]$ redis-cli -h 10.105.22.241
Could not connect to Redis at 10.105.22.241:6379: Connection refused
not connected> 
```

#### 3.5.2. 设置外部访问Redis的方式

支持下述几种方式对外提供访问方式：

* 1、通过 `kubectl port-forward` （推荐开发环境）
    * 命令：`kubectl port-forward service/redis-service 6379:6379`，这会将本地的 6379 端口转发到 Redis Service 的 6379 端口

```sh
[root@xdlinux ➜ redis-server git:(main) ✗ ]$ kubectl port-forward service/redis-service 6379:6379
Forwarding from 127.0.0.1:6379 -> 6379
Forwarding from [::1]:6379 -> 6379
```

* 2、通过`NodePort`暴露到外部（生产环境需谨慎）
    * 修改`Service`的`type`为`NodePort`，并重新应用配置

新增一个NodePort对应的`redis-nodeport.yaml`：

```sh
[root@xdlinux ➜ redis-server git:(main) ✗ ]$ cat redis-nodeport.yaml
apiVersion: v1
kind: Service
metadata:
  name: redis-service
spec:
  selector:
    run: redis  # 匹配Pod的标签（需根据实际标签调整）
  ports:
    - protocol: TCP
      port: 6379        # Service端口
      targetPort: 6379  # Pod端口（Redis默认端口）
      nodePort: 30000   # 可选指定NodePort（范围30000-32767）
  type: NodePort


# 查看标签，相应调整上面的`run: redis`（而不是`app: redis`）
[root@xdlinux ➜ redis-server git:(main) ✗ ]$ kubectl get pods redis --show-labels
NAME    READY   STATUS    RESTARTS   AGE   LABELS
redis   1/1     Running   0          85m   run=redis
```

应用：
```sh
[root@xdlinux ➜ redis-server git:(main) ✗ ]$ kubectl apply -f redis-nodeport.yaml 
service/redis-service configured
[root@xdlinux ➜ redis-server git:(main) ✗ ]$ kubectl get all
NAME        READY   STATUS    RESTARTS   AGE
pod/redis   1/1     Running   0          62m

NAME                    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
service/kubernetes      ClusterIP   10.96.0.1       <none>        443/TCP          6d14h
service/redis-service   NodePort    10.105.22.241   <none>        6379:30000/TCP   24m
```

service服务的描述信息：
```sh
# 正常情况下的描述信息如下，注意标签是run=redis
[root@xdlinux ➜ redis-server git:(main) ✗ ]$ kubectl describe service redis-service
Name:                     redis-service
Namespace:                default
Labels:                   <none>
Annotations:              <none>
Selector:                 run=redis
Type:                     NodePort
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.105.22.241
IPs:                      10.105.22.241
Port:                     <unset>  6379/TCP
TargetPort:               6379/TCP
NodePort:                 <unset>  30000/TCP
Endpoints:                10.244.0.13:6379
Session Affinity:         None
External Traffic Policy:  Cluster
Internal Traffic Policy:  Cluster
Events:                   <none>

# 这里也贴一下之前有问题（标签当时为`app: redis`，和pod不符）的描述信息作为对比
# 根本原因：Service 的 Selector 与 Pod 标签不匹配，导致 kube-proxy 无法将 Service 关联到 Pod。且Endpoints 为空
[root@xdlinux ➜ redis-server git:(main) ✗ ]$ kubectl describe service redis-service
Name:                     redis-service
Namespace:                default
Labels:                   <none>
Annotations:              <none>
Selector:                 app=redis
Type:                     NodePort
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.105.22.241
IPs:                      10.105.22.241
Port:                     <unset>  6379/TCP
TargetPort:               6379/TCP
NodePort:                 <unset>  30000/TCP
Endpoints:                
Session Affinity:         None
External Traffic Policy:  Cluster
Internal Traffic Policy:  Cluster
Events:                   <none>
```

可看到防火墙规则正常生成了。

```sh
# 检查iptables规则是否自动生成
[root@xdlinux ➜ redis-server git:(main) ✗ ]$ iptables -t nat -L KUBE-NODEPORTS -n -v | grep 30000
    0     0 KUBE-EXT-DHQ3MZCC7Y6T2RHF  tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* default/redis-service */ tcp dpt:30000
[root@xdlinux ➜ redis-server git:(main) ✗ ]$ kubectl get nodes -o wide
NAME      STATUS   ROLES           AGE     VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                      KERNEL-VERSION                 CONTAINER-RUNTIME
xdlinux   Ready    control-plane   6d15h   v1.33.3   192.168.1.150   <none>        Rocky Linux 9.5 (Blue Onyx)   5.14.0-503.40.1.el9_5.x86_64   containerd://2.1.3
```

`redis-cli -h 192.168.1.150 -p 30000`可以正常连接了。
* 注意对应的ip是node对应的ip，而不是上面显示的`10.105.22.241`。这里的`10.105.22.241`是Service对应的`CLUSTER-IP`，这是一个**仅在集群内部可访问的虚拟IP**
* **`Cluster IP`的设计说明：**
    * `Cluster IP`是 Kubernetes 为 Service 分配的**内部虚拟IP**，仅用于集群内部 Pod 之间或节点与 Service 之间的通信。**外部网络无法直接访问 Cluster IP**。
    * Cluster IP不对应任何物理网卡或网络设备，它由`kube-proxy`通过`iptables`或`IPVS`规则实现流量转发。外部网络**无法路由**到这个虚拟IP。

```sh
[root@xdlinux ➜ redis-server git:(main) ✗ ]$ redis-cli -h 192.168.1.150 -p 30000
192.168.1.150:30000> 
192.168.1.150:30000> set xdtest 1111
OK
192.168.1.150:30000> get xdtest
"1111"
```

`NodePort`模式下的流量链路：外部请求 → 节点 IP:30000 → kube-proxy 转发 → Cluster IP:6379 → Redis Pod。

也可以：`redis-cli -h 10.105.22.241`，虽然`ping 10.105.22.241`是不通的。

```sh
[root@xdlinux ➜ certs.d ]$ redis-cli -h 10.105.22.241
10.105.22.241:6379> get xdtest
"1111"
10.105.22.241:6379> 
# 查看redis:alpine版本信息
10.105.22.241:6379> info server
redis_version:8.0.3
...
```

## 4. 扩容Redis服务

上述使用独立`Pod`方式部署了`Redis`，无法实现自动扩容。要实现自动扩容，这里使用`StatefulSet`替换`Deployment`。

1、创建 `Redis StatefulSet` 配置

创建`redis-statefulset.yaml`文件

2、应用配置
```sh
# 删除现有Pod和Service
kubectl delete pod redis
kubectl delete service redis-service

# 创建新的Service和StatefulSet
kubectl apply -f redis-statefulset.yaml
```

查看状态：
```sh
[root@xdlinux ➜ redis-stateful-set git:(main) ✗ ]$ kubectl get all
NAME          READY   STATUS    RESTARTS   AGE
pod/redis-0   0/1     Pending   0          43s

NAME                     TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
service/kubernetes       ClusterIP   10.96.0.1    <none>        443/TCP    6d15h
service/redis-headless   ClusterIP   None         <none>        6379/TCP   43s

NAME                     READY   AGE
statefulset.apps/redis   0/1     43s
```

**定位：**可以`kubectl describe pod redis-0`查看原因。可看到是没有可用的`PV`。

```sh
Events:
  Type     Reason            Age                    From               Message
  ----     ------            ----                   ----               -------
  Warning  FailedScheduling  2m15s (x2 over 7m19s)  default-scheduler  0/1 nodes are available: pod has unbound immediate PersistentVolumeClaims. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
```

重新调整为临时存储，而不用PV。`kubectl delete`几个资源后重新apply，可看到正常创建了。
```sh
[root@xdlinux ➜ redis-stateful-set git:(main) ✗ ]$ kubectl get all
NAME          READY   STATUS    RESTARTS   AGE
pod/redis-0   1/1     Running   0          32s

NAME                     TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)    AGE
service/kubernetes       ClusterIP   10.96.0.1    <none>        443/TCP    6d16h
service/redis-headless   ClusterIP   None         <none>        6379/TCP   32s

NAME                     READY   AGE
statefulset.apps/redis   1/1     32s

```

3、创建 `NodePort Service` 暴露 Redis

创建：`redis-nodeport.yaml`

```sh
[root@xdlinux ➜ redis-stateful-set git:(main) ✗ ]$ kubectl get all
NAME          READY   STATUS    RESTARTS   AGE
pod/redis-0   1/1     Running   0          113s

NAME                     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
service/kubernetes       ClusterIP   10.96.0.1       <none>        443/TCP          6d16h
service/redis-headless   ClusterIP   None            <none>        6379/TCP         113s
service/redis-service    NodePort    10.107.73.216   <none>        6379:30000/TCP   6s

NAME                     READY   AGE
statefulset.apps/redis   1/1     113s
```

验证，通过映射端口和Cluster-Ip都可以访问：

```sh
[root@xdlinux ➜ redis-stateful-set git:(main) ✗ ]$ redis-cli -h 192.168.1.150 -p 30000 ping
PONG

[root@xdlinux ➜ redis-stateful-set git:(main) ✗ ]$ redis-cli -h 10.107.73.216 ping
PONG
```

4、水平扩容（增加Redis副本数）：`kubectl scale statefulset redis --replicas=3`

```sh
[root@xdlinux ➜ redis-stateful-set git:(main) ✗ ]$ kubectl scale statefulset redis --replicas=3
statefulset.apps/redis scaled

# 可看到有3个pod了（需要另外手动配置 Redis 主从关系实现读写分离，此处暂不进行后续操作）
[root@xdlinux ➜ redis-stateful-set git:(main) ✗ ]$ kubectl get all
NAME          READY   STATUS    RESTARTS   AGE
pod/redis-0   1/1     Running   0          4m44s
pod/redis-1   1/1     Running   0          6s
pod/redis-2   1/1     Running   0          5s

NAME                     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
service/kubernetes       ClusterIP   10.96.0.1       <none>        443/TCP          6d16h
service/redis-headless   ClusterIP   None            <none>        6379/TCP         4m44s
service/redis-service    NodePort    10.107.73.216   <none>        6379:30000/TCP   2m57s

NAME                     READY   AGE
statefulset.apps/redis   3/3     4m44s
```

纵向扩容则可`kubectl edit statefulset redis`调整硬件资源。

## 5. 小结

基于上篇环境进行基本命令操作；并通过K8S创建了一个Redis的Pod、Service；以及集群扩容操作。过程中由于containerd新版本弃用调整了镜像配置的方式也折腾了挺久，创建Pod后，通过Service对外提供服务访问，增强了一些体感。

## 6. 参考

* [Kubernetes Docs](https://kubernetes.io/docs/concepts/overview/)
    * [Kubernetes中文文档](https://kubernetes.io/zh-cn/docs/concepts/overview/)
* 极客时间：Kubernetes从上手到实践
* LLM
