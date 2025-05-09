---
title: 服务究竟被谁kill了？ -- 利用audit审计监测
categories: [Troubleshooting]
tags: audit
---

利用audit审计监测服务被谁kill了

## 1. 背景

Linux环境上一个应用服务会被定期异常kill掉，但是未直接找到是谁来操作的，后面绕了不少弯后找到了罪魁祸首（简单来说是其他程序bug导致操作错了进程号）。

这种场景若有更针对性的监测手段，会高效很多。基于该背景检索后尝试两种手段：audit审计 和 SystemTap。

本文先对audit进行实验。

## 2. 实验

网上(同质)资料很多，不贴基本介绍了。

### 2.1. 步骤

监测事件需要先通过auditctrl添加规则，开启对kill系统调用的审计

* 使用命令： `auditctl -a exit,always -F arch=b64 -S kill -F a1=9`

    `-a <l,a>` 添加规则到l后面，此处指定一直添加到exit后面

    `-F f=v` 构建规则，此处`arch=b64`指定64位系统，也可用其他操作符`!=`/`>`/`<`/`>=`等

    `-S syscall` 指定系统调用名称或者编号(32位和64位的编号不同)

    `-F a1=9` a0, a1, a2, a3这四个参数为传给系统调用的参数，此处规则即`kill -9`

* 查询审计记录的方式：

    `ausearch -sc kill`，查询(ausearch)audit日志中的系统调用(-sc)：kill

    `-k,–key` 查询添加规则时指定的关键字

* 操作：

    1. 后台起循环脚本 `sh test.sh &`
    2. 脚本调用kill -9：`sh xdkill.sh`

分别查看audit.log里和auserach的结果，如下：

```sh
# /var/log/audit/audit.log日志文件
# syscall=62，显示的系统调用编号，可通过syscall=xxx去搜索
type=SYSCALL msg=audit(1695710251.567:366042): arch=c000003e syscall=62 success=yes exit=0 a0=1dfd a1=9 a2=0 a3=7ffe8cad2ee0 items=0 ppid=5533 pid=7885 auid=0 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=pts5 ses=7482 comm="sh" exe="/usr/bin/bash" subj=unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023 key=(null)
type=OBJ_PID msg=audit(1695710251.567:366042): opid=7677 oauid=0 ouid=0 oses=7482 obj=unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023 ocomm="sh"
type=PROCTITLE msg=audit(1695710251.567:366042): proctitle=73680078646B696C6C2E7368
```

```sh
# ausearch的结果，打印了一下转换后的时间戳，相对直观一点（对比看内容是一样的）
[root@localhost qxd]# ausearch -sc kill
----
time->Tue Sep 26 14:37:31 2023
type=PROCTITLE msg=audit(1695710251.567:366042): proctitle=73680078646B696C6C2E7368
type=OBJ_PID msg=audit(1695710251.567:366042): opid=7677 oauid=0 ouid=0 oses=7482 obj=unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023 ocomm="sh"
type=SYSCALL msg=audit(1695710251.567:366042): arch=c000003e syscall=62 success=yes exit=0 a0=1dfd a1=9 a2=0 a3=7ffe8cad2ee0 items=0 ppid=5533 pid=7885 auid=0 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=pts5 ses=7482 comm="sh" exe="/usr/bin/bash" subj=unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023 key=(null)
----
```

* 结果说明：

    `type=SYSCALL`是发起者的记录，根据ppid=5533 pid=12256找到调用者的线索。此处12256是xdkill.sh的临时进程号，5533是其父进程-bash

    `type=OBJ_PID`是被操作对象的记录，`opid=7677`即test.sh的pid号

    `type=PROCTITLE`指定此记录提供触发此审计事件的完整命令行，终端直接执行是proctitle=-bash，此处一串可能要转换下

    这个效果来看，可以通过该方式来监测这类事件。

上述调用记录中，syscall=62，系统编号在32位和64位系统下是不一样的：

```c
// 64位下
#define __NR_kill 62

// 32位下
#define __NR_kill 37
```

### 2.2. 其他实用功能/选项

* auditctl选项和示例

    `-k xxx` 指定自定义串，可用于查询过滤，`auditctl -a exit,always -F arch=b64 -S kill -F a1=9 -k xdtest`，查询时基于该串来过滤提高定位效率

    `-F dir` 监控目录路径，`auditctl -a always,exit -F dir=/home/ -F uid=0 -C auid!=obj_uid`

    `-F pid` 监测进程做的动作(日志比较多，不是监测对该进程的操作)，`auditctl -a always,exit -S all -F pid=1005`

    监测目录下的修改 `auditctl -w /etc/ -p wa`，-w指定目录或文件，-p指定操作类型(w:写，a:属性修改)

* 其他用法：

    `auditctl -l` 查看规则列表

    `auditctl -D` 删除所有规则

    `auditctl -d` 删除指定规则，注意要匹配完整的规则，比如上述实验里的规则删除要用`auditctl -d exit,always -F arch=b64 -S kill -F a1=9`

## 3. 小结

1. 实验audit审计监测进程kill操作，比较适用于该场景。
2. audit在其他类似场景下也很有效果。注意使用中配置的规则范围，防止日志刷得太多了。

    1、配置文件被异常修改(如系统时区文件修改、服务配置文件被其他模块异常修改)

    2、文件大小不定期累加，不明确写入方(lsof不好准确监测)

## 4. 参考

1. [linux 上进程被随机kill掉，如何监测和查询](https://www.cnblogs.com/xuyaowen/p/linux-audit.html)
2. man手册
