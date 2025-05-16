---
title: Ceph学习笔记（三） -- 跟踪Ceph读写流程
description: 通过demo跟踪Ceph读写处理流程。
categories: [存储和数据库, Ceph]
tags: [存储, Ceph]
---


## 1. 引言

前面梳理了Ceph的基本架构，并简单搭建了Ceph集群。现在进入到代码层，通过demo对Ceph集群进行读写，跟踪梳理代码处理流程。

## 2. Ceph代码结构

先来看下Ceph项目的代码结构。

### 2.1. 子模块

除了Ceph主干代码外，还有很多**git子模块**依赖，这里暂列几个自己关注的：

* 纠删码
    * src/erasure-code/jerasure/jerasure
    * https://github.com/ceph/jerasure.git
* RocksDB
    * src/rocksdb
    * https://github.com/ceph/rocksdb
* SPDK
    * src/spdk
    * https://github.com/ceph/spdk.git
* cpp_redis
    * src/cpp_redis
    * https://github.com/ceph/cpp_redis.git
* opentelemetry-cpp
    * src/jaegertracing/opentelemetry-cpp
    * https://github.com/open-telemetry/opentelemetry-cpp.git
* GoogleTest
    * src/googletest
    * https://github.com/ceph/googletest

### 2.2. 编译

### 2.3. container

container目录用于构建容器，可看到当前版本默认使用`podman`来构建容器。

```sh
# ceph-v19.2.2/container/build.sh
...
podman build --pull=newer --squash -f $CFILE -t build.sh.output \
    --build-arg FROM_IMAGE=${FROM_IMAGE:-quay.io/centos/centos:stream9} \
    --build-arg CEPH_SHA1=${CEPH_SHA1} \
    --build-arg CEPH_GIT_REPO=${CEPH_GIT_REPO} \
    --build-arg CEPH_REF=${BRANCH:-main} \
    --build-arg OSD_FLAVOR=${FLAVOR:-default} \
    --build-arg CI_CONTAINER=${CI_CONTAINER:-default} \
    --secret=id=prerelease_creds,src=./prerelease.secret.txt \
    2>&1 
image_id=$(podman image ls localhost/build.sh.output --format '{{.ID}}')
vars="$(podman inspect -f '{{printf "export CEPH_CONTAINER_ARCH=%v" .Architecture}}' ${image_id})
...
```

默认容器镜像则基于`centos:stream9`。

```dockerfile
# ceph-v19.2.2/container/Containerfile
ARG FROM_IMAGE="quay.io/centos/centos:stream9"
FROM $FROM_IMAGE
...
dnf install -y --setopt=install_weak_deps=False --setopt=skip_missing_names_on_install=False --enablerepo=crb $(cat packages.txt)
...
```

## 3. 小结


## 4. 参考

* [Ceph Document -- Quincy](https://docs.ceph.com/en/quincy/)
* [Ceph Document -- Squid](https://docs.ceph.com/en/squid/)
* [Ceph Git仓库](https://github.com/ceph/ceph)
* LLM