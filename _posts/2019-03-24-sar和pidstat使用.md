---
layout: post
title: sar和pidstat使用
categories: Linux
tags: Linux sar pidstat 性能监测
---

* content
{:toc}

sar和pidstat使用，监测系统和程序性能状态



## sar

System Activity Reporter, 系统活动情况报告

sar（System Activity Reporter系统活动情况报告）是目前 Linux 上最为全面的系统性能分析工具之一，可以从多方面对系统的活动进行报告，包括：文件的读写情况、系统调用的使用情况、磁盘I/O、CPU效率、内存使用状况、进程活动及IPC有关的活动等。

>sar可用于监控Linux系统性能，帮助我们分析性能瓶颈。sar工具的使用方式为”sar [选项] intervar [count]”，其中interval为统计信息采样时间，count为采样次数。

下文将说明如何使用sar获取以下性能分析数据：

- 整体CPU使用统计
	-u：输出CPU使用情况的统计信息
- 各个CPU使用统计
	“-P ALL”选项指示对每个CPU核输出统计信息：
- 内存使用情况统计
	sar -r 1
- 整体I/O情况
	Report I/O and transfer rate statistics
	sar -b 1, 磁盘I/O的使用情况
- 各个I/O设备情况
	Report activity for each block device.
	sar -d -p 1 1, 块设备sectors扇区读写 (-p显示磁盘名称)
- 网络统计

>sar -n { DEV | EDEV | NFS | NFSD | SOCK | ALL }
DEV显示网络接口信息，EDEV显示关于网络错误的统计数据，NFS统计活动的NFS客户端的信息，NFSD统计NFS服务器的信息，SOCK显示套接字信息，ALL显示所有5个开关。它们可以单独或者一起使用。
sar -n DEV 1 1, 所有网卡


- 怀疑CPU存在瓶颈，可用 sar -u 和 sar -q 等来查看
- 怀疑内存存在瓶颈，可用 sar -B、sar -r 和 sar -W 等来查看
- 怀疑I/O存在瓶颈，可用 sar -b、sar -u 和 sar -d 等来查看

## pidstat

### pidstat -u (默认,CPU使用)

Report CPU utilization.
(%usr:Percentage of CPU used by the task while executing at  the  user  level (application), with or without nice riority.
%system: Percentage of CPU used by the task while executing at the system  level (kernel).
%guest: Percentage  of CPU spent by the task in virtual machine (running a virtual processor).
%CPU: Total percentage of CPU time used by the task. 
)

```py
root@ubuntu:~# pidstat -u -p 1619 1 
Linux 4.4.0-28-generic (ubuntu) 	03/24/2019 	_x86_64_	(1 CPU)

10:38:26 PM   UID       PID    %usr %system  %guest    %CPU   CPU  Command
10:38:27 PM  1000      1619    0.99    0.00    0.00    0.99     0  compiz
10:38:28 PM  1000      1619    1.00    1.00    0.00    2.00     0  compiz
```

usr-ms:Total number of milliseconds spent by the task  and  all  its  children while  executing  at the user level (application),

```py
root@ubuntu:~# pidstat -u -p 1619 1 -T ALL
Linux 4.4.0-28-generic (ubuntu) 	03/24/2019 	_x86_64_	(1 CPU)

10:43:16 PM   UID       PID    %usr %system  %guest    %CPU   CPU  Command
10:43:17 PM  1000      1619    1.00    1.00    0.00    2.00     0  compiz

10:43:16 PM   UID       PID    usr-ms system-ms  guest-ms  Command
10:43:17 PM  1000      1619        10        10         0  compiz
```

### pidstat -d (磁盘io)

pidstat -d -p 1619 1, Report I/O statistics 
(kB_rd:Number  of  kilobytes the task has caused to be read from disk per second.
kB_ccwr: Number  of  kilobytes  whose  writing to disk has been cancelled by the task;
iodelay:Block I/O delay of the task being monitored)

```py
root@ubuntu:~# pidstat -d -p 1619 1
Linux 4.4.0-28-generic (ubuntu) 	03/24/2019 	_x86_64_	(1 CPU)

10:19:12 PM   UID       PID   kB_rd/s   kB_wr/s kB_ccwr/s iodelay  Command
10:19:13 PM  1000      1619      0.00      0.00      0.00       0  compiz
10:19:14 PM  1000      1619      0.00      0.00      0.00       0  compiz
```

### pidstat -r (内存使用)

Report page faults and memory utilization.
(minflt:Total  number of minor faults the task has made per second,
VSZ:Virtual Size: The virtual memory usage of entire task in kilobytes
RSS:Resident  Set Size: The non-swapped physical memory used by the task in kilobytes.)

