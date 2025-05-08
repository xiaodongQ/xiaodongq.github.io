---
title: Ceph学习笔记（二） -- 集群部署和相关命令
description: Ceph集群部署和相关命令。
categories: [存储和数据库, Ceph]
tags: [存储, Ceph]
---


## 1. 引言

上篇梳理了Ceph的基本架构和流程，本篇进行集群部署，并梳理学习Ceph相关的命令和状态、进行实践印证。

> 部分操作基于`Quincy`的文档。系统重装为了Rocky Linux release 9.5 (Blue Onyx)，后续使用Ceph `v19.2.2`新版本：`Squid`。  
> 内核版本：5.14.0-503.14.1；容器：默认使用podman，`yum install docker`会安装一个能使用docker的适配脚本，实际还是调用到podman。
{: .prompt-warning }

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

---

更新Rocky Linux系统后，获取一些资源就比较丝滑了，直接安装`cephadm`对应的包即可。

```sh
[root@xdlinux ➜ workspace ]$ dnf search release-ceph
Last metadata expiration check: 0:58:54 ago on Thu 08 May 2025 08:12:24 PM CST.
================================= Name Matched: release-ceph ==================================
centos-release-ceph-pacific.noarch : Ceph Pacific packages from the CentOS Storage SIG
                                   : repository
centos-release-ceph-quincy.noarch : Ceph Quincy packages from the CentOS Storage SIG repository
centos-release-ceph-reef.noarch : Ceph Reef packages from the CentOS Storage SIG repository
centos-release-ceph-squid.noarch : Ceph Squid packages from the CentOS Storage SIG repository

[root@xdlinux ➜ workspace ]$ nf install --assumeyes cephadm
Last metadata expiration check: 2:44:54 ago on Thu 08 May 2025 08:12:24 PM CST.
Dependencies resolved.
===============================================================================================
 Package                               Architecture   Version             Repository      Size
===============================================================================================
Installing:
 centos-release-ceph-squid             noarch         1.0-1.el9           extras         7.3 k
Installing dependencies:
 centos-release-storage-common         noarch         2-5.el9             extras         8.4 k
...

[root@xdlinux ➜ workspace ]$ dnf install --assumeyes cephadm
CentOS-9-stream - Ceph Squid                                   138 kB/s |  95 kB     00:00    
Dependencies resolved.
===============================================================================================
 Package          Architecture    Version                     Repository                  Size
===============================================================================================
Installing:
 cephadm          noarch          2:19.2.2-1.el9s             centos-ceph-squid          346 k

Transaction Summary
===============================================================================================
Install  1 Package
...
Installed:
  cephadm-2:19.2.2-1.el9s.noarch                                                               

Complete!
```

`cephadm -h`执行报错`ModuleNotFoundError: No module named 'jinja2'`，另外需要再安装下`yum install python-jinja2`。

而后可以用了：

```sh
[root@xdlinux ➜ ~ ]$ cephadm -h
usage: cephadm [-h] [--image IMAGE] [--docker] [--data-dir DATA_DIR] [--log-dir LOG_DIR]
               [--logrotate-dir LOGROTATE_DIR] [--sysctl-dir SYSCTL_DIR]
               [--unit-dir UNIT_DIR] [--verbose] [--log-dest {file,syslog}]
               [--timeout TIMEOUT] [--retry RETRY] [--env ENV] [--no-container-init]
               [--no-cgroups-split]
...
```

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

简单调研了下，初步选择是：`Rocky Linux`或`Ubuntu LTS`，包先都下载了，先试试`Rocky Linux`。

---

