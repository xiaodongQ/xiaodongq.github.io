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

### 2.2. 部署Ceph

部署（需要依赖时间同步：`chrony`或者传统的`ntpd`，CentOS8默认使用`chrony`）：

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

### 2.3. 登录面板

![ceph-dashboard](/images/2025-05-06-ceph-dashboard.png)

## 3. 小结

## 4. 参考

* [Ceph Document](https://docs.ceph.com/en/reef/)
* [Ceph Git仓库](https://github.com/ceph/ceph)
* LLM