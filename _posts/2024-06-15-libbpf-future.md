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

最近初步学习了libbpf-bootstrap和BCC (其中的`bcc tools`/`libbpf-tools`)。并在一个环境A里从BCC项目(0.23.0版本)中的libbpf-tools移植了`tcpconnect`工具到libbpf-bootstrap，成功编译运行了；但是在另一个环境B里(0.19.0版本)，依赖的工具类文件比较多就不再移植测试了。

这里先跳出框架，基于libbpf学习实践，加深些理解，主要参考下面几篇文章。

[使用C语言从头开发一个Hello World级别的eBPF程序](https://tonybai.com/2022/07/05/develop-hello-world-ebpf-program-in-c-from-scratch/)

[eBPF动手实践系列三：基于原生libbpf库的eBPF编程改进方案](https://mp.weixin.qq.com/s/R70hmc965cA8X3WUZRp2hQ)

## 2. 基于libbpf开发hello world级BPF程序

脱离开libbpf-bootstrap框架，构建一个独立的BPF项目。

[上篇](https://xiaodongq.github.io/2024/06/06/ebpf_learn/) 学习libbpf-bootstrap时，没具体看其结构。示意图如下，我们看下哪些工作可以从框架里抽离出来。

![libbpf-bootstrap结构示意图](/images/2024-06-18-libbpf-bootstrap-module.png)

> libbpf是指linux内核代码库中的**tools/lib/bpf**，这是内核提供给外部开发者的C库，用于创建BPF用户态的程序。  
> bpf内核开发者为了方便开发者使用libbpf库，特地在github.com上为libbpf建立了镜像仓库：github.com/libbpf/libbpf，这样BPF开发者可以不用下载全量的Linux Kernel代码。

> bpftool对应的是linux内核代码库中的**tools/bpf/bpftool**，也是在github上创建的对应的镜像库(github.com/libbpf/bpftool)，这是一个bpf辅助工具程序，在libbpf-bootstrap中用于生成xx.skel.h。

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
make
```

过程中make报错，`yum install llvm`安装后重新编译正常

```sh
make: llvm-strip: Command not found
make: *** [Makefile:211: profiler.bpf.o] Error 127
make: *** Deleting file 'profiler.bpf.o'
```

编译出的bpftool，查看版本：

```sh
[root@xdlinux ➜ /home/workspace/libbpf-demo/bpftool/src git:(main) ]$ ./bpftool -V
bpftool v7.5.0
using libbpf v1.5
features: skeletons
```

### 2.2. 安装libbpf库和bpftool工具

1、安装libbpf到系统

libbpf之前也安装过，不过只有动态库(版本为0.4.0)，这里还是通过源码安装一下

```sh
[root@xdlinux ➜ /root ]$ rpm -ql libbpf
/usr/lib/.build-id
/usr/lib/.build-id/37
/usr/lib/.build-id/37/b7a980f447665a69005b8ecdd9ca7b5bbc99ee
/usr/lib64/libbpf.so.0
/usr/lib64/libbpf.so.0.4.0
```

上述源码安装：

```sh
[root@xdlinux ➜ /home/workspace/libbpf-demo/libbpf/src git:(master) ]$ BUILD_STATIC_ONLY=1 NO_PKG_CONFIG=1 PREFIX=/usr/local/bpf make install
  INSTALL  bpf.h libbpf.h btf.h libbpf_common.h libbpf_legacy.h bpf_helpers.h bpf_helper_defs.h bpf_tracing.h bpf_endian.h bpf_core_read.h skel_internal.h libbpf_version.h usdt.bpf.h
  INSTALL  ./libbpf.pc
  INSTALL  ./libbpf.a

# 安装后目的目录结构如下
[root@xdlinux ➜ /home/workspace/libbpf-demo/libbpf/src git:(master) ]$ tree /usr/local/bpf
/usr/local/bpf
|-- include
|   `-- bpf
|       |-- bpf.h
|       |-- bpf_core_read.h
|       |-- bpf_endian.h
|       |-- bpf_helper_defs.h
|       |-- bpf_helpers.h
|       |-- bpf_tracing.h
|       |-- btf.h
|       |-- libbpf.h
|       |-- libbpf_common.h
|       |-- libbpf_legacy.h
|       |-- libbpf_version.h
|       |-- skel_internal.h
|       `-- usdt.bpf.h
`-- lib64
    |-- libbpf.a
    `-- pkgconfig
        `-- libbpf.pc

4 directories, 15 files
```

2、安装bpftool

bpftool之前其实已经yum安装过了，此处就不另外安装了

```sh
# 系统中之前安装的bpftool
[root@xdlinux ➜ /home/workspace/libbpf-demo/bpftool/src git:(main) ]$ which bpftool
/usr/sbin/bpftool
[root@xdlinux ➜ /home/workspace/libbpf-demo/bpftool/src git:(main) ]$ rpm -qf /usr/sbin/bpftool 
bpftool-4.18.0-348.el8.x86_64
[root@xdlinux ➜ /home/workspace/libbpf-demo/bpftool/src git:(main) ]$ /usr/sbin/bpftool -V
/usr/sbin/bpftool v4.18.0-348.el8.x86_64
features: libbfd, skeletons
```

### 2.3. 编写helloworld BPF程序

任意目录创建helloworld目录，创建`helloworld.bpf.c`和`helloworld.c`文件，内容和 "[eBPF学习实践系列（一） -- 初识eBPF](https://xiaodongq.github.io/2024/06/06/ebpf_learn/)" 中的示例一样。

创建Makefile：

```sh
# ?=是条件赋值操作符，若变量之前没有被定义，那它就会采用?=后面的值，若之前非空则不作赋值
CLANG ?= clang
ARCH := $(shell uname -m | sed 's/x86_64/x86/' | sed 's/aarch64/arm64/' | sed 's/ppc64le/powerpc/' | sed 's/mips.*/mips/')
BPFTOOL ?= /usr/sbin/bpftool

# 用来-I下面的uapi目录，make install libbpf时不会安装libbpf/include目录
# 但helloworld.bpf.c依赖linux/bpf.h，实际对应的就是 libbpf/include/uapi/linux/bpf.h
LIBBPF_TOP = /home/workspace/libbpf-demo/libbpf

LIBBPF_UAPI_INCLUDES = -I $(LIBBPF_TOP)/include/uapi
# make install libbpf指定路径下的头文件目录
LIBBPF_INCLUDES = -I /usr/local/bpf/include
# install指定了BUILD_STATIC_ONLY=1，此处链接静态库libbpf.a
LIBBPF_LIBS = -L /usr/local/bpf/lib64 -lbpf

INCLUDES=$(LIBBPF_UAPI_INCLUDES) $(LIBBPF_INCLUDES)

# 过滤clang依赖的头文件目录列表，并添加 -idirafter 前缀
CLANG_BPF_SYS_INCLUDES = $(shell $(CLANG) -v -E - </dev/null 2>&1 | sed -n '/<...> search starts here:/,/End of search list./{ s| \(/.*\)|-idirafter \1|p }')

all: build

build: helloworld

# 特别注意： Makefile里面规则定义(下述形式)必须用tab，不能用空格
# clang编译bpf字节码
helloworld.bpf.o: helloworld.bpf.c
	$(CLANG)  -g -O2 -target bpf -D__TARGET_ARCH_$(ARCH) $(INCLUDES) $(CLANG_BPF_SYS_INCLUDES) -c helloworld.bpf.c 

# 根据bpf字节码，用bpftool生成骨架文件
helloworld.skel.h: helloworld.bpf.o
	$(BPFTOOL) gen skeleton helloworld.bpf.o > helloworld.skel.h

# 编译用户空间代码生成二进制程序，链接libbpf.a，代码里还会include上述骨架文件
helloworld: helloworld.skel.h helloworld.c
	$(CLANG)  -g -O2 -D__TARGET_ARCH_$(ARCH) $(INCLUDES) $(CLANG_BPF_SYS_INCLUDES) -o helloworld helloworld.c $(LIBBPF_LIBS) -lbpf -lelf -lz

clean:
	rm -rf helloworld.bpf.o helloworld
```

上述`CLANG_BPF_SYS_INCLUDES`赋值结果为：

```sh
[root@xdlinux ➜ /home/workspace/libbpf-demo ]$ clang -v -E - </dev/null 2>&1 | sed -n '/<...> search starts here:/,/End of search list./{ s| \(/.*\)|-idirafter \1|p }'
-idirafter /usr/local/include
-idirafter /usr/lib64/clang/12.0.1/include
-idirafter /usr/include
```

### 2.4. 编译并执行

编译：

```sh
[root@xdlinux ➜ /home/workspace/libbpf-demo/helloworld ]$ make
clang  -g -O2 -target bpf -D__TARGET_ARCH_x86 -I /home/workspace/libbpf-demo/libbpf/include/uapi -I /usr/local/bpf/include -idirafter /usr/local/include -idirafter /usr/lib64/clang/12.0.1/include -idirafter /usr/include -c helloworld.bpf.c 
/usr/sbin/bpftool gen skeleton helloworld.bpf.o > helloworld.skel.h
libbpf: elf: skipping unrecognized data section(5) .rodata.str1.1
clang  -g -O2 -D__TARGET_ARCH_x86 -I /home/workspace/libbpf-demo/libbpf/include/uapi -I /usr/local/bpf/include -idirafter /usr/local/include -idirafter /usr/lib64/clang/12.0.1/include -idirafter /usr/include -o helloworld helloworld.c -L /usr/local/bpf/lib64 -lbpf -lbpf -lelf -lz
[root@xdlinux ➜ /home/workspace/libbpf-demo/helloworld ]$ ls -ltrh
total 1.7M
-rw-r--r-- 1 root root 1000 Jun 18 13:26 helloworld.bpf.c
-rw-r--r-- 1 root root 1.9K Jun 18 13:26 helloworld.c
-rw-r--r-- 1 root root 1.9K Jun 18 14:22 Makefile
-rw-r--r-- 1 root root 4.3K Jun 18 14:22 helloworld.bpf.o
-rw-r--r-- 1 root root  15K Jun 18 14:22 helloworld.skel.h
-rwxr-xr-x 1 root root 1.7M Jun 18 14:22 helloworld
```

运行：

```sh
[root@xdlinux ➜ /home/workspace/libbpf-demo/helloworld ]$ ./helloworld 
libbpf: loading object 'helloworld_bpf' from buffer
libbpf: elf: section(3) tracepoint/syscalls/sys_enter_execve, size 120, link 0, flags 6, type=1
libbpf: sec 'tracepoint/syscalls/sys_enter_execve': found program 'bpf_prog' at insn offset 0 (0 bytes), code size 15 insns (120 bytes)
libbpf: elf: section(4) .reltracepoint/syscalls/sys_enter_execve, size 16, link 21, flags 0, type=9
...
libbpf: map 'hellowor.rodata': created successfully, fd=4
Successfully started! Please run `sudo cat /sys/kernel/debug/tracing/trace_pipe` to see output of the BPF programs.
.....
```

在另一个窗口中`cat /sys/kernel/debug/tracing/trace_pipe`，可看到执行命令的追踪记录。

## 3. 另一个libbpf实践案例

来自阿里云大数据SRE团队的一篇文章：[eBPF动手实践系列三：基于原生libbpf库的eBPF编程改进方案](https://mp.weixin.qq.com/s/R70hmc965cA8X3WUZRp2hQ)

### 3.1. 获取示例代码

git获取：

```sh
git clone https://github.com/alibaba/sreworks-ext.git
```

这里实验`sreworks-ext/demos/native_libbpf_guide/`下的示例代码，结构如下：

```sh
[root@xdlinux ➜ /home/workspace/sreworks-ext/demos/native_libbpf_guide/trace_execve_libbpf130 git:(main) ]$ tree -L 3
.
|-- Makefile
|-- helpers
|   |-- uprobe_helper.c
|   `-- uprobe_helper.h
|-- include
|   |-- common.h
|   |-- probe_execve.h
|   `-- trace_execve.h
|-- probe_execve.c
|-- progs
|   |-- Makefile
|   |-- probe_execve.bpf.c
|   `-- trace_execve.bpf.c
|-- tools
|   |-- build
|   |   `-- feature
|   |-- include
|   |   |-- asm
|   |   |-- linux
|   |   `-- uapi
|   |-- lib
|   |   `-- bpf
|   `-- scripts
|       |-- Makefile.arch
|       |-- Makefile.include
|       `-- bpf_helpers_doc.py
`-- trace_execve.c

13 directories, 14 files
```

目录说明：

| 目录/文件 | 说明 |
| :--: | :--: |
| `./` | 项目用户态代码和主Makefile |
| `./progs` | 项目内核态bpf程序代码 |
| `./include` | 项目的业务代码相关的头文件 |
| `./helpers` | 非来自于libbpf库的一些helper文件 |
| `./tools/lib/bpf/` | 来自于libbpf-1.3.0/src/的库文件或代码 |
| `./tools/include/` | 来自于libbpf-1.3.0/include/的头文件 |
| `./tools/build/` | 项目构建时一些feature探测代码 |
| `./tools/scripts/` | 项目Makefile所依赖的一些功能函数 |

#### 3.1.1. 如何查看libbpf版本

可从libbpf.map中获得libbpf版本，即其中最大的版本(一般看最后面一个)。

可看到trace_execve_libbpf130里的libbpf版本为`1.3.0`

```sh
# 查看本地的几个工程
[root@xdlinux ➜ /home/workspace ]$ find . -name libbpf.map
./libbpf-bootstrap/libbpf/src/libbpf.map
./libbpf-bootstrap/bpftool/libbpf/src/libbpf.map
./sreworks-ext/demos/native_libbpf_guide/hexdump_skel_libbpf130/tools/lib/bpf/libbpf.map
./sreworks-ext/demos/native_libbpf_guide/skel_execve_libbpf081/tools/lib/bpf/libbpf.map
./sreworks-ext/demos/native_libbpf_guide/trace_execve_libbpf130/tools/lib/bpf/libbpf.map
./sreworks-ext/demos/native_libbpf_guide/trace_user_libbpf130/tools/lib/bpf/libbpf.map
./libbpf-demo/libbpf/src/libbpf.map
./libbpf-demo/bpftool/libbpf/src/libbpf.map

# 此处版本为 1.3.0
[root@xdlinux ➜ /home/workspace ]$ tail -n20 ./sreworks-ext/demos/native_libbpf_guide/trace_execve_libbpf130/tools/lib/bpf/libbpf.map
...
LIBBPF_1.3.0 {
	global:
		bpf_obj_pin_opts;
		bpf_object__unpin;
		...
		ring__size;
		ring_buffer__ring;
} LIBBPF_1.2.0;
```

另外看了下linux-5.10.10内核里的版本，只有0.2.0：

```sh
➜  /Users/xd/Documents/workspace/src/cpp_path tail -40 ./linux-5.10.10/tools/lib/bpf/libbpf.map
...
LIBBPF_0.2.0 {
	global:
		bpf_prog_bind_map;
		bpf_prog_test_run_opts;
		...
		xsk_socket__create_shared;
} LIBBPF_0.1.0;
```

上述./libbpf-demo/libbpf/src/libbpf.map里是clone最新的代码，即截止当前(20240618)最新已经到了1.5.0

```sh
[root@xdlinux ➜ /home/workspace/libbpf-demo ]$ tail ./libbpf-demo/libbpf/src/libbpf.map
		btf__new_split;
		btf_ext__raw_data;
} LIBBPF_1.3.0;

LIBBPF_1.5.0 {
	global:
		bpf_program__attach_sockmap;
		ring__consume_n;
		ring_buffer__consume_n;
} LIBBPF_1.4.0;
```

### 3.2. 代码构建及过程学习

1、代码构建

过程都在Makefile封装好了，直接`make`即可，得到`trace_execve`和`probe_execve`可执行文件。

直接使用：

```sh
[root@xdlinux ➜ /home/workspace/sreworks-ext/demos/native_libbpf_guide/trace_execve_libbpf130 git:(main) ✗ ]$ ./trace_execve
trace_execve 213298500493875 20033 zsh 18068 zsh 0 
trace_execve 213298502952897 20036 zsh 18068 zsh 0 
trace_execve 213298502991619 20035 zsh 20034 zsh 0 
trace_execve 213299519528331 20039 zsh 18068 zsh 0 
trace_execve 213299519554250 20040 zsh 20038 zsh 0
```

2、Makefile说明

trace_execve_libbpf130 项目有4个Makefile，分别如下：

* ./Makefile是主文件，用于生成用户态eBPF程序trace_execve。
* ./progs/Makefile 用于生成内核态BPF程序trace_execve.bpf.o。
* ./tools/lib/bpf/Makefile 用于生成libbpf.a静态库。
* ./tools/build/feature/Makefile 用于一些feature的探测。

3、主Makefile

```sh
# SPDX-License-Identifier: GPL-2.0

CC     = $(CROSS_COMPILE)gcc
LD     = $(CROSS_COMPILE)ld
AS     = $(CROSS_COMPILE)as

HELPERS_PATH := ./helpers
TOOLS_PATH   := ./tools

CFLAGS += -iquote ./helpers/
CFLAGS += -iquote ./include/
CFLAGS += -I./tools/lib/
CFLAGS += -I./tools/include/
CFLAGS += -I./tools/include/uapi/

comma   := ,
dot-target = $(dir $@).$(notdir $@)
depfile = $(subst $(comma),_,$(dot-target).d)

LIBBPF   = $(TOOLS_PATH)/lib/bpf/libbpf.a
LDLIBS  += $(LIBBPF) -lelf -lz -lrt

SOURCES := $(wildcard *.c)

HELPER_OBJECTS := $(patsubst %.c,%.o,$(wildcard $(HELPERS_PATH)/*.c))
LOADER_OBJECT  := $(patsubst %.c,%,$(SOURCES))
USER_OBJECT    := $(patsubst %.c,%.o,$(SOURCES))
BPF_OBJECT     := $(patsubst %.c,./progs/%.bpf.o,$(SOURCES))


.PHONY: clean

clean:
	rm -f *.ll *.o *.d .*.d $(LOADER_OBJECT) $(HELPERS_PATH)/*.o $(HELPERS_PATH)/.*.d
	make -C ./tools/lib/bpf/ clean
	make -C ./tools/build/feature clean
	make -C ./progs/ clean

# 编译静态libbpf.a
$(LIBBPF):
	make -C ./tools/lib/bpf/

# 辅助函数编译
$(HELPER_OBJECTS): %.o:%.c
	$(CC) -Wp,-MD,$(depfile) $(CFLAGS)  -g -c -o $@ $<

# 内核态bpf程序编译，得到bpf字节码
$(BPF_OBJECT):./progs/%.bpf.o:./progs/%.bpf.c
	make -C ./progs/ BPF_TARGET=$(notdir $@)

# 用户态程序编译
$(USER_OBJECT):%.o:%.c
	$(CC) -Wp,-MD,$(depfile) $(CFLAGS)  -g -c -o $@ $<

# 二进制程序，如 trace_execve，根据trace_execve.c名截取
$(LOADER_OBJECT): %:%.o ./progs/%.bpf.o
	$(CC) -g -o $@ $< $(HELPER_OBJECTS) $(LDLIBS)

all: $(LIBBPF) $(HELPER_OBJECTS) $(LOADER_OBJECT)
	@echo "Successfully remade target file 'all'."

.DEFAULT_GOAL := all
```

## 4. 小结

脱离libbpf-bootstrap框架，跟踪学习了基于libbpf的构建过程

## 5. 参考

1、[使用C语言从头开发一个Hello World级别的eBPF程序](https://tonybai.com/2022/07/05/develop-hello-world-ebpf-program-in-c-from-scratch/)

2、[eBPF动手实践系列三：基于原生libbpf库的eBPF编程改进方案](https://mp.weixin.qq.com/s/R70hmc965cA8X3WUZRp2hQ)

3、[BPF 系统接口 与 libbpf 示例分析- eBPF基础知识 Part2](https://blog.mygraphql.com/zh/notes/bpf/libbpf/libbpf-bootstrap-study-1-minimal/)

4、[BPF 二进制文件：BTF，CO-RE 和 BPF 性能工具的未来【译】](https://www.ebpf.top/post/bpf-co-re-btf-libbpf/)

5、[BCC 到 libbpf 的转换指南【译】](https://www.ebpf.top/post/bcc-to-libbpf-guid/)

6、GPT
