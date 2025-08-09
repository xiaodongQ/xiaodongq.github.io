---
title: Kubernetes学习实践（四） -- 容器网络
description: 梳理学习容器网络
categories: [云原生, Kubernetes]
tags: [云原生, Kubernetes, 容器网络]
---


## 1. 引言

前几篇了解了基本的K8s操作，终于可以开始梳理容器网络了，这也是之前的核心出发点之一，本篇来搞清楚容器网络相关原理和一些细节。

部分参考链接：

1、[开发内功修炼](https://kfngxl.cn/index.php)中网路篇的一些文章
* 本机网络，涉及`crictl`客户端工具通过`Unix Domain Socket（UDS）`通信方式访问`containerd`
    * [本机网络IO之Unix Domain Socket与普通socket的性能对比 实验使用源码](https://kfngxl.cn/index.php/archives/211/)
    * [127.0.0.1 之本机网络通信过程知多少](https://kfngxl.cn/index.php/archives/195/)
* 
* https://kfngxl.cn/index.php/archives/254/
* https://kfngxl.cn/index.php/archives/415/
* https://kfngxl.cn/index.php/archives/430/
* https://kfngxl.cn/index.php/archives/443/
* https://kfngxl.cn/index.php/archives/460/
* https://kfngxl.cn/index.php/archives/488/

## 2. 本机网络通信方式说明

[Kubernetes学习实践（一） -- 总体说明和基本使用](https://xiaodongq.github.io/2025/07/13/kubernetes-overview/) 中搭建环境时提到需要为容器CLI工具`crictl`新增配置文件（其中的："修复上述警告和crictl命令执行不了的问题"），其中指定了`Unix Domain Socket（UDS）`的通信地址：`unix:///var/run/containerd/containerd.sock`，这里就是指定`UDS`进行`bind`绑定时需要用到的文件路径。

此处来介绍下`Unix Domain Socket`的本机通信方式，并说明其和`127.0.0.1`回环（`loopback`）网络通信的差异，以及和跨主机网络通信的差异。

贴一下`crictl`配置文件相关内容：
```sh
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF
```

### 2.1. 跨主机通信 和 loopback回环网络通信

此处只做总体流程简要说明，进一步细节和代码级流程梳理，可见：[127.0.0.1 之本机网络通信过程知多少](https://kfngxl.cn/index.php/archives/195/)。

1、先来看下最常规情况下的网络通信：2台机器之间进行基本的TCP `socket`交互。流程如下：

![network-process-cross-host](/images/network-process-cross-host.png)

发送方数据经过内核网络协议栈处理，通过**邻居子系统**发送到驱动程序，而后通过**网卡硬件**发出。接收方则也通过**网卡硬件**接收。

2、loopback回环网络通信流程

![network-process-loopback](/images/network-process-loopback.png)

可看到：
* `127.0.0.1`本机回环网络通信时，**<mark>数据不需要经过网卡</mark>**，因此即使拔掉网卡，也不影响本机上通过loopback通信
* 本机回环网络数据流向：还是 **<mark>需要经过跨机通信一样（除了网卡硬件）的各流程处理</mark>**，只是数据不需要经过网卡的`RingBuffer`队列，而是通过**软中断**直接把`skb`传给接收协议栈（本机回环的驱动程序也是一个纯软件的虚拟程序）。

**问题**：访问本机Server时，使用`127.0.0.1​`能比使用本机ip（例如`192.168.x.x`）更快吗？
* 结论：两种使用方法在性能上没有啥差别
* 所有`local`路由表项内核都会标识为`RTN_LOCAL`，查找路由表时（`__ip_route_output_key`），都会路由选择`loopback`虚拟设备

比如我的环境中的`local`路由表：
```sh
[root@xdlinux ➜ ~ ]$ ip route list table local
...
local 127.0.0.0/8 dev lo proto kernel scope host src 127.0.0.1 
local 127.0.0.1 dev lo proto kernel scope host src 127.0.0.1 
broadcast 127.255.255.255 dev lo proto kernel scope link src 127.0.0.1 
# 虽然显示enp4s0，实际上所有的`RTN_LOCAL`项，路由还是会选择loopback 虚拟设备
local 192.168.1.150 dev enp4s0 proto kernel scope host src 192.168.1.150 
broadcast 192.168.1.255 dev enp4s0 proto kernel scope link src 192.168.1.150 
```

这里也贴下参考链接中提到的，在 边车（`sidecar`）代理程序 和 本地进程 间通信时，通过`eBPF`来绕开内核协议栈的开销：  
![ebpf-sidecar](/images/network-process-ebpf-sidecar.png)

### 2.2. Unix Domain Socket



## 3. 小结


## 4. 参考
