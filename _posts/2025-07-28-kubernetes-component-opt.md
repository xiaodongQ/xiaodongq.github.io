---
title: Kubernetes学习实践（三） -- 关键组件操作实践
description: 进一步对K8S关键组件进行操作实践
categories: [云原生, Kubernetes]
tags: [云原生, Kubernetes]
---


## 1. 引言

通过前面对K8S的环境搭建和Redis环境的部署，已经有一些实践经验了。下面继续对环境中的组件进行操作实践，并简要对比代码，进一步了解K8S各个组件的功能和相关实现。

从 [kubernetes github](https://github.com/kubernetes/kubernetes) 中 [fork](https://github.com/xiaodongQ/kubernetes) 相应代码进行学习，并切换到与当前环境一致的分支：`release-1.33`。

## 2. 集群运行的几个容器

`crictl ps`先查看当前运行的几个容器，可看到K8S集群的几个关键组件：`kube-proxy`、`kube-controller-manager`、`coredns`、`etcd`、`kube-scheduler`、`kube-apiserver`。

```sh
# 省略了部分列
[root@xdlinux ➜ ~ ]$ crictl ps
CONTAINER       IMAGE           STATE    NAME                     POD                               NAMESPACE
2fc197c519935   9b38108e295d1   Running  redis                    redis-2                           default
f87801fdfefbc   9b38108e295d1   Running  redis                    redis-1                           default
558d59adb947c   9b38108e295d1   Running  redis                    redis-0                           default
f51fbab3eb587   af855adae7960   Running  kube-proxy               kube-proxy-6ptwm                  kube-system
0da3e07a247f2   1cf5f116067c6   Running  coredns                  coredns-757cc6c8f8-v2mgf          kube-system
15bd1f6bc3a7f   1cf5f116067c6   Running  coredns                  coredns-757cc6c8f8-nxw7g          kube-system
f6f4852a86c52   bf97fadcef430   Running  kube-controller-manager  kube-controller-manager-xdlinux   kube-system
695cfc514a5ff   499038711c081   Running  etcd                     etcd-xdlinux                      kube-system
c5b9e0185069d   41376797d5122   Running  kube-scheduler           kube-scheduler-xdlinux            kube-system
9ffc7318407b7   a92b4b92a9916   Running  kube-apiserver           kube-apiserver-xdlinux            kube-system

# 可以看下所有namespace下的pod（`--all-namespaces`参数，也可以简写为`-A`，即：`kubectl get pod -A`）
  # `-n kube-system` 指定对应namespace下的pod（不指定则默认只显示default下的pod）
[root@xdlinux ➜ ~ ]$ kubectl get pod --all-namespaces
NAMESPACE     NAME                              READY   STATUS    RESTARTS   AGE
default       redis-0                           1/1     Running   0          4d21h
default       redis-1                           1/1     Running   0          4d21h
default       redis-2                           1/1     Running   0          4d21h
kube-system   coredns-757cc6c8f8-nxw7g          1/1     Running   0          11d
kube-system   coredns-757cc6c8f8-v2mgf          1/1     Running   0          11d
kube-system   etcd-xdlinux                      1/1     Running   2          11d
kube-system   kube-apiserver-xdlinux            1/1     Running   2          11d
kube-system   kube-controller-manager-xdlinux   1/1     Running   0          11d
kube-system   kube-proxy-6ptwm                  1/1     Running   0          4d23h
kube-system   kube-scheduler-xdlinux            1/1     Running   2          11d

# 查看所有namespace：
[root@xdlinux ➜ ~ ]$ kubectl get namespaces
NAME              STATUS   AGE
default           Active   11d
kube-node-lease   Active   11d
kube-public       Active   11d
kube-system       Active   11d
```

再看下第一篇中的架构图进行对比映证：  
![kubernetes-cluster-architecture](/images/kubernetes-cluster-architecture.svg)

下面对各个组件进行操作说明。

## 3. 查看kube-apiserver处理过程

第一篇总体介绍中提到，`kube-apiserver`提供HTTP API服务，并负责处理接收到的请求，是K8S控制平面的核心，并且`kubectl`的操作也是通过调用API来完成的。

可以在执行`kubectl`时，**通过`-v 8`来查看调用API的详细信息**。
* `-v / --v`用于指定详细级别，部分级别说明如下：
* `6` -- HTTP请求路径 + 响应状态码
* `8` -- 完整请求和响应

### 3.1. kubectl version过程

以`kubectl version`查看版本为例：可看到会先加载`/etc/kubernetes/admin.conf`配置文件进行认证

```sh
[root@xdlinux ➜ ~ ]$ kubectl version -v 8 
I0729 21:45:30.645383  778204 loader.go:402] Config loaded from file:  /etc/kubernetes/admin.conf
I0729 21:45:30.645608  778204 envvar.go:172] "Feature gate default state" feature="ClientsAllowCBOR" enabled=false
I0729 21:45:30.645619  778204 envvar.go:172] "Feature gate default state" feature="ClientsPreferCBOR" enabled=false
I0729 21:45:30.645625  778204 envvar.go:172] "Feature gate default state" feature="InformerResourceVersion" enabled=false
I0729 21:45:30.645631  778204 envvar.go:172] "Feature gate default state" feature="InOrderInformers" enabled=true
I0729 21:45:30.645636  778204 envvar.go:172] "Feature gate default state" feature="WatchListClient" enabled=false
I0729 21:45:30.645665  778204 discovery_client.go:657] "Request Body" body=""
I0729 21:45:30.645718  778204 round_trippers.go:527] "Request" verb="GET" url="https://192.168.1.150:6443/version?timeout=32s" headers=<
    Accept: application/json, */*
    User-Agent: kubectl/v1.33.3 (linux/amd64) kubernetes/80779bd
 >
I0729 21:45:30.649450  778204 round_trippers.go:632] "Response" status="200 OK" headers=<
    Audit-Id: ea53bfd7-8bd4-4cbc-9354-e3cbc656c712
    Cache-Control: no-cache, private
    Content-Length: 379
    Content-Type: application/json
    Date: Tue, 29 Jul 2025 13:45:30 GMT
    X-Kubernetes-Pf-Flowschema-Uid: a85b9af0-4d2d-493d-8ebf-b43193f9dd31
    X-Kubernetes-Pf-Prioritylevel-Uid: bb92ee23-b810-4c85-9fbc-b3c9f72105d2
 > milliseconds=3
I0729 21:45:30.649617  778204 discovery_client.go:657] "Response Body" body=<
    {
      "major": "1",
      "minor": "33",
      "emulationMajor": "1",
      "emulationMinor": "33",
      "minCompatibilityMajor": "1",
      "minCompatibilityMinor": "32",
      "gitVersion": "v1.33.3",
      "gitCommit": "80779bd6ff08b451e1c165a338a7b69351e9b0b8",
      "gitTreeState": "clean",
      "buildDate": "2025-07-15T17:59:42Z",
      "goVersion": "go1.24.4",
      "compiler": "gc",
      "platform": "linux/amd64"
    }
 >
Client Version: v1.33.3
Kustomize Version: v5.6.0
Server Version: v1.33.3
```

调用的是`https://192.168.1.150:6443/version`的`GET`接口（需要鉴权的命令则会报错无权限）
* 1）可在浏览器里直接请求 `https://192.168.1.150:6443/version?timeout=32s`，会返回结果信息
* 2）也可用`curl`进行如下请求：

```sh
[root@xdlinux ➜ ~ ]$ curl -k https://192.168.1.150:6443/version\?timeout\=32s
{
  "major": "1",
  "minor": "33",
  "emulationMajor": "1",
  "emulationMinor": "33",
  "minCompatibilityMajor": "1",
  "minCompatibilityMinor": "32",
  "gitVersion": "v1.33.3",
  "gitCommit": "80779bd6ff08b451e1c165a338a7b69351e9b0b8",
  "gitTreeState": "clean",
  "buildDate": "2025-07-15T17:59:42Z",
  "goVersion": "go1.24.4",
  "compiler": "gc",
  "platform": "linux/amd64"
}
```

### 3.2. /etc/kubernetes/admin.conf 配置文件说明

上述`kubectl`执行时，可看到会先加载`/etc/kubernetes/admin.conf`配置文件进行认证。
* `admin.conf`是一个`YAML`格式的kubeconfig文件，该文件记录**集群管理员的认证信息和API服务器地址**
* `kubeadm init`初始化集群时会自动生成该配置文件

```sh
[root@xdlinux ➜ ~ ]$ cat /etc/kubernetes/admin.conf
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: xxx (Base64编码的CA证书)
    server: https://192.168.1.150:6443 (API服务器地址)
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubernetes-admin
  name: kubernetes-admin@kubernetes
current-context: kubernetes-admin@kubernetes
kind: Config
preferences: {}
users:
- name: kubernetes-admin
  user:
    client-certificate-data: xxxxx (Base64编码的客户端证书)
    client-key-data: xxxxxx (Base64编码的客户端私钥)
```

上述配置文件的加载逻辑实现在：`kubernetes/staging/src/k8s.io/client-go/tools/clientcmd/loader.go`
```go
// kubernetes/staging/src/k8s.io/client-go/tools/clientcmd/loader.go
func LoadFromFile(filename string) (*clientcmdapi.Config, error) {
    kubeconfigBytes, err := os.ReadFile(filename)
    if err != nil {
        return nil, err
    }
    config, err := Load(kubeconfigBytes)
    if err != nil {
        return nil, err
    }
}
```

对应的配置结构如下，可以和配置文件的`YAML`格式一一对应：
```go
// kubernetes/staging/src/k8s.io/client-go/tools/clientcmd/api/types.go
type Config struct {
    Kind string `json:"kind,omitempty"`
    APIVersion string `json:"apiVersion,omitempty"`
    // Preferences holds general information to be use for cli interactions
    Preferences Preferences `json:"preferences"`
    // Clusters is a map of referencable names to cluster configs
    Clusters map[string]*Cluster `json:"clusters"`
    // AuthInfos is a map of referencable names to user configs
    AuthInfos map[string]*AuthInfo `json:"users"`
    // Contexts is a map of referencable names to context configs
    Contexts map[string]*Context `json:"contexts"`
    // CurrentContext is the name of the context that you would like to use by default
    CurrentContext string `json:"current-context"`
    // Extensions holds additional information. This is useful for extenders so that reads and writes don't clobber unknown fields
    // +optional
    Extensions map[string]runtime.Object `json:"extensions,omitempty"`
}
```

除此之外，`/etc/kubernetes/`下面的其他几个配置文件（如`kubelet.conf`），也是通过上面的结构体所定义的，查看里面可看到相同的YAML结构。
```sh
[root@xdlinux ➜ ~ ]$ ll /etc/kubernetes/
total 40K
-rw------- 1 root root 5.6K Jul 21 07:47 admin.conf
-rw------- 1 root root 5.6K Jul 21 07:47 controller-manager.conf
-rw------- 1 root root 2.0K Jul 21 07:47 kubelet.conf
drwxr-xr-x 2 root root  113 Jul 22 22:20 manifests
drwxr-xr-x 3 root root 4.0K Jul 21 07:47 pki
-rw------- 1 root root 5.5K Jul 21 07:47 scheduler.conf
-rw------- 1 root root 5.6K Jul 21 07:47 super-admin.conf
```

### 3.3. kubectl proxy绕过认证（Authentication）

`kubectl get pods -v 8` 可看到对应的请求为 `Request" verb="GET" url="https://192.168.1.150:6443/api/v1/namespaces/default/pods?limit=500"`。  
下面通过`curl -k`调用`GET`请求，发现`-k`忽略掉认证过程的curl被判定为`system:anonymous`用户，而此用户没有`list pods`的权限，所以报错了。

```sh
[root@xdlinux ➜ ~ ]$ curl -k https://192.168.1.150:6443/api/v1/namespaces/default/pods\?limit\=500
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "pods is forbidden: User \"system:anonymous\" cannot list resource \"pods\" in API group \"\" in the namespace \"default\"",
  "reason": "Forbidden",
  "details": {
    "kind": "pods"
  },
  "code": 403
}
```

可以通过`kubectl proxy`在本地和集群之间创建一个代理：
```sh
# 会阻塞等待请求，也可加&在后台运行
[root@xdlinux ➜ ~ ]$ kubectl proxy -v8 
I0729 23:23:16.454401  783638 loader.go:402] Config loaded from file:  /etc/kubernetes/admin.conf
Starting to serve on 127.0.0.1:8001

```

而后向`127.0.0.1`的`8001`端口发送`HTTP`（而非`HTTPS`）请求：
* 注意，`192.168.1.150`则不行
* 上面的`kubectl proxy`会使用`/etc/kubernetes/admin.conf`配置文件

```sh
[root@xdlinux ➜ ~ ]$ curl http://127.0.0.1:8001/api/v1/namespaces/default/pods\?limit\=500
{
  "kind": "PodList",
  "apiVersion": "v1",
  "metadata": {
    "resourceVersion": "987772"
  },
  "items": [
    ...
  ]
  ...
}
```

## 4. etcd基本操作

etcd是一个高可用的分布式键值存储系统（键值数据库），存储K8S中的关键配置、所有状态信息等。
* `etcdctl`是官方命令行客户端工具，用于与etcd集群交互，执行键值存储操作、集群管理和监控等任务。

在K8S中，只有`API Server（kube-apiserver）`会直接与etcd交互，其他组件（如`Controller Manager`、`Kubelet`、`Scheduler`等）均通过`API Server`提供的 REST API **间接**操作数据。

### 4.1. 进入etcd pod

本地实验环境中只部署了一个etcd实例，根据上面`kubectl get pods -A`显示的pod，选择进入`etcd`对应的pod：`etcd-xdlinux`。
* 当前基础镜像（取决于不同镜像的配置）对应的`etcd` pod里只安装了`sh`，没安装`bash`，所以下面`--`后面使用`sh`

```sh
[root@xdlinux ➜ ~ ]$ kubectl -n kube-system exec -it etcd-xdlinux -- sh
sh-5.2#
```

而后就可以在容器里通过`etcdctl`进行etcd相关操作了：
* etcd启用了**严格的安全认证机制**，且需要明确操作的目标集群，需要通过参数指定这些信息
* `--endpoints`：指定操作的etcd节点地址，如果不指定，`etcdctl`会使用默认值（http://127.0.0.1:2379）
* 证书参数
    * `--cacert`：CA 根证书路径，用于验证etcd服务器的身份（确保连接的是真实的 etcd 节点，而非伪造的恶意节点）
    * `--cert`和`--key`：客户端证书和私钥，用于向etcd服务器证明自己的身份（etcd 会验证客户端是否有权限操作数据）
    * 这些证书在 Kubernetes 集群中通常存放在 `/etc/kubernetes/pki/etcd/` 目录下，路径是固定的（由 kubeadm 等工具自动生成）。

```sh
# 命令
sh-5.2# etcdctl member list \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key
# 结果
bff3f519f190640f, started, xdlinux, https://192.168.1.150:2380, https://192.168.1.150:2379, false

# etcd的版本
sh-5.2# etcdctl version \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key
etcdctl version: 3.5.21
API version: 3.5
```

小技巧：在etcd Pod内执行export来设置相关环境变量
```sh
export ETCDCTL_API=3
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key
```

### 4.2. 增删改查

设置上述环境变量后，就能省略上述参数来执行基本增删改查命令了：

```sh
# 1、增和改：put
sh-5.2# etcdctl put xdkey1 111
OK

# 2、查：get
sh-5.2# etcdctl get xdkey1
xdkey1
111

# 3、删：del
sh-5.2# etcdctl del xdkey1
1
sh-5.2# etcdctl get xdkey1
sh-5.2# 

# 4、观察监测更新：watch
sh-5.2# etcdctl watch xdkey1
# （上面阻塞会等待监测结果，在另一个窗口操作 etcdctl put xdkey1 ttt）
PUT
xdkey1
tttt
```

另外还支持分布式锁、租约等。

### 4.3. etcd中存储的K8S信息

**K8S存储格式说明：**
* K8S在etcd中以**键值对（Key-Value）**形式存储数据，键的结构与 K8s API 路径高度一致，便于按**资源类型**、**命名空间**等维度组织和查询。
* **键（key）格式**：类似文件系统的分层路径结构，格式为`/registry/<资源类型>/<命名空间>/<资源名称>`
    * 比如：`etcdctl get /registry/pods/default/redis-1`
* **值（Value）格式**：值是经过Protocol Buffers（`protobuf`）序列化的 K8s API 对象，相对于Json更紧凑、序列化效率更高

相关信息查看：

* 查看所有资源的键（简要概览）
    * Kubernetes 资源在 etcd 中的根路径是 `/registry`，查看所有键的列表

```sh
# 只显示值，只看键名（避免输出过多）
sh-5.2# etcdctl get /registry --prefix --keys-only
/registry/apiregistration.k8s.io/apiservices/v1.
/registry/apiregistration.k8s.io/apiservices/v1.admissionregistration.k8s.io
/registry/apiregistration.k8s.io/apiservices/v1.apiextensions.k8s.io
...
```

* 也可进一步过滤`pods`/`services`/`deployments`/`nodes`/`namespace`信息

比如路径前缀：`/registry/namespaces`
```sh
sh-5.2# etcdctl get /registry/namespaces --prefix --keys-only
/registry/namespaces/default
/registry/namespaces/kube-node-lease
/registry/namespaces/kube-public
/registry/namespaces/kube-system
```

* 查看集群成员信息，常用于检查etcd集群的节点状态和成员健康情况：`etcdctl member list`

```sh
sh-5.2# etcdctl member list
# 成员ID           状态     成员名称   Peer通信地址（etcd之间同步数据地址）      客户端通信地址     是否为learner（是则仅同步数据，无投票权）
bff3f519f190640f, started, xdlinux, https://192.168.1.150:2380, https://192.168.1.150:2379, false
```



## 5. 小结



## 6. 参考

* 极客时间：Kubernetes从上手到实践
* LLM