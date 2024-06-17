---
layout: post
title: eBPF学习实践系列（三） -- 基于libbpf开发实践
categories: eBPF
tags: eBPF libbpf CO-RE
---

* content
{:toc}

基于libbpf开发实践



## 1. 背景

最近初步学习了`libbpf-bootstrap`和`BCC` (其中的`bcc tools`/`libbpf-tools`)。并在一个环境A里从BCC项目(0.23.0版本)中的`libbpf-tools`移植了`tcpconnect`工具到`libbpf-bootstrap`，成功编译运行了；但是在另一个环境B里(0.19.0版本)，依赖的工具类文件比较多放弃移植测试了。

这里先跳出框架，基于libbpf学习实践，加深些理解，主要参考下面几篇文章。

[使用C语言从头开发一个Hello World级别的eBPF程序](https://tonybai.com/2022/07/05/develop-hello-world-ebpf-program-in-c-from-scratch/)

[eBPF动手实践系列三：基于原生libbpf库的eBPF编程改进方案](https://mp.weixin.qq.com/s/R70hmc965cA8X3WUZRp2hQ)里的demo学习。

## 2. 基于libbpf开发hello world级BPF程序

脱离开libbpf-bootstrap框架，构建一个独立的BPF项目。

[上篇](https://xiaodongq.github.io/2024/06/06/ebpf_learn/)入门学习libbpf-bootstrap，没具体看其结构。示意图如下，我们看下哪些工作可以从框架里抽离出来。

![libbpf-bootstrap结构示意图](/images/2024-06-18-libbpf-bootstrap-module.png)

> libbpf是指linux内核代码库中的tools/lib/bpf，这是内核提供给外部开发者的C库，用于创建BPF用户态的程序。  
> bpf内核开发者为了方便开发者使用libbpf库，特地在github.com上为libbpf建立了镜像仓库：github.com/libbpf/libbpf，这样BPF开发者可以不用下载全量的Linux Kernel代码。

> bpftool对应的是linux内核代码库中的tools/bpf/bpftool，也是在github上创建的对应的镜像库(github.com/libbpf/bpftool)，这是一个bpf辅助工具程序，在libbpf-bootstrap中用于生成xx.skel.h。

> helloworld.bpf.c是bpf程序对应的源码，通过clang -target=bpf编译成BPF字节码ELF文件helloworld.bpf.o。libbpf-bootstrap并没有使用用户态加载程序直接去加载helloworld.bpf.o，而是通过bpftool gen命令基于helloworld.bpf.o生成helloworld.skel.h文件，在生成的helloworld.skel.h文件中包含了BPF程序的字节码以及加载、卸载对应BPF程序的函数，我们在用户态程序直接调用即可。

> helloworld.c是BPF用户态程序，它只需要include helloworld.skel.h并按套路加载、挂接BPF程序到内核层对应的埋点即可。由于BPF程序内嵌到用户态程序中，我们在分发BPF程序时只需分发用户态程序即可！

### 2.1. 编译libbpf和bpftool

1、下载编译libbpf

```sh
git clone https://github.com/libbpf/libbpf.git
cd libbpf/src
NO_PKG_CONFIG=1 make

# 编译产物：
drwxr-xr-x 2 root root 4.0K Jun 17 23:09 staticobjs
-rw-r--r-- 1 root root 4.1M Jun 17 23:09 libbpf.a
drwxr-xr-x 2 root root 4.0K Jun 17 23:09 sharedobjs
-rwxr-xr-x 1 root root 2.1M Jun 17 23:09 libbpf.so.1.5.0
lrwxrwxrwx 1 root root   15 Jun 17 23:09 libbpf.so.1 -> libbpf.so.1.5.0
lrwxrwxrwx 1 root root   11 Jun 17 23:09 libbpf.so -> libbpf.so.1
-rw-r--r-- 1 root root  251 Jun 17 23:09 libbpf.pc
```

2、下载编译bpftool

```sh
git clone https://github.com/libbpf/bpftool.git
# 里面的libbpf是依赖模块，需要init(或者上面git clone时一步到位，添加：`--recurse-submodules`)
git submodule update --init
cd bpftool/src

```

过程中make报错，`yum install llvm`安装后重新编译正常

```sh
make: llvm-strip: Command not found
make: *** [Makefile:211: profiler.bpf.o] Error 127
make: *** Deleting file 'profiler.bpf.o'
```

### 2.2. 安装libbpf库和bpftool工具

bpftool之前其实已经yum安装过了，此处为了实验先把编译产物放到其他目录

```sh
[root@xdlinux ➜ /home/workspace/libbpf-demo/bpftool/src git:(main) ]$ which bpftool
/usr/sbin/bpftool
[root@xdlinux ➜ /home/workspace/libbpf-demo/bpftool/src git:(main) ]$ rpm -qf /usr/sbin/bpftool 
bpftool-4.18.0-348.el8.x86_64
```

## 3. 小结


## 4. 参考

1、[使用C语言从头开发一个Hello World级别的eBPF程序](https://tonybai.com/2022/07/05/develop-hello-world-ebpf-program-in-c-from-scratch/)

2、[eBPF动手实践系列三：基于原生libbpf库的eBPF编程改进方案](https://mp.weixin.qq.com/s/R70hmc965cA8X3WUZRp2hQ)

3、[BPF 系统接口 与 libbpf 示例分析- eBPF基础知识 Part2](https://blog.mygraphql.com/zh/notes/bpf/libbpf/libbpf-bootstrap-study-1-minimal/)

4、[BPF 二进制文件：BTF，CO-RE 和 BPF 性能工具的未来【译】](https://www.ebpf.top/post/bpf-co-re-btf-libbpf/)

5、[BCC 到 libbpf 的转换指南【译】](https://www.ebpf.top/post/bcc-to-libbpf-guid/)

6、GPT