```py
root@ubuntu:~# pidstat -r -p 1619 1 
Linux 4.4.0-28-generic (ubuntu) 	03/24/2019 	_x86_64_	(1 CPU)

10:25:22 PM   UID       PID  minflt/s  majflt/s     VSZ     RSS   %MEM  Command
10:25:23 PM  1000      1619      0.00      0.00 1442272   60928   6.10  compiz
10:25:24 PM  1000      1619      0.00      0.00 1442272   60928   6.10  compiz
```

### pidstat -s (栈使用)

Report stack utilization. 
(StkSize:The  amount  of memory in kilobytes reserved for the task as stack, but not necessarily used.
StkRef:The amount of memory in kilobytes used  as  stack,  referenced  by  the task.)

```py
root@ubuntu:~# pidstat -s -p 1619 1 
Linux 4.4.0-28-generic (ubuntu) 	03/24/2019 	_x86_64_	(1 CPU)

10:28:14 PM   UID       PID StkSize  StkRef  Command
10:28:15 PM  1000      1619     220      28  compiz
10:28:16 PM  1000      1619     220      28  compiz
```

### -T 是否能打印子线程信息？

### -t 同时打印子线程信息

Also display statistics for threads associated with selected tasks.

```py
root@ubuntu:~# pidstat -s -p 1619 1 -t
Linux 4.4.0-28-generic (ubuntu) 	03/24/2019 	_x86_64_	(1 CPU)

10:34:37 PM   UID      TGID       TID StkSize  StkRef  Command
10:34:38 PM  1000      1619         -     220      32  compiz
10:34:38 PM  1000         -      1619     220      32  |__compiz
10:34:38 PM  1000         -      1626    8192       0  |__gmain
10:34:38 PM  1000         -      1635    8192       8  |__gdbus
10:34:38 PM  1000         -      1640    8192       0  |__dconf worker
10:34:38 PM  1000         -      7507    8192       4  |__pool
```

### -v (其他有用信息, 线程数/文件句柄数等)

Report values of some kernel tables.
(threads: Number of threads associated with current task.
fd-nr: Number of file descriptors associated with current task.)

```py
root@ubuntu:~# pidstat -u -p 1619 1 -v
Linux 4.4.0-28-generic (ubuntu) 	03/24/2019 	_x86_64_	(1 CPU)

10:49:32 PM   UID       PID    %usr %system  %guest    %CPU   CPU  Command
10:49:33 PM  1000      1619    1.00    0.00    0.00    1.00     0  compiz

10:49:32 PM   UID       PID threads   fd-nr  Command
10:49:33 PM  1000      1619       5      29  compiz
```

### -w (上下文切换)

>CPU上下文切换包括
- 进程上下文切换(指针, 栈, 内存,进程状态, 优先级,调度信息,资源信息等,当发生进程切换时，这些保存在寄存器或高速缓存的信息需要记录到内存，以便下次恢复进程的运行。)、
- 线程上下文切换(同一个进程的线程切换，只需保存线程独有的信息，比如栈和寄存器，而共享的虚拟内存和全局变量则无需切换，因此切换开销比进程小。)
- 及中断上下文切换(中断会打断一个正常执行的进程而运行中断处理程序，因为中断处理程序是内核态进程，而不涉及到用户态进程之间的切换，当被中断的是用户态进程时，不需保存和恢复这个进程的虚拟内存和全局变量，中断上下文只包括中断服务程序所需要的状态，比如CPU寄存器、内核堆栈、硬件中断等参数。)
当任务进行io或发生时间片事件及发生中断(如硬件读取完成)时，就会进入内核态，发生CPU上下文切换。

[CPU上下文切换](https://www.cnblogs.com/killianxu/p/10052927.html)

过多的上下文切换会导致将大量CPU时间浪费在寄存器、内核栈以及虚拟内存的保存和恢复上，导致系统整体性能下降。
(vmstat和dstat都可查看系统的cs切换和in中断)

Report task switching activity (kernels 2.6.23 and later only). 
(cswch/s: Total number of voluntary context switches the task made per second. 每秒自愿上下文切换次数，如等待io等
nvcswch/s: Total number of non voluntary context switches the task made per second. 每秒非自愿上下文切换次数，如时间片用完切换。)

```py
root@ubuntu:~# pidstat -w -p 1619 1
Linux 4.4.0-28-generic (ubuntu) 	03/24/2019 	_x86_64_	(1 CPU)

10:55:50 PM   UID       PID   cswch/s nvcswch/s  Command
10:55:51 PM  1000      1619      6.93     24.75  compiz
10:55:52 PM  1000      1619      7.07     24.24  compiz
10:55:53 PM  1000      1619      6.00     20.00  compiz
```
