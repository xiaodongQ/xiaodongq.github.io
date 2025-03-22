---
layout: post
title: Linux存储IO栈梳理（三） -- eBPF和ftrace跟踪IO写流程
categories: 存储
tags: 存储 IO
---

* content
{:toc}

跟踪Linux存储IO写流程。



## 1. 背景

[Linux存储IO栈梳理（二） -- Linux内核存储栈流程和接口](https://xiaodongq.github.io/2024/08/13/linux-kernel-fs/) 中，我们跟踪了读取的IO调用栈，本篇跟踪下写入操作时的IO调用栈。

环境说明：同上一篇一样，本地CentOS8.5环境只追踪到中断调用栈，先起ECS进行实验了：Alibaba Cloud Linux 3.2104 LTS 64位（内核版本：5.10.134-16.1.al8.x86_64）

## 2. 跟踪点和方式说明

方法跟上篇类似，跟踪VFS层的写操作：`vfs_write`，分别用`bpftrace`和`perf-tools`里的`funcgraph`（其中用的就是`ftrace`）进行跟踪。

对应命令：

* `bpftrace -e 'kprobe:vfs_write { printf("comm:%s, kstack:%s\n", comm, kstack) }'`，并过滤pid
* `funcgraph -H vfs_write`，并用`-p`指定进程pid进行过滤

## 3. demo：经过page cache写

通过信号的方式来触发写入，以便追踪时过滤进程号。

由于`printf`也会用到VFS，注释掉打印提示，只保留一个`write`文件的`vfs_write`调用。

代码：

```cpp
// write_by_signal.cpp
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>


#define FILE_PATH "/home/tempfile"

void signal_handler(int sig)
{
    if (sig == SIGUSR1) {
        // printf("Received SIGUSR1 signal, writing to file...\n");
        FILE *fp = fopen(FILE_PATH, "w");
        if (fp == NULL) {
            perror("fopen");
            exit(1);
        }
        if (fprintf(fp, "hello world\n") < 0) {
            printf("write failed!\n");
            perror("fprintf");
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

代码和Makefile归档：[write_by_signal](https://github.com/xiaodongQ/prog-playground/tree/main/storage/write_by_signal)

### 3.1. 运行跟踪

1、运行：

```sh
[root@iZ2zeftv45jk9frk8u0d0rZ ~]# ./write_tempfile 
pid:4137
```

2、起不同终端，启动跟踪

* `bpftrace -e 'kprobe:vfs_write / pid==4137 / { printf("comm:%s, kstack:%s\n", comm, kstack) }'`
* `./funcgraph -H -p 4137 vfs_write`

3、发送信号 `kill -USR1 4137`，追踪结果下面进行分析

### 3.2. bpftrace结果

这里是调用`vfs_write`函数的调用栈。

```sh
[root@iZ2zeftv45jk9frk8u0d0rZ ~]# bpftrace -e 'kprobe:vfs_write / pid==4137 / { printf("comm:%s, kstack:%s\n", comm, kstack) }'
Attaching 1 probe...
comm:write_tempfile, kstack:
        vfs_write+1
        ksys_write+79
        do_syscall_64+51
        entry_SYSCALL_64_after_hwframe+97
```

### 3.3. funcgraph结果

调用栈特别长，下面用`-m`限制一下堆栈的深度。不限制层数的完整结果见：[funcgragh结果](/images/srcfiles/funcgragh_write_stack.txt)

可大致看到流程：`vfs_write`->`new_sync_write`-> ext4文件系统的`ext4_file_write_iter`，而后获取page cache、写page cache

```sh
[root@iZ2zeftv45jk9frk8u0d0rZ bin]# ./funcgraph -H -p 4137 -m 9 vfs_write
Tracing "vfs_write" for PID 4137... Ctrl-C to end.
# tracer: function_graph
#
# CPU  DURATION                  FUNCTION CALLS
# |     |   |                     |   |   |   |
 0)               |  vfs_write() {
 0)               |    irq_enter_rcu() {
 0)   0.236 us    |      irqtime_account_irq();
 0)   0.779 us    |    }
                        ...
 0)               |    rw_verify_area() {
 0)   0.214 us    |      security_file_permission();
 0)   0.657 us    |    }
 0)               |    new_sync_write() {
 0)               |      ext4_file_write_iter() {
                           # 没指定 O_DIRECT 则走此分支
 0)               |        ext4_buffered_write_iter() {
 0)   0.201 us    |          ext4_fc_start_update();
 0)   0.195 us    |          down_write();
 0)               |          ext4_generic_write_checks() {
 0)               |            generic_write_checks() {
 0)   0.240 us    |              generic_write_check_limits();
 0)   0.635 us    |            }
 0)   0.997 us    |          }
 0)               |          file_modified() {
 0)   0.195 us    |            file_remove_privs();
 0)               |            file_update_time() {
 0)               |              current_time() {
 0)   0.163 us    |                ktime_get_coarse_real_ts64();
 0)   0.505 us    |              }
 0)   0.861 us    |            }
 0)   1.782 us    |          }
 0)               |          generic_perform_write() {
 0)               |            ext4_da_write_begin() {
 0)   0.291 us    |              ext4_nonda_switch();
 0)               |              grab_cache_page_write_begin() {
 0)               |                pagecache_get_page() {
 0)   0.415 us    |                  find_get_entry();
 0)   2.448 us    |                  alloc_pages_current();
 0)   8.323 us    |                  add_to_page_cache_lru();
 0)   0.403 us    |                  irq_enter_rcu();
 0)   1.275 us    |                  __sysvec_irq_work();
 0)   0.326 us    |                  irq_exit_rcu();
 0) + 16.397 us   |                }
 0)   0.158 us    |                wait_for_stable_page();
 0) + 17.226 us   |              }
 0)   0.155 us    |              wait_for_stable_page();
 0)               |              __block_write_begin() {
 0)               |                __block_write_begin_int() {
 0)   1.481 us    |                  create_page_buffers();
 0)   6.616 us    |                  ext4_da_get_block_prep();
 0)   0.967 us    |                  clean_bdev_aliases();
 0) + 11.644 us   |                }
 0) + 12.471 us   |              }
 0) + 31.420 us   |            }
 0)               |            ext4_da_write_end() {
 0)               |              ext4_da_do_write_end() {
 0)               |                block_write_end() {
 0)   3.480 us    |                  __block_commit_write.constprop.0.isra.0();
 0)   4.213 us    |                }
 0)   0.839 us    |                ext4_da_should_update_i_disksize();
 0)   0.201 us    |                unlock_page();
 0)   7.056 us    |              }
 0)   7.951 us    |            }
 0)               |            _cond_resched() {
 0)   0.229 us    |              rcu_all_qs();
 0)   0.638 us    |            }
 0)   0.748 us    |            balance_dirty_pages_ratelimited();
 0) + 42.959 us   |          }
 0)   0.223 us    |          up_write();
 0)   0.206 us    |          ext4_fc_stop_update();
 0) + 48.619 us   |        }
 0) + 49.156 us   |      }
 0) + 50.222 us   |    }
 0)   0.458 us    |    __fsnotify_parent();
 0) + 77.161 us   |  }
