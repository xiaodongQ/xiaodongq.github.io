---
title: Ceph学习笔记（二） -- 集群部署和相关命令
description: Ceph集群部署和相关命令。
categories: [存储和数据库, Ceph]
tags: [存储, Ceph]
---


## 1. 引言

上篇梳理了Ceph的基本架构和流程，本篇进行集群部署，并梳理学习Ceph相关的命令和状态、进行实践印证。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 安装和部署

见：[Installing Ceph](https://docs.ceph.com/en/quincy/install/)。

有多种方式可以安装`Ceph`，官方推荐的方式：

1、[cephadm](https://docs.ceph.com/en/quincy/cephadm/install/#cephadm-deploying-new-cluster)。
* `cephadm`可以安装和管理Ceph集群。
* 需要容器支持：`Podman`或者`Docker`，以及`Python3`。

2、[Rook](https://rook.io/)
* `Rook`用于`Kubernetes`环境下部署、管理Ceph

此处选择`cephadm`。先安装`cephadm`：

### 2.1. 安装cephadm

```sh
# 看下面网站中17.2.8 el8下没有包，暂时下载17.2.7
[CentOS-root@xdlinux ➜ ~ ]$ curl --silent --remote-name --location https://download.ceph.com/rpm-17.2.7/el8/noarch/cephadm
# 下载下来是个python脚本
[CentOS-root@xdlinux ➜ ~ ]$ chmod +x cephadm

# 支持的选项
[CentOS-root@xdlinux ➜ ~ ]$ ./cephadm --help
usage: cephadm [-h] [--image IMAGE] [--docker] [--data-dir DATA_DIR]
               [--log-dir LOG_DIR] [--logrotate-dir LOGROTATE_DIR]
               [--sysctl-dir SYSCTL_DIR] [--unit-dir UNIT_DIR] [--verbose]
               [--timeout TIMEOUT] [--retry RETRY] [--env ENV]
               [--no-container-init] [--no-cgroups-split]
               {version,pull,inspect-image,ls,list-networks,adopt,rm-daemon,rm-cluster,run,shell,enter,ceph-volume,zap-osds,unit,logs,bootstrap,deploy,check-host,prepare-host,add-repo,rm-repo,install,registry-login,gather-facts,host-maintenance,agent,disk-rescan}
               ...
```

`cephadm`中集成了编排接口（`orchestration interface`）来管理Ceph集群。

具体Python脚本内容可见：[cephadm](https://github.com/xiaodongQ/prog-playground/blob/main/storage/ceph/cephadm)。

### 2.2. 部署Ceph集群

使用cephadm部署集群，命令：`cephadm bootstrap --mon-ip *<mon-ip>*`。

* 需要依赖时间同步：`chrony`或者传统的`ntpd`，CentOS8默认使用`chrony`
* 命令会在本地主机创建一个monitor和manager、生成一个ssh key、创建一个配置文件`/etc/ceph/ceph.conf`、创建`/etc/ceph/ceph.client.admin.keyring`
* 具体操作内容和进一步的选项功能，可见：[running-the-bootstrap-command](https://docs.ceph.com/en/quincy/cephadm/install/#running-the-bootstrap-command)

```sh
[CentOS-root@xdlinux ➜ ~ ]$ ./cephadm --verbose bootstrap --mon-ip 192.168.1.150 
--------------------------------------------------------------------------------
cephadm ['--verbose', 'bootstrap', '--mon-ip', '192.168.1.150']
Verifying podman|docker is present...
Verifying lvm2 is present...
Verifying time synchronization is in place...
...
/usr/bin/docker: stdout Status: Downloaded newer image for quay.io/ceph/ceph:v17
/usr/bin/docker: stdout quay.io/ceph/ceph:v17
# 下载的是17.2.8的镜像
ceph: stdout ceph version 17.2.8 (f817ceb7f187defb1d021d6328fa833eb8e943b3) quincy (stable)
...
Generating a dashboard self-signed certificate...
/usr/bin/ceph: stdout Self-signed certificate created
Creating initial admin user...
/usr/bin/ceph: stdout {"username": "admin", "password": "$2b$12$T/9S/pFZWpiAhd1DneOI4O1eA.qN8Lqs6cLpaT5bHeRE0PTX8FoUS", "roles": ["administrator"], "name": null, "email": null, "lastUpdate": 1746487677, "enabled": true, "pwdExpirationDate": null, "pwdUpdateRequired": true}
...
# dashboard面板页面，由于是在自己另一台Linux PC安装的，替换成 https://192.168.1.150:8443/
Ceph Dashboard is now available at:
   
         URL: https://xdlinux:8443/
        User: admin
    Password: c7y70jlyad
...
You can access the Ceph CLI as following in case of multi-cluster or non-default config:       
    sudo ./cephadm shell --fsid 616bc616-2a08-11f0-86a6-1c697af53932 -c /etc/ceph/ceph.conf -k /etc/ceph/ceph.client.admin.keyring
Or, if you are only running a single cluster on this host:
    sudo ./cephadm shell 
Please consider enabling telemetry to help improve Ceph:
    ceph telemetry on
```

上面部署过程的完整输出，可见：[cephadm_bootstrap.log](https://github.com/xiaodongQ/prog-playground/blob/main/storage/ceph/cephadm_bootstrap.log)。

`docker ps`可看到部署的集群中：
* 包含一个`monitor`和一个`manager`，
* 同时还部署了`node_exporter`、`prometheus`和`grafana`进行状态收集展示。
* 还可以选择开启telemetry分布式链路跟踪。

```sh
[CentOS-root@xdlinux ➜ ~ ]$ docker ps
CONTAINER ID   IMAGE                                     COMMAND                  CREATED          STATUS          PORTS     NAMES
e0c15d412d77   quay.io/ceph/ceph-grafana:9.4.7           "/bin/sh -c 'grafana…"   18 minutes ago   Up 18 minutes             ceph-616bc616-2a08-11f0-86a6-1c697af53932-grafana-xdlinux
b3399062f6fb   quay.io/prometheus/alertmanager:v0.25.0   "/bin/alertmanager -…"   19 minutes ago   Up 19 minutes             ceph-616bc616-2a08-11f0-86a6-1c697af53932-alertmanager-xdlinux
23cb28d71524   quay.io/prometheus/prometheus:v2.43.0     "/bin/prometheus --c…"   19 minutes ago   Up 19 minutes             ceph-616bc616-2a08-11f0-86a6-1c697af53932-prometheus-xdlinux
cbbdea5e241b   quay.io/prometheus/node-exporter:v1.5.0   "/bin/node_exporter …"   20 minutes ago   Up 20 minutes             ceph-616bc616-2a08-11f0-86a6-1c697af53932-node-exporter-xdlinux
8776543913da   quay.io/ceph/ceph                         "/usr/bin/ceph-crash…"   20 minutes ago   Up 20 minutes             ceph-616bc616-2a08-11f0-86a6-1c697af53932-crash-xdlinux
ec87bf5e542b   quay.io/ceph/ceph:v17                     "/usr/bin/ceph-mgr -…"   21 minutes ago   Up 21 minutes             ceph-616bc616-2a08-11f0-86a6-1c697af53932-mgr-xdlinux-wfcgil
955ad744813e   quay.io/ceph/ceph:v17                     "/usr/bin/ceph-mon -…"   21 minutes ago   Up 21 minutes             ceph-616bc616-2a08-11f0-86a6-1c697af53932-mon-xdlinux
```

### 2.3. Dashboard 和 Grafana

上面部署完成后，可登录对应的Dashboard，账号信息打印在上面的部署过程当中。

![ceph-dashboard](/images/2025-05-06-ceph-dashboard.png)

另外还部署了Grafana，包含了默认的一些面板：

![ceph-grafana](/images/2025-05-06-ceph-grafana.png)

主机详情面板：

![ceph-grafana-host-detail](/images/2025-05-06-ceph-grafana-host.png)

### 2.4. Ceph Cli 命令操作

开启 `ceph` 客户端命令操作，有几种方法。

* 方式1、使用 `cephadm shell` 命令进入容器，而后执行客户端命令
    * 也可以直接：`cephadm shell -- ceph -s`，但是每次会很慢
* 方式2、安装`ceph-common`
    * 添加源`cephadm add-repo --release quincy`，而后`cephadm install ceph-common`

一些命令：

* 确认`ceph`命令已安装：`ceph -v`
* 确认`ceph`命令连接到了集群并查看状态：`ceph status`
* Adding Hosts：`ceph orch host label add *<host>* _admin`
* Adding additional MONs：`ceph orch daemon add mon *<host1:ip-or-network1>`
    * 具体见[Deploying additional monitors](https://docs.ceph.com/en/quincy/cephadm/services/mon/#deploying-additional-monitors)
* Adding Storage：`ceph orch apply osd --all-available-devices`

#### 2.4.1. cephadm shell方式

```sh
# 执行cephadm shell，此处加--verbose显示详情
[CentOS-root@xdlinux ➜ ~ ]$ ./cephadm --verbose shell
--------------------------------------------------------------------------------
cephadm ['--verbose', 'shell']
Using default config /etc/ceph/ceph.conf
...
Using container info for daemon 'mon'
Using ceph image with id '259b35566514' and tag 'v17' created on 2024-11-26 08:45:38 +0800 CST
quay.io/ceph/ceph@sha256:a0f373aaaf5a5ca5c4379c09da24c771b8266a09dc9e2181f90eacf423d7326f
...
# 最后会创建并进入一个容器
[ceph: root@xdlinux /]#

# 在容器里可以使用ceph客户端命令
[ceph: root@xdlinux /]# ceph -v
ceph version 17.2.8 (f817ceb7f187defb1d021d6328fa833eb8e943b3) quincy (stable)
[ceph: root@xdlinux /]# ceph -s
  cluster:
    id:     616bc616-2a08-11f0-86a6-1c697af53932
    health: HEALTH_WARN
            OSD count 0 < osd_pool_default_size 3
 
  services:
    mon: 1 daemons, quorum xdlinux (age 13h)
    mgr: xdlinux.wfcgil(active, since 13h)
    osd: 0 osds: 0 up, 0 in
 
  data:
    pools:   0 pools, 0 pgs
    objects: 0 objects, 0 B
    usage:   0 B used, 0 B / 0 B avail
    pgs:
# -h 可看到支持很多命令
[ceph: root@xdlinux /]# ceph -h
...
```

#### 2.4.2. 安装ceph-common

`cephadm shell`每次进入容器再使用`ceph`客户端相关命令，比较麻烦，且宿主机目录和容器中存在隔离，还是在宿主机安装一下`ceph-common`。

CentOS已经不再维护了，之前也已经更改为了阿里云的yum源，但是`cephadm add-repo --release quincy`还是报错了。后面还是得把系统重装一下，换成其他系统。

```sh
[CentOS-root@xdlinux ➜ ~ ]$ ./cephadm add-repo --release quincy
unable to fetch repo metadata: <HTTPError 404: 'Not Found'>
ERROR: failed to fetch repository metadata. please check the provided parameters are correct and try again
```

## 3. 使用Ceph

见：[using-ceph](https://docs.ceph.com/en/quincy/cephadm/install/#using-ceph)

### 3.1. 创建OSD

由于自己的PC环境是在一块SSD上装了双系统，暂时无法使用单独的硬盘或分区来创建OSD，此处<mark>使用目录作为OSD（无需分区）</mark> （参考LLM）。

```sh
[CentOS-root@xdlinux ➜ ~ ]$ mkdir /var/lib/ceph/osd/ceph-0 -p
```

### 3.2. 对象存储

具体见：[cephadm-deploy-rgw](https://docs.ceph.com/en/quincy/cephadm/services/rgw/#cephadm-deploy-rgw)

继续在上述`cephadm shell`进入的客户端容器里，使用`ceph`客户端命令进行集群操作。

简单创建名为`foo`的rgw对象网关（默认会创建2个daemon守护进程）：`ceph orch apply rgw foo`

```sh
# ceph客户端对应的容器中
[ceph: root@xdlinux /]# ceph orch apply rgw foo
Scheduled rgw.foo update...
```

可看到宿主机上创建的2个`radosgw`容器：

```sh
# 宿主机上
[CentOS-root@xdlinux ➜ ceph git:(main) ]$ docker ps
CONTAINER ID   IMAGE                                     COMMAND                  CREATED          STATUS          PORTS     NAMES
18a1c01bf48d   quay.io/ceph/ceph                         "/usr/bin/radosgw -n…"   4 minutes ago    Up 4 minutes              ceph-616bc616-2a08-11f0-86a6-1c697af53932-rgw-foo-xdlinux-yeqiep
c124e7c56c48   quay.io/ceph/ceph                         "/usr/bin/radosgw -n…"   4 minutes ago    Up 4 minutes              ceph-616bc616-2a08-11f0-86a6-1c697af53932-rgw-foo-xdlinux-bsojzq
...
```

## 4. 小结

## 5. 参考

* [Ceph Document -- quincy](https://docs.ceph.com/en/quincy/)
* [Installing Ceph](https://docs.ceph.com/en/quincy/install/)
* [Ceph Git仓库](https://github.com/ceph/ceph)
* LLM