---
title: 服务究竟被谁kill了？ -- 利用SystemTap监测
categories: [Troubleshooting]
tags: SystemTap
---

利用SystemTap监测服务被谁kill了

## 1. 背景

Linux环境上一个应用服务会被定期异常kill掉，但是未直接找到是谁来操作的，后面绕了不少弯后找到了罪魁祸首（简单来说是其他程序bug导致操作错了进程号）。

这种场景若有更针对性的监测手段，会高效很多。基于该背景检索后尝试两种手段：audit审计 和 SystemTap。

本文对SystemTap进行实验。

## 2. 基本用法

stap基本用法：

1. `stap 脚本`，可以传参，并用 $N(表示整数) 或 @N(表示字符串) 引用
2. `stap -e '实现'` 通过命令行指定脚本内容(单引号和双引号均可)
    - 如：`stap -e 'probe syscall.* { }'`
3. `stap -l '单个探测点'`，相对脚本，该方式只有一个探测点
    - 如：`stap -l 'syscall.*'`，部分结果：syscall.wait4
4. `stap -L '单个探测点'`
    - 和-l类似，不过匹配的探测点会加上参数说明
    - 如：`stap -L 'syscall.*'`，部分结果：syscall.wait4 name:string pid:long status_uaddr:long options:long options_str:string rusage_uaddr:long argstr:string

probe追踪常见用法

- begin、end，systemtap会话开始和结束
- kernel.function("sys_open")，探测进入到指定内核函数(可查看内核源码后指定函数进行探测)
    + kernel.function("*@net/socket.c").call，可进一步指定某源码文件及探测时机
- syscall.close.return，探测系统调用，可进一步指定是调用时(.call)还是返回时(.return)
- module("ext3").statement(0xdeadbeef)
- timer.ms(200)，每200ms执行一次，指定exit()则可单次使用
- timer.profile、perf.hw.cache_misses、procfs("status").read
- process("a.out").statement("*@main.c:200") 可指定用户进程

systemtap支持很多内建事件(tapset)，常见内建函数和变量：

- execname() 当前进程名
    + 如：pmdalinux
- pid() 当前进程号、tid()当前线程号
- uid() 当前用户id
- cpu() 当前cpu号
- pp() 当前处理探测点的字符串描述
    + 如：kprobe.function("__x64_sys_openat")
- ppfunc() 探测点函数名
    + __x64_sys_openat
- print_backtrace() 打印调用栈(如果可能的话，If possible)
- print_ubacktrace() 打印用户态调用栈(如果可能的话)
- thread_indent() 是很有用的一个函数
    + 可以输出当前probe所处的可执行程序名称、线程id、函数执行的相对时间和执行的次数（通过空格的数量）信息，它的返回值就是一个字符串。参数delta是在每次调用时增加或移除的空白数量 (未梳理如何得到相对时间的，参考：https://www.cnblogs.com/10087622blog/articles/9592036.html)
    + 查看其实现为：`return _generic_indent (tid(), sprintf("%s(%d)", execname(), tid()), delta)`

具体可以参考官网链接。

## 3. 实验

### 3.1. 安装SystemTap

SystemTap安装中踩了几个坑，具体可见：[动态追踪技术笔记](https://github.com/xiaodongQ/devNoteBackup/blob/master/%E5%90%84%E5%88%86%E7%B1%BB%E8%AE%B0%E5%BD%95/%E5%8A%A8%E6%80%81%E8%BF%BD%E8%B8%AA%E6%8A%80%E6%9C%AF%E7%AC%94%E8%AE%B0.md)

### 3.2. 实验步骤

* 1、运行systemtap探测脚本

脚本内容如下，先直接从参考链接里copy过来用，作用：监测调用kill的进程，同时监测是谁新建的该进程

```sh
#!/usr/bin/stap

global target
global signal

probe kprocess.create
{
    printf("%-25s: %s (%d) created %d\n",
        ctime(gettimeofday_s()), execname(), pid(), new_pid)
}

probe kprocess.exec
{
    printf("%-25s: %s (%d) is exec'ing %s\n",
        ctime(gettimeofday_s()), execname(), pid(), filename)
}

probe nd_syscall.kill
{
    target[tid()] = uint_arg(1);
    signal[tid()] = uint_arg(2);
}

probe nd_syscall.kill.return
{
    if (target[tid()] != 0) {
        printf("%-6d %-12s %-5d %-6d %6d\n", pid(), execname(),
            signal[tid()], target[tid()], int_arg(1));
        delete target[tid()];
        delete signal[tid()];
    }
}
```

* 2、构造kill场景
    1. 后台起循环脚本 `sh test.sh &`
    2. 脚本调用kill -9：`sh xdkill.sh` (内容为`kill -9 $(ps -fe|grep test.sh|grep -v grep|awk '{print $2}')`)

脚本里打印下自身的进程号，如下：

```
[root@anonymous ➜ /home/xd/workspace/systemtap_dir ]$ sh test.sh& 
pid:154293
[root@anonymous ➜ /home/xd/workspace/systemtap_dir ]$ sh xdkill.sh 
pid:154313
[1]  + 154293 killed     sh test.sh
```

* 结果分析

追踪的部分打印如下。可看到可以追踪到kill操作，目前看不是很直观。还要优化下脚本。

```
Mon Oct  2 01:33:53 2023 : zsh (151549) created 154313
Mon Oct  2 01:33:53 2023 : zsh (154313) is exec'ing "/usr/bin/sh"
Mon Oct  2 01:33:53 2023 : sh (154313) created 154314
Mon Oct  2 01:33:53 2023 : sh (154317) is exec'ing "/usr/bin/grep"
Mon Oct  2 01:33:53 2023 : sh (154316) is exec'ing "/usr/bin/grep"
Mon Oct  2 01:33:53 2023 : sh (154314) created 154315
Mon Oct  2 01:33:53 2023 : sh (154314) created 154316
Mon Oct  2 01:33:53 2023 : sh (154314) created 154317
Mon Oct  2 01:33:53 2023 : sh (154314) created 154318
Mon Oct  2 01:33:53 2023 : sh (154318) is exec'ing "/usr/bin/awk"
Mon Oct  2 01:33:53 2023 : sh (154315) is exec'ing "/usr/bin/ps"
154313 sh           9     154293    646
```

## 4. 小结

实验了使用systemtap追踪kill操作。

## 5. 参考

1. [systemtap tutorial](https://sourceware.org/systemtap/tutorial/tutorialse2.html#x4-30002)
2. [使用 Systemtap 排查隐形 Killer](https://www.jianshu.com/p/671014356c41)