```

## 4. demo：不经过page cache写

`open`时指定`O_DIRECT`。

### 4.1. 错误示例

注意：`O_DIRECT`有严格限制，下面的demo在运行时会**报错：`write: Invalid argument`**

```cpp
// write_by_signal_direct.cpp
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>

#define FILE_PATH "/home/tempfile"

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

### 4.2. O_DIRECT 的要求

* 1、对齐要求
    * 对于`O_DIRECT`，数据缓冲区和写入长度必须是文件系统块大小的倍数，比如`xfs`为4K
    * 缓冲区地址本身也必须是对齐的。例如，在 64 位系统上，缓冲区地址可能需要对齐到 4K 边界。
* 2、缓冲区大小：确保你的缓冲区大小与你尝试写入的数据量匹配，并且都是文件系统块大小的整数倍。
* 3、文件位置：确保文件指针的位置也是文件系统块大小的倍数。如果你试图写入的部分数据位于文件系统块边界之间，则会失败。

### 4.3. 正确示例

代码如下，主要通过`posix_memalign`申请内存对齐的数据：

```cpp
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <string.h>

#define FILENAME "/home/tempfile"
#define BUFFER_SIZE (4096 * 2) // 假设文件系统块大小为 4KB，这里写8KB数据
#define BLOCK_SIZE 4096 // 文件系统块大小，通常是 4KB，用于下面的对齐

int fd;
char *buffer;
off_t offset;

void handle_signal(int signum)
{
    if (signum != SIGUSR1) {
        printf("signum: %d not expected!\n", signum);
        exit(1);
    }
    // 写入数据
    if (write(fd, buffer + offset, BUFFER_SIZE - offset) != (BUFFER_SIZE - offset)) {
        perror("Error writing to file");
        exit(1);
    }

    // 更新偏移量
    offset += (BUFFER_SIZE - offset);

    // 如果文件写满了，重置偏移量
    if (offset >= BUFFER_SIZE) {
        offset = 0;
    }

    // printf("Wrote %zu bytes to file.\n", BUFFER_SIZE - offset);
}

int main(void)
{
    pid_t pid = getpid();
    printf("pid:%d\n", pid);

    void *ptr;

    // 初始化偏移量
    offset = 0;

    // 打开文件，使用 O_DIRECT 标志
    fd = open(FILENAME, O_WRONLY | O_CREAT | O_DIRECT, S_IRUSR | S_IWUSR);
    if (fd == -1) {
        perror("Error opening file");
        return 1;
    }

    // 分配缓冲区，并确保它是在页面边界上对齐
    if (posix_memalign(&ptr, BLOCK_SIZE, BUFFER_SIZE) != 0) {
        perror("Memory allocation failed");
        close(fd);
        return 1;
    }

    buffer = (char *)ptr;

    // 填充缓冲区
    memset(buffer, 'X', BUFFER_SIZE);

    // 设置信号处理函数
    signal(SIGUSR1, handle_signal);

    // 主循环
    while (1) {
        pause();
    }

    // 不会执行到这里，因为程序是无限循环
    free(buffer);
    close(fd);
    return 0;
}
```

