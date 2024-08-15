---
layout: post
title: 学习Linux存储IO栈（三） -- Linux内核通用块层
categories: 存储
tags: 存储 IO
---

* content
{:toc}

梳理学习Linux内核通用块层的相关定义和接口流程。



## 1. 背景

[学习Linux存储IO栈（二） -- Linux内核存储栈流程和接口](https://xiaodongq.github.io/2024/08/13/linux-kernel-fs/) 中，我们跟踪了读取的IO调用栈，本篇跟踪下简单写入操作时的IO调用栈，并学习梳理通用块层的流程和接口。

前置说明：

* demo运行的本地测试环境为：CentOS Linux release 8.5.2111 系统，内核版本为 4.18.0-348.7.1.el8_5.x86_64
* 内核代码基于之前常用的5.10.10版本，分析流程类似

## 2. eBPF 和 ftrace 跟踪写流程

### 2.1. 跟踪点和方式说明

跟上篇类似，这里跟踪VFS层的写操作`vfs_write`，分别用`bpftrace`和`perf-tools`里的`funcgraph`（其实用的就是`ftrace`）进行跟踪。

* `bpftrace -e 'kprobe:vfs_write { printf("comm:%s, kstack:%s\n", comm, kstack) }'`，并过滤pid
* `funcgraph -H vfs_write`，并用`-p`指定进程pid进行过滤

### 2.2. demo：经过page cache写

```cpp
// write_by_signal.cpp
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>


#define FILE_PATH "/tmp/testfile"

void signal_handler(int sig)
{
    if (sig == SIGUSR1) {
        printf("Received SIGUSR1 signal, writing to file...\n");
        FILE *fp = fopen(FILE_PATH, "w");
        if (fp == NULL) {
            perror("fopen");
            exit(1);
        }
        if (fprintf(fp, "hello world\n") < 0) {
            printf("write failed!\n");
            perror("fprintf");
        } else {
            printf("write success\n");
        }
        fclose(fp);
    }
}

int main()
{
    pid_t pid = getpid();
    printf("pid:%d\n", pid);

    // Install signal handler for SIGUSR1
    if (signal(SIGUSR1, signal_handler) == SIG_ERR) {
        perror("signal");
        exit(1);
    }

    while (1) {
        // Do nothing, just wait for signal
        pause();
    }

    return 0;
}
```

编译：`g++ -o write_tempfile write_by_signal.cpp`

### 2.3. 运行跟踪

1、运行：

```sh
[root@xdlinux ➜ write_by_signal git:(main) ✗ ]$ ./write_tempfile 
pid:4847
```

2、起不同终端，启动跟踪

* `bpftrace -e 'kprobe:vfs_write / pid==4847 / { printf("comm:%s, kstack:%s\n", comm, kstack) }'`
* `./funcgraph -H -p 4847 vfs_write`

3、发送信号 `kill -USR1 4847`，追踪结果下面进行分析

```sh
[root@xdlinux ➜ write_by_signal git:(main) ✗ ]$ ./write_tempfile 
pid:4847
Received SIGUSR1 signal, writing to file...
write success
```

#### 2.3.1. bpftrace结果

这里是调用`vfs_write`之前的调用栈。

疑问：为什么会追踪到3次`vfs_write`？

```sh
[root@xdlinux ➜ bin git:(master) ✗ ]$ bpftrace -e 'kprobe:vfs_write / pid==4847 / { printf("comm:%s, kstack:%s\n", comm, kstack) }'
Attaching 1 probe...
comm:write_tempfile, kstack:
        vfs_write+1
        ksys_write+79
        do_syscall_64+91
        entry_SYSCALL_64_after_hwframe+101

comm:write_tempfile, kstack:
        vfs_write+1
        ksys_write+79
        do_syscall_64+91
        entry_SYSCALL_64_after_hwframe+101

comm:write_tempfile, kstack:
        vfs_write+1
        ksys_write+79
        do_syscall_64+91
        entry_SYSCALL_64_after_hwframe+101
```

#### 2.3.2. funcgraph结果

调用栈特别长，下面截取部分。完整结果见：[funcgragh结果](/images/srcfiles/funcgragh_write_stack.txt)

可大致看到流程：`vfs_write`->`new_sync_write`-> xfs文件系统的`xfs_file_write_iter`，而后写page cache

```sh
  1)               |  vfs_write() {
  2)               |    rw_verify_area() {
  3)               |      security_file_permission() {
  4)   0.030 us    |        bpf_lsm_file_permission();
  5)   0.301 us    |      }
  6)   0.521 us    |    }
  7)               |    __sb_start_write() {
  8)               |      _cond_resched() {
  9)   0.040 us    |        rcu_all_qs();
  10)  0.270 us    |      }
  11)  0.961 us    |    }
  12)              |    __vfs_write() {
  13)              |      new_sync_write() {
  14)              |        xfs_file_write_iter [xfs]() {
  15)              |          xfs_file_buffered_aio_write [xfs]() {
  16)              |            xfs_ilock [xfs]() {
  17)              |              down_write() {
  18)              |                _cond_resched() {
  19)  0.030 us    |                  rcu_all_qs();
  20)  0.270 us    |                }
  21)  0.511 us    |              }
  22)  0.772 us    |            }
  23)              |            xfs_file_aio_write_checks [xfs]() {
                                    ...
  7)   4.469 us    |            }
  8)               |            iomap_file_buffered_write() {
  9)               |              iomap_apply() {
  10)              |                xfs_buffered_write_iomap_begin [xfs]() {
  11)  0.231 us    |                  xfs_get_extsz_hint [xfs]();
                                        ...
  54) + 12.764 us   |                }
  55)              |                iomap_write_actor() {
  56)              |                  iomap_write_begin() {
  57)              |                    grab_cache_page_write_begin() {
  58)              |                      pagecache_get_page() {
  59)  0.200 us    |                        find_get_entry();
  60)              |                        __page_cache_alloc() {
  61)              |                          alloc_pages_current() {
                                                ...
  82)  6.452 us    |                          }
  83)  6.742 us    |                        }
  84)              |                        add_to_page_cache_lru() {
                                                ...
  123) + 12.263 us   |                        }
  124) + 20.348 us   |                      }
  125) 0.040 us    |                      wait_for_stable_page();
  126) + 21.249 us   |                    }
  127) 0.060 us    |                    iomap_page_create();
  128) 0.050 us    |                    iomap_adjust_read_range();
  129) 0.040 us    |                    iomap_set_range_uptodate();
  130) + 23.705 us   |                  }
  131)             |                  iomap_write_end.isra.32() {
                                        ...
  27) + 50.495 us   |                  }
  28)              |                  _cond_resched() {
  29)  0.050 us    |                    rcu_all_qs();
  30)  0.692 us    |                  }
  31)  0.260 us    |                  balance_dirty_pages_ratelimited();
  32) + 77.705 us   |                }
  33)  0.611 us    |                xfs_buffered_write_iomap_end [xfs]();
  34) + 93.405 us   |              }
  35) + 94.347 us   |            }
  36)              |            xfs_iunlock [xfs]() {
  37)  0.040 us    |              up_write();
  38)  0.541 us    |            }
  39) ! 101.641 us  |          }
  40) ! 102.573 us  |        }
  41) ! 103.665 us  |      }
  42) ! 104.085 us  |    }
  43)  0.050 us    |    __fsnotify_parent();
  44)  0.090 us    |    fsnotify();
  45)  0.211 us    |    __sb_end_write();
  46) ! 108.193 us  |  }
```

### 2.4. demo：不经过page cache写

`open`时指定`O_DIRECT`。

注意：`O_DIRECT`有严格限制，下面的demo在运行时会报错：`write: Invalid argument`

```cpp
// write_by_signal_direct.cpp
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>

#define FILE_PATH "/tmp/testfile"

// write错误
void signal_handler(int sig)
{
    if (sig == SIGUSR1) {
        printf("Received SIGUSR1 signal, writing to file...\n");
        int fd = open(FILE_PATH, O_WRONLY | O_CREAT | O_DIRECT, 0644);
        if (fd == -1) {
            perror("open");
            exit(1);
        }
        const char *buf = "hello world\n";
        ssize_t bytes_written = write(fd, buf, strlen(buf));
        if (bytes_written != (ssize_t)strlen(buf)) {
            perror("write");
            exit(1);
        }
        printf("write success\n");
        close(fd);
    }
}

int main()
{
    pid_t pid = getpid();
    printf("pid:%d\n", pid);

    // Install signal handler for SIGUSR1
    if (signal(SIGUSR1, signal_handler) == SIG_ERR) {
        perror("signal");
        exit(1);
    }

    while (1) {
        // Do nothing, just wait for signal
        pause();
    }

    return 0;
}
```

编译：`g++ -o write_direct write_by_signal_direct.cpp`

#### 2.4.1. O_DIRECT 的要求

* 1、对齐要求
    * 对于`O_DIRECT`，数据缓冲区和写入长度必须是文件系统块大小的倍数，比如此处`xfs`为4K
    * 缓冲区地址本身也必须是对齐的。例如，在 64 位系统上，缓冲区地址可能需要对齐到 4K 边界。

```sh
[root@xdlinux ➜ write_by_signal_direct git:(main) ✗ ]$ xfs_info /home
meta-data=/dev/mapper/cl_desktop--mme7h3a-home isize=512    agcount=4, agsize=4193792 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=1, sparse=1, rmapbt=0
         =                       reflink=1
data     =                       bsize=4096   blocks=16775168, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
log      =internal log           bsize=4096   blocks=8191, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
```

* 2、缓冲区大小：确保你的缓冲区大小与你尝试写入的数据量匹配，并且都是文件系统块大小的整数倍。
* 3、文件位置：确保文件指针的位置也是文件系统块大小的倍数。如果你试图写入的部分数据位于文件系统块边界之间，则会失败。

## 3. 小结

学习梳理内核中通用块层的定义和接口流程。

## 4. 参考

1、[write文件一个字节后何时发起写磁盘IO？](https://mp.weixin.qq.com/s/qEsK6X_HwthWUbbMGiydBQ)

2、[7.1 文件系统全家桶](https://www.xiaolincoding.com/os/6_file_system/file_system.html)

3、GPT
