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
```

再看下第一篇中的架构图进行对比映证：  
![kubernetes-cluster-architecture](/images/kubernetes-cluster-architecture.svg)

下面对

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

除此之外，`/etc/kubernetes/`下面的其他几个配置文件（如`kubelet.conf`），也是通过上面的结构体所定义的。
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

## 4. 小结



## 5. 参考

* 极客时间：Kubernetes从上手到实践
* LLM