编译：`g++ -o write_direct write_by_signal_direct.cpp`

代码和Makefile归档：[write_by_signal_direct](https://github.com/xiaodongQ/prog-playground/tree/main/storage/write_by_signal_direct)

### 4.4. 追踪结果

* 调用到`vfs_write`的堆栈：

```sh
[root@iZ2zeftv45jk9frk8u0d0rZ ~]# bpftrace -e 'kprobe:vfs_write / pid==8016 / { printf("comm:%s, kstack:%s\n", comm, kstack) }'
Attaching 1 probe...
comm:write_direct, kstack:
        vfs_write+1
        ksys_write+79
        do_syscall_64+51
        entry_SYSCALL_64_after_hwframe+97
```

* `vfs_write`处理的堆栈

`funcgraph`跟踪的调用栈特别长，完整内容见：[O_DIRECT写入调用栈](/images/srcfiles/funcgragh_write_direct_stack.txt)

这里限制下栈深度，大致流程如下：  
`vfs_write`->`new_sync_write`->`ext4_file_write_iter`，走的是`ext4_dio_write_iter`，就不过page cache了 -> 后面还有io调度处理：`blk_io_schedule`

```sh
[root@iZ2zeftv45jk9frk8u0d0rZ bin]# ./funcgraph -H -p 8016 -m 8 vfs_write
Tracing "vfs_write" for PID 8016... Ctrl-C to end.
# tracer: function_graph
#
# CPU  DURATION                  FUNCTION CALLS
# |     |   |                     |   |   |   |
 1)               |  vfs_write() {
 1)               |    irq_enter_rcu() {
 1)   0.322 us    |      irqtime_account_irq();
 1)   1.066 us    |    }
                        ...
 1)               |    new_sync_write() {
 1)               |      ext4_file_write_iter() {
                           # 原始文件指定了 O_DIRECT 则走此分支
 1)               |        ext4_dio_write_iter() {
 1)   0.355 us    |          down_read();
 1)   0.542 us    |          ext4_inode_journal_mode();
 1)               |          ext4_dio_write_checks() {
 1)               |            ext4_generic_write_checks() {
 1)               |              generic_write_checks() {
 1)   0.306 us    |                generic_write_check_limits();
 1)   0.752 us    |              }
 1)   1.137 us    |            }
 1)               |            ext4_map_blocks() {
 1)               |              ext4_es_lookup_extent() {
 1)   0.321 us    |                _raw_read_lock();
 1)   0.933 us    |              }
 1)               |              __check_block_validity.constprop.0() {
 1)   1.295 us    |                ext4_inode_block_valid();
 1)   1.916 us    |              }
 1)   3.816 us    |            }
 1)               |            file_modified() {
 1)   0.305 us    |              file_remove_privs();
 1)               |              file_update_time() {
 1)   0.440 us    |                current_time();
 1)   0.476 us    |                __mnt_want_write_file();
 1) + 18.490 us   |                generic_update_time();
 1)   0.224 us    |                __mnt_drop_write_file();
 1) + 21.440 us   |              }
 1) + 22.449 us   |            }
 1) + 29.051 us   |          }
 1)               |          iomap_dio_rw() {
 1)               |            __iomap_dio_rw() {
 1)               |              kmem_cache_alloc_trace() {
 1)   0.225 us    |                should_failslab();
 1)   0.884 us    |              }
 1)               |              filemap_write_and_wait_range() {
 1)   0.230 us    |                filemap_check_errors();
 1)   0.759 us    |              }
 1)   0.494 us    |              invalidate_inode_pages2_range();
 1)   0.246 us    |              blk_start_plug();
 1)               |              iomap_apply() {
 1)   1.830 us    |                ext4_iomap_overwrite_begin();
 1) + 22.641 us   |                iomap_dio_actor();
 1)   0.239 us    |                ext4_iomap_end();
 1) + 26.515 us   |              }
 1)               |              blk_finish_plug() {
 1)   0.251 us    |                flush_plug_callbacks();
 1) + 16.815 us   |                blk_mq_flush_plug_list();
 1) + 17.997 us   |              }
 1)               |              blk_io_schedule() {
 1)               |                io_schedule_timeout() {
 0) ! 596.777 us  |                } /* io_schedule_timeout */
 0)   0.614 us    |                irq_enter_rcu();
 0) + 15.096 us   |                __sysvec_irq_work();
 0)   0.511 us    |                irq_exit_rcu();
 0) ! 616.815 us  |              } /* blk_io_schedule */
 0) ! 667.862 us  |            } /* __iomap_dio_rw */
 0)               |            iomap_dio_complete() {
 0)   0.381 us    |              ext4_dio_write_end_io();
 0)   0.283 us    |              wake_up_bit();
 0)               |              kfree() {
 0)   0.247 us    |                __slab_free();
 0)   1.239 us    |              }
 0)   3.027 us    |            }
 0) ! 671.601 us  |          } /* iomap_dio_rw */
 0)   0.183 us    |          up_read();
 0) ! 703.376 us  |        } /* ext4_dio_write_iter */
 0) ! 703.909 us  |      } /* ext4_file_write_iter */
 0) ! 704.567 us  |    } /* new_sync_write */
 0)   0.424 us    |    __fsnotify_parent();
 0) ! 725.418 us  |  } /* vfs_write */
```

## 5. 代码映证

根据上述堆栈流程，和内核的代码相互映证。

### 5.1. VFS：vfs_write

```cpp
// linux-5.10.10/fs/read_write.c
ssize_t vfs_write(struct file *file, const char __user *buf, size_t count, loff_t *pos)
{
    ...
    ret = rw_verify_area(WRITE, file, pos, count);
    ...
    file_start_write(file);
    if (file->f_op->write)
        ret = file->f_op->write(file, buf, count, pos);
    else if (file->f_op->write_iter)
        // 目前看ext4和xfs都走了该分支
        ret = new_sync_write(file, buf, count, pos);
    else
        ret = -EINVAL;
    ...
}
```

### 5.2. VFS：new_sync_write

```cpp
static ssize_t new_sync_write(struct file *filp, const char __user *buf, size_t len, loff_t *ppos)
{
    // struct iovec 是一个在 Unix 和类 Unix 系统（包括 Linux）中广泛使用的结构体，
        // 用于支持分散读取（scatter read）和聚合写入（gather write）的 I/O 操作。
        // 这种机制允许程序在一个系统调用中从多个不同的缓冲区读取或写入数据，而不是像普通的 read 或 write 系统调用那样只处理单一的缓冲区。
        // 使用场景：`readv`、`writev`
    struct iovec iov = { .iov_base = (void __user *)buf, .iov_len = len };
    struct kiocb kiocb;
    // `struct iov_iter` 是 Linux 内核中用于管理 I/O 操作中数据缓冲区的迭代器。
    struct iov_iter iter;
    ssize_t ret;

    // `struct kiocb`结构，Kernel I/O Control Block
        // 用于处理异步 I/O 操作，为每个异步 I/O 请求提供详细的信息和操作控制
        // kiocb 结构体是 aio（异步 I/O）操作的核心数据结构之一，用于描述一个异步 I/O 请求的所有必要信息。
    // 此处根据file结构里的信息初始化IO控制块
    init_sync_kiocb(&kiocb, filp);
    kiocb.ki_pos = (ppos ? *ppos : 0);
    iov_iter_init(&iter, WRITE, &iov, 1, len);

    // 里面调用具体文件的.write_iter
    ret = call_write_iter(filp, &kiocb, &iter);
    BUG_ON(ret == -EIOCBQUEUED);
    if (ret > 0 && ppos)
        *ppos = kiocb.ki_pos;
    return ret;
}
```

```cpp
// linux-5.10.10/include/linux/fs.h
static inline ssize_t call_write_iter(struct file *file, struct kiocb *kio,
                      struct iov_iter *iter)
{
    // 调用具体文件系统的 write_iter 注册接口
    return file->f_op->write_iter(kio, iter);
}
```

### 5.3. ext4：ext4_file_write_iter

ext4的注册接口：

```cpp
// linux-5.10.10/fs/ext4/file.c
const struct file_operations ext4_file_operations = {
    .llseek		= ext4_llseek,
    .read_iter	= ext4_file_read_iter,
    // vfs写会调用此处注册的接口
    .write_iter	= ext4_file_write_iter,
    ...
};
```

`ext4_file_write_iter`实现如下，可以跟上述分别不带和带`O_DIRECT`的两个堆栈对应起来：

```cpp
// ext4注册给 .write_iter 的实现接口
static ssize_t
ext4_file_write_iter(struct kiocb *iocb, struct iov_iter *from)
{
    // 从 struct file 里获取 inode
    struct inode *inode = file_inode(iocb->ki_filp);
    ...
    // vfs层根据file初始化了iocb，file若带了O_DIRECT则进此处语句块
    if (iocb->ki_flags & IOCB_DIRECT)
        return ext4_dio_write_iter(iocb, from);
    else
        // file未指定O_DIRECT，则走buffer写接口
        return ext4_buffered_write_iter(iocb, from);
}
```

## 6. 小结

基于`bpftrace`和`funcgraph`跟踪存储IO写流程，后续基于调用栈，结合代码进一步跟踪学习和梳理。

## 7. 参考

1、[write文件一个字节后何时发起写磁盘IO？](https://mp.weixin.qq.com/s/qEsK6X_HwthWUbbMGiydBQ)

2、GPT