更新Rocky Linux系统后，安装`ceph-common`。参考 [enable-ceph-cli](https://docs.ceph.com/en/squid/cephadm/install/#enable-ceph-cli)。

```sh
[root@xdlinux ➜ prog-playground git:(main) ]$ cephadm add-repo --release squid
Writing repo to /etc/yum.repos.d/ceph.repo...
Enabling EPEL...
Completed adding repo.

[root@xdlinux ➜ prog-playground git:(main) ]$ cephadm install ceph-common
Installing packages ['ceph-common']...
```

宿主机可以直接执行`ceph`客户端命令了：

```sh
[root@xdlinux ➜ prog-playground git:(main) ]$ ceph -s  
  cluster:
    id:     75ab91f2-2c23-11f0-8e6f-1c697af53932
    health: HEALTH_WARN
            OSD count 0 < osd_pool_default_size 3
 
  services:
    mon: 1 daemons, quorum xdlinux (age 16m)
    mgr: xdlinux.qnvoyl(active, since 14m)
    osd: 0 osds: 0 up, 0 in
 
  data:
    pools:   0 pools, 0 pgs
    objects: 0 objects, 0 B
    usage:   0 B used, 0 B / 0 B avail
    pgs: 
```

## 3. 使用Ceph

见：[using-ceph](https://docs.ceph.com/en/quincy/cephadm/install/#using-ceph)

### 3.1. 创建OSD

由于自己的PC环境是在一块SSD上装了双系统，暂时无法使用单独的硬盘或分区来创建OSD，此处<mark>使用目录作为OSD（无需分区）</mark>，参考LLM给的思路：

* 创建专用目录
    * mkdir /var/lib/ceph/osd/ceph-0
* 挂载目录（可选）
    * mount --bind /path/to/storage /var/lib/ceph/osd/ceph-0
* 部署OSD
    * ceph-volume lvm prepare --data /var/lib/ceph/osd/ceph-0
    * ceph-volume lvm activate 0  # 根据生成的OSD ID调整

~~TODO：等换了系统再来。~~

---

更新Rocky Linux系统后操作，安装一下`ceph-volume`。

```sh
[root@xdlinux ➜ ~ ]$ dnf install ceph-volume
Last metadata expiration check: 0:14:15 ago on Fri 09 May 2025 12:02:03 AM CST.
Dependencies resolved.
========================================================================================================
 Package                         Architecture      Version             Repository                  Size
========================================================================================================
Installing:
 ceph-volume                     noarch            2:19.2.2-1.el9s     centos-ceph-squid          292 k
Installing dependencies:
 ceph-base                       x86_64            2:19.2.2-1.el9s     centos-ceph-squid          5.2 M
 ceph-osd                        x86_64            2:19.2.2-1.el9s     centos-ceph-squid           16 M
 ceph-selinux                    x86_64            2:19.2.2-1.el9s     centos-ceph-squid           26 k
 python3-packaging               noarch            20.9-5.el9          appstream                   69 k
 python3-pyparsing               noarch            2.4.7-9.el9         baseos                     150 k
 qatlib                          x86_64            24.02.0-1.el9_4     appstream                  220 k
 qatzip-libs                     x86_64            1.2.0-1.el9_4       appstream                   46 k
Installing weak dependencies:
 qatlib-service                  x86_64            24.02.0-1.el9_4     appstream                   35 k

Transaction Summary
========================================================================================================
Install  9 Packages

Total download size: 22 M
Installed size: 81 M
Is this ok [y/N]:
```

创建目录而后用`ceph-volume`部署OSD，还是报错了：

```sh
[root@xdlinux ➜ ~ ]$ ceph-volume lvm prepare --data /var/lib/ceph/osd/ceph-0
 stderr: blkid: error: /var/lib/ceph/osd/ceph-0: Invalid argument
 stderr: Unknown device "/var/lib/ceph/osd/ceph-0": No such device
Running command: /usr/bin/ceph-authtool --gen-print-key
Running command: /usr/bin/ceph-authtool --gen-print-key
Running command: /usr/bin/ceph --cluster ceph --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/ceph.keyring -i - osd new 4b37544e-c2f2-432f-9d87-a4a843bf28d0
...
```

调整方式：通过文件虚拟块设备

* 创建虚拟磁盘文件，truncate -s 200M /ceph-osd.img  # 大小根据需求调整
* 挂载为 Loop 设备，losetup /dev/loop0 /ceph-osd.img
* 使用 LVM 模式部署
    * ceph-volume lvm prepare --data /dev/loop0
    * ceph-volume lvm activate 0

第3步报错：

```sh
[root@xdlinux ➜ ~ ]$ ceph-volume lvm prepare --data /dev/loop0
Running command: /usr/bin/ceph-authtool --gen-print-key
Running command: /usr/bin/ceph-authtool --gen-print-key
Running command: /usr/bin/ceph --cluster ceph --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/ceph.keyring -i - osd new a1fce513-b3c9-4d76-9555-68c4d3cec23b
 stderr: 2025-05-09T00:26:50.493+0800 7f4d6b23d640 -1 auth: unable to find a keyring on /var/lib/ceph/bootstrap-osd/ceph.keyring: (2) No such file or directory
 ...
 stderr: 2025-05-09T00:26:50.495+0800 7f4d68fb2640 -1 monclient(hunting): handle_auth_bad_method server allowed_methods [2] but i only support [1]
 stderr: 2025-05-09T00:26:50.495+0800 7f4d6b23d640 -1 monclient: authenticate NOTE: no keyring found; disabled cephx authentication
 stderr: [errno 13] RADOS permission denied (error connecting to the cluster)
-->  RuntimeError: Unable to create a new OSD id
```

```sh
[root@xdlinux ➜ ~ ]$ ceph auth get-or-create client.bootstrap-osd mon 'allow profile bootstrap-osd' \
  -o /var/lib/ceph/bootstrap-osd/ceph.keyring
[root@xdlinux ➜ ~ ]$ chown ceph:ceph /var/lib/ceph/bootstrap-osd/ceph.keyring
[root@xdlinux ➜ ~ ]$ chmod 0600 /var/lib/ceph/bootstrap-osd/ceph.keyring
[root@xdlinux ➜ ~ ]$ 
[root@xdlinux ➜ ~ ]$ ceph-volume lvm prepare --data /dev/loop0 --cluster ceph
Running command: /usr/bin/ceph-authtool --gen-print-key
Running command: /usr/bin/ceph-authtool --gen-print-key
Running command: /usr/bin/ceph --cluster ceph --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/ceph.keyring -i - osd new 2f3d84e3-4559-4f8a-916c-7323c96ab908
--> Was unable to complete a new OSD, will rollback changes
Running command: /usr/bin/ceph --cluster ceph --name client.bootstrap-osd --keyring /var/lib/ceph/bootstrap-osd/ceph.keyring osd purge-new osd.0 --yes-i-really-mean-it
 stderr: purged osd.0
-->  RuntimeError: Unable to find any LV for zapping OSD: 0
```

好吧，折腾几次都不行，单台PC机器不带盘想骚操作部署OSD有点费劲。暂时不折腾了（TODO）。

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

### 3.3. 一些管理命令

具体见：[cephadm/host-management](https://docs.ceph.com/en/quincy/cephadm/host-management/)、[cephadm/services](https://docs.ceph.com/en/quincy/cephadm/services/)，此处仅试用下少数命令。

**1、主机管理：**

* `ceph orch host ls` 查看主机信息

```sh
[ceph: root@xdlinux /]# ceph orch host ls --detail
HOST     ADDR           LABELS  STATUS  VENDOR/MODEL                            CPU      RAM     HDD  SSD        NIC  
xdlinux  192.168.1.150  _admin          LENOVO TianYi510Pro-14ACN (90RX0051CD)  8C/128T  31 GiB  -    1/512.1GB  2    
1 hosts in cluster
```

**2、服务管理：**

* `ceph orch ls` 查看编排器（orchestrator）已知的服务列表
    * `ceph orch ls --export` 导出yaml格式，可以用于`ceph orch apply -i`
* 查看daemons状态：`ceph orch ps`

```sh
[ceph: root@xdlinux /]# ceph orch ls
NAME                       PORTS        RUNNING  REFRESHED  AGE  PLACEMENT  
alertmanager               ?:9093,9094      1/1  17s ago    23h  count:1    
crash                                       1/1  17s ago    23h  *          
grafana                    ?:3000           1/1  17s ago    23h  count:1    
mgr                                         1/2  17s ago    23h  count:2    
mon                                         1/5  17s ago    23h  count:5    
node-exporter              ?:9100           1/1  17s ago    23h  *          
osd.all-available-devices                     0  -          9h   *          
prometheus                 ?:9095           1/1  17s ago    23h  count:1    
rgw.foo                    ?:80             0/2  17s ago    9h   count:2
```

* 部署daemon：`ceph orch apply <service-name>` 或 `ceph orch apply -i file.yaml`
    * 部署服务是，需要知道到哪些主机部署daemons，以及部署几个。比如：
        * `ceph orch apply mon "host1,host2,host3"`
        * `ceph orch apply prometheus --placement="host1 host2 host3"` 显式指定
    * 为了避免混淆，建议使用yaml指定放置规则（placement specification）

file.yaml 示例：

```yaml
service_type: mon
placement:
  hosts:
   - host1
   - host2
   - host3
```

* 不同服务命令示例
    * monitor：`ceph orch daemon add mon newhost1:10.1.2.123`
    * osd：`ceph orch device ls`
    * rgw：`ceph orch apply rgw foo`
    * cephfs：`ceph fs status`
        * `ceph fs volume create xdfs` 创建文件系统
    * nfs：`ceph nfs cluster ls`
    * ...

```sh
# `ceph fs volume create xdfs` 创建文件系统后，编排器会自动创建MDS
[CentOS-root@xdlinux ➜ ~ ]$ docker ps
CONTAINER ID   IMAGE                                     COMMAND                  CREATED          STATUS          PORTS     NAMES
8af21cee0bc4   quay.io/ceph/ceph                         "/usr/bin/ceph-mds -…"   2 minutes ago    Up 2 minutes              ceph-616bc616-2a08-11f0-86a6-1c697af53932-mds-xdfs-xdlinux-enyulk
7d02ba5f4146   quay.io/ceph/ceph                         "/usr/bin/ceph-mds -…"   2 minutes ago    Up 2 minutes              ceph-616bc616-2a08-11f0-86a6-1c697af53932-mds-xdfs-xdlinux-rrgraq
```

**3、跟踪`cephadm`日志打印**

```sh
# 设置日志等级，默认是info
[ceph: root@xdlinux /]# ceph config set mgr mgr/cephadm/log_to_cluster_level debugug
[ceph: root@xdlinux /]# ceph -W cephadm --watch-debug
cluster:
    id:     616bc616-2a08-11f0-86a6-1c697af53932
    health: HEALTH_WARN
            2 failed cephadm daemon(s)
            Reduced data availability: 1 pg inactive
            OSD count 0 < osd_pool_default_size 3
...
2025-05-06T23:34:28.445677+0000 mgr.xdlinux.wfcgil [DBG]  mgr option ssh_config_file = None
2025-05-06T23:34:28.446521+0000 mgr.xdlinux.wfcgil [DBG]  mgr option device_cache_timeout = 1800
...
```

**4、`cephadm`命令**

```sh
# 查看服务
[CentOS-root@xdlinux ➜ ~ ]$ ./cephadm ls
[
    {
        "style": "cephadm:v1",
        "name": "mon.xdlinux",
        "fsid": "616bc616-2a08-11f0-86a6-1c697af53932",
        "systemd_unit": "ceph-616bc616-2a08-11f0-86a6-1c697af53932@mon.xdlinux",
        "enabled": true,
        "state": "running",
        "service_name": "mon",
        "memory_request": null,
        "memory_limit": null,
        "ports": [],
        "container_id": "955ad744813e3f6fa4ceebb98b4ff7b12e7c7eff0aa15f33aae47c175ab96895",
        "container_image_name": "quay.io/ceph/ceph:v17",
        "container_image_id": "259b3556651452e4de35111bd226d7a17fe902360c7e9e49a4e5da686ffb71c1",
        "container_image_digests": [
            "quay.io/ceph/ceph@sha256:a0f373aaaf5a5ca5c4379c09da24c771b8266a09dc9e2181f90eacf423d7326f"
        ],
        "memory_usage": 380423372,
        "cpu_percentage": "0.32%",
        "version": "17.2.8",
        "started": "2025-05-05T23:27:25.733655Z",
        "created": "2025-05-05T23:27:23.127578Z",
        "deployed": "2025-05-05T23:27:22.769568Z",
        "configured": "2025-05-05T23:29:29.845014Z"
    },
    {
        "style": "cephadm:v1",
        "name": "mgr.xdlinux.wfcgil",
        ...
    },
    ...
]

# 查看具体服务日志
[CentOS-root@xdlinux ➜ ~ ]$ ./cephadm logs --name mon.xdlinux
Inferring fsid 616bc616-2a08-11f0-86a6-1c697af53932
-- Logs begin at Sat 2025-04-19 08:02:16 CST, end at Wed 2025-05-07 07:41:36 CST. --
May 06 07:27:23 xdlinux systemd[1]: Started Ceph mon.xdlinux for 616bc616-2a08-11f0-86a6-1c697>
May 06 07:27:23 xdlinux bash[105457]: debug 2025-05-05T23:27:23.287+0000 7f1dace9c8c0  0 set u>
May 06 07:27:23 xdlinux bash[105457]: debug 2025-05-05T23:27:23.287+0000 7f1dace9c8c0  0 ceph >
...
```

## 4. 小结

基于`cephadm`安装部署ceph集群。使用`CentOS 8.5`有些资源无法获取了，所以自己PC的Linux切换为了`Rocky Linux 9.5`，效率提升不少。

## 5. 参考

* [Ceph Document -- Quincy](https://docs.ceph.com/en/quincy/)
* [Ceph Document -- Squid](https://docs.ceph.com/en/squid/)
* [Ceph Git仓库](https://github.com/ceph/ceph)
* LLM