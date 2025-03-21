---
layout: post
title: CPU及内存调度（二） -- Linux内存管理
categories: CPU及内存调度
tags: 内存
---

* content
{:toc}

CPU和内存调度相关学习实践系列，本篇梳理Linux内存管理及相关的进程、线程创建。



## 1. 背景

在 [CPU及内存调度（一） -- 进程、线程、系统调用、协程上下文切换](https://xiaodongq.github.io/2025/03/09/context-switch) 中已经介绍过Linux通过页表机制进行内存映射管理，涉及TLB、MMU、缺页中断等，并发与异步编程系列梳理学习中，也涉及内存序和CPU缓存等问题，本篇开始梳理学习Linux内存管理，以及相关的进程、线程创建过程。

主要参考：

* [一步一图带你深入理解 Linux 虚拟内存管理](https://mp.weixin.qq.com/s/uWadcBxEgctnrgyu32T8sQ)
* [一步一图带你深入理解 Linux 物理内存管理](https://mp.weixin.qq.com/s/Cn-oX0W5DrI2PivaWLDpPw)
* 以及进程创建流程相关文章：
    * [Linux进程是如何创建出来的？](https://mp.weixin.qq.com/s/ftrSkVvOr6s5t0h4oq4I2w)
    * [进程和线程之间有什么根本性的区别？](https://mp.weixin.qq.com/s/--S94B3RswMdBKBh6uxt0w)

上述几篇参考文章内容都写得很好。其中内存管理篇由浅入深介绍内存结构、内存管理，并跟踪相关内核代码进行说明，其中用exclidraw画的配图也很直观。本篇博客中的配图，若无特别出处备注，均出自参考文章。

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 进程虚拟内存空间结构

Linux为每个进程分配独立的虚拟内存，各进程间有独立的虚拟地址空间，使用内存时相互隔离。相对于直接使用物理内存，极大扩展了可用空间。

进程在其内存地址空间中的资源访问，由TLB和MMU等组件，映射到真正的物理内存上。虽然虚拟地址可能相同，但实际读写的物理地址是不同的。如下图所示：

![virutal-memory-map](/images/virutal-memory-map.png)

**进程虚拟内存空间的结构：**

代码编译成二进制文件后，需要加载到内存中才能运行。对于32位和64位操作系统，加载到内存中时的结构除了虚拟地址空间大小差异外，其他结构基本类似。

虚拟地址空间从低地址到高地址，组成依次为：**代码段（Text Segment）** -> **数据段（Data Segment）** -> **BSS段（Block Started by Symbol ）** -> **堆（Heap）** -> **栈（Stack）**，再往上是**内核态空间**。且对于64位系统，由于只使用**48位**来描述虚拟内存空间，用户态空间和内核态之间还有一层`canonical address 空洞`。

1、`32位`系统 -- 进程虚拟内存空间结构示意图：

![virtual-memory-struct-32bit](/images/virtual-memory-struct-32bit.png)

说明：

* 32位系统上，指针寻址范围`2^32`，对应虚拟内存空间`4GB`，其中用户态`3GB`，内核态`1GB`
* **保留区**：0x0000 0000 到 `0x0804 8000` 这段虚拟内存地址是一段不可访问的保留区
* 编译期确定：
    * **代码段**：存储二进制文件中的机器码、**数据段**：存储指定了初始值的 全局变量和静态变量、**BSS段**：存储未指定初始值的全局变量和静态变量
* 运行期确定：
    * **堆**：存储动态的申请内存
    * **文件映射与匿名映射区**，用于存储：
        * 1）内存文件映射的系统调用`mmap`，映射的内存空间
        * 2）程序运行依赖的动态链接库，这些动态链接库也有自己的对应的代码段，数据段，BSS 段，加载到内存需要的空间（匿名映射区）
    * **栈**：存储程序运行期间，函数调用过程中用到的局部变量和参数
* 注意几个分段的**地址增长方向**
    * 堆：从低地址到高地址增长
    * 文件映射与匿名映射区：从高地址到低地址增长
    * 栈：从高地址到低地址增长

2、`64位`系统 -- 进程虚拟内存空间结构示意图：

![virtual-memory-struct-64bit](/images/virtual-memory-struct-64bit.png)

* `64位`系统上，只用了48位来表示虚拟内存地址，即`2^48`，`256TB`，用户态和内核态虚拟内存空间各128TB
    * 低128T 的用户态虚拟内存空间，高16位全部为 **0**，高128T 的内核态虚拟内存空间，高16位全部为 **1**
    * 所以根据`高16位`，可以快速判断地址是内核态还是用户态地址
* 和32位系统的不同
    * 高16位空闲地址造成了 `canonical address 空洞`，在这段范围内的虚拟内存地址是不合法的
    * 代码段跟数据段的中间还有一段不可以读写的保护段，防止程序在读写数据段的时候越界访问到代码段，可让越界时直接崩溃，防止它继续往下运行
    * 空间大小不同

`readelf -l`查看二进制程序，可看到`LOAD`对应的`VirtAddr`就是从`0x0000000000400000`开始加载（即代码段）

```sh
[CentOS-root@xdlinux ➜ std_async git:(main) ✗ ]$ readelf -l thread_pool_async_withwait

Elf file type is EXEC (Executable file)
Entry point 0x402370
There are 9 program headers, starting at offset 64

Program Headers:
  Type           Offset             VirtAddr           PhysAddr
                 FileSiz            MemSiz              Flags  Align
...
      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
  LOAD           0x0000000000000000 0x0000000000400000 0x0000000000400000
                 0x00000000000158c0 0x00000000000158c0  R E    0x200000
  LOAD           0x0000000000015c08 0x0000000000615c08 0x0000000000615c08
                 0x0000000000000618 0x0000000000000858  RW     0x200000
  DYNAMIC        0x0000000000015d98 0x0000000000615d98 0x0000000000615d98
                 0x0000000000000220 0x0000000000000220  RW     0x8
...
```

详细说明可见参考链接。

## 3. 内核的进程管理

既然说进程的虚拟内存空间管理，那就离不开进程的创建。下面先看下内核中创建进程的简要流程，再跟进其中涉及的内存管理相关结构和机制。

### 3.1. 进程的核心数据结构

结合 [Linux进程是如何创建出来的？](https://mp.weixin.qq.com/s/ftrSkVvOr6s5t0h4oq4I2w) 和 [进程和线程之间有什么根本性的区别？](https://mp.weixin.qq.com/s/--S94B3RswMdBKBh6uxt0w) 一起梳理。

内核中进程和线程都使用 `task_struct` 来表示，具体可见：[进程和线程之间有什么根本性的区别？](https://mp.weixin.qq.com/s/--S94B3RswMdBKBh6uxt0w)。

其定义在`include/linux/sched.h`中，自己本地5.10.10的内核代码：linux-5.10.10/include/linux/sched.h。

`struct task_struct`中的内容特别多，算上注释和一些空格、条件编译，5.10.10版本里有`700`多行。

对比了一下参考链接（基于3.10.0内核）中的字段，在5.10.10中基本都一样，只是顺序略有不同，所以此处还是贴一下参考链接的结构体定义，便于和后续流程说明保持一致。

```cpp
// linux-5.10.10/include/linux/sched.h
struct task_struct {
    //2.1 进程状态 （标号对应于参考链接中的小章节）
    volatile long state;

    //2.2 进程线程的pid
    pid_t pid;
    pid_t tgid;

    //2.3 进程树关系：父进程、子进程、兄弟进程
    struct task_struct __rcu *parent;
    struct list_head children; 
    struct list_head sibling;
    struct task_struct *group_leader; 

    //2.4 进程调度优先级
    int prio, static_prio, normal_prio;
    unsigned int rt_priority;

    //2.5 进程地址空间
    struct mm_struct *mm, *active_mm;

    //2.6 进程文件系统信息（当前目录等）
    struct fs_struct *fs;

    //2.7 进程打开的文件信息
    struct files_struct *files;

    //2.8 namespaces
    // 命名空间，用于隔离内核资源
    struct nsproxy *nsproxy;
}
```

示意图如下：

![task_struct](/images/task_struct.png)  
[出处](https://mp.weixin.qq.com/s/ftrSkVvOr6s5t0h4oq4I2w)

说明：

* **进程/线程状态** 对应的定义也在 include/linux/sched.h 中
    * 在 [并发与异步编程（三） -- 性能分析工具：gperftools和火焰图](https://xiaodongq.github.io/2025/03/14/async-io-example-profile/) 的介绍中，bcc中的`offcputime`工具就可以通过`--state`来指定过滤线程状态，以避免多线程时部分等待线程影响整体火焰图的展示
    * 常见状态：
        * 0（`TASK_RUNNING`）可执行状态
            * 进程要么正在执行，要么准备执行，涵盖了操作系统层面“运行”和“就绪”两种状态。
            * 处于该状态（比如一个进程被创建并准备好执行）的进程会被放置在 CPU 的运行队列（runqueue）中，等待调度器分配CPU时间片
        * 1（`TASK_INTERRUPTIBLE`）可中断睡眠状态，可被信号唤醒
            * 进程正在等待某个特定的事件发生（如 I/O 完成、信号到来等），这期间会放弃CPU资源进入睡眠状态
            * 内核中，当进程调用某些会导致睡眠的系统调用（如 read、write 等）时，如果所需的资源暂时不可用，进程会将自己的状态设置为 TASK_INTERRUPTIBLE 并加入相应的等待队列
        * 2（`TASK_UNINTERRUPTIBLE`）不可中断睡眠状态，不可被信号唤醒
            * 等待某个特定事件，期间不会响应任何信号，只能等待事件本身发生后才能被唤醒
            * 通常用于一些对系统稳定性要求较高的场景，比如与硬件设备交互，例如进程正在`等待磁盘 I/O 操作完成`
        * 4（`__TASK_STOPPED`）停止状态
            * 进程由于接收到特定的信号（如 SIGSTOP、SIGTSTP 等）而被暂停执行，该状态不会调度到CPU上运行，直到它接收到继续执行的信号（如 SIGCONT）
            * 当内核接收到停止进程的信号时，会将进程的状态设置为 TASK_STOPPED，并将其从运行队列中移除
    * 还有很多状态，可见：linux-5.10.10/include/linux/sched.h
* **进程ID**：有`pid`和`tgid` 2个定义
    * 对于没有创建线程的进程(**只包含一个主线程**)来说，这个 pid 就是进程的 PID，**tgid 和 pid 是相同的**
* 进程树关系，可以通过 `pstree` 命令查看
* **进程地址空间**：`struct mm_struct *mm, *active_mm;`，内存描述符，是**下述章节的重点**，此处暂时不做展开。
* fs_struct：进程文件系统信息
    * 描述进程的文件位置等信息
* files_struct：进程打开的文件信息
    * 每个进程用一个 files_struct 结构来记录文件描述符的使用情况， 这个 files_struct 结构称为用户打开文件表。
    * 其中核心结构：`struct file __rcu * fd_array[NR_OPEN_DEFAULT];`，在数组元素中记录了当前进程打开的每一个文件的指针。这个文件是 Linux 中抽象的文件，可能是真的磁盘上的文件，也可能是一个 socket。
    * 定义位于：`linux-5.10.10/include/linux/fdtable.h`

### 3.2. 进程、线程创建流程

在应用代码里面，我们一般会用`fork`及`clone`系统调用创建子进程，这里来跟踪梳理下`fork`的简要流程。

系统调用一般是 `SYSCALL_DEFINEx` 形式，`x`则为参数个数，比如`fork`没有传入参数，其定义为`SYSCALL_DEFINE0(fork)`，位于`kernel/fork.c`。

如下，可见不管是`fork`、`vfork`还是`clone`，设置参数后，都是调用`kernel_clone`函数（3.10内核的调用层次略有不同）。

* 创建进程使用`fork`系统调用
* 创建线程使用`clone`系统调用
    * `pthread_create`创建线程，接口实现在glibc中，代码可见：`glibc/nptl/pthread_create.c`
        * `versioned_symbol (libc, __pthread_create_2_1, pthread_create, GLIBC_2_34);`，此处定义别名，即`pthread_create`是`__pthread_create_2_1`的别名
        * 调用关系为：`pthread_create` -> `__pthread_create_2_1` -> `create_thread` -> `__clone_internal`，其中包装了`clone`不同参数个数的系统调用
* 从下面的定义可以看出，创建进程和线程均会调用`kernel_clone`，根据传入参数的不同确定不同处理逻辑

上述几个系统调用的定义：

```cpp
// linux-5.10.10/kernel/fork.c
// fork和vfork定义，省略了部分条件编译相关判断分支
#ifdef __ARCH_WANT_SYS_FORK
SYSCALL_DEFINE0(fork)
{
    struct kernel_clone_args args = {
        .exit_signal = SIGCHLD,
    };
    return kernel_clone(&args);
}
#endif

#ifdef __ARCH_WANT_SYS_VFORK
SYSCALL_DEFINE0(vfork)
{
    struct kernel_clone_args args = {
        .flags		= CLONE_VFORK | CLONE_VM,
        .exit_signal	= SIGCHLD,
    };

    return kernel_clone(&args);
}
#endif

// clone系统调用定义节选
SYSCALL_DEFINE5(clone, unsigned long, clone_flags, unsigned long, newsp,
         int __user *, parent_tidptr,
         int __user *, child_tidptr,
         unsigned long, tls)
{
    struct kernel_clone_args args = {
        .flags		= (lower_32_bits(clone_flags) & ~CSIGNAL),
        .pidfd		= parent_tidptr,
        .child_tid	= child_tidptr,
        .parent_tid	= parent_tidptr,
        .exit_signal	= (lower_32_bits(clone_flags) & CSIGNAL),
        .stack		= newsp,
        .tls		= tls,
    };

    return kernel_clone(&args);
}
```

继续跟踪调用流程，`kernel_clone`的核心是一个`copy_process`函数，通过拷贝父进程/线程的方式，复制一个新的`task_struct`并进行各种核心对象的拷贝处理。

```cpp
// linux-5.10.10/kernel/fork.c
pid_t kernel_clone(struct kernel_clone_args *args)
{
    struct task_struct *p;
    ...
    // 核心是一个 copy_process 函数
    // 复制一个 task_struct 出来
    p = copy_process(NULL, trace, NUMA_NO_NODE, args);
    ...
    pid = get_task_pid(p, PIDTYPE_PID);
    nr = pid_vnr(pid);
    ...
    // 子任务加入到就绪队列中去，等待调度器调度
    wake_up_new_task(p);
    ...
    put_pid(pid);
    return nr;
}
```

`copy_process`函数逻辑很长（5.10.10中500多行），截取部分核心流程，看下具体复制什么内容，其中`args`就是上述传入的参数结构：

```cpp
// linux-5.10.10/kernel/fork.c
// 说明：基于5.10.10代码，保留了参考链接对应的标号，便于对照查看
static __latent_entropy struct task_struct *copy_process(
                    struct pid *pid,
                    int trace,
                    int node,
                    struct kernel_clone_args *args)
{
    int pidfd = -1, retval;
    // 用于复制进程 task_struct 结构体
    struct task_struct *p;
    ...

    //3.1 复制进程 task_struct 结构体
    p = dup_task_struct(current, node);
    ...

    //3.2 拷贝 files_struct
    retval = copy_files(clone_flags, p);

    //3.3 拷贝 fs_struct
    retval = copy_fs(clone_flags, p);

    // 拷贝信号处理结构
    retval = copy_sighand(clone_flags, p);
    // 拷贝信号
    retval = copy_signal(clone_flags, p);

    //3.4 拷贝 mm_struct
    retval = copy_mm(clone_flags, p);

    //3.5 拷贝进程的命名空间 nsproxy
    retval = copy_namespaces(clone_flags, p);

    // 拷贝io上下文：io_context
    retval = copy_io(clone_flags, p);
    // 拷贝线程相关信息
    retval = copy_thread(clone_flags, args->stack, args->stack_size, p, args->tls);

    //3.6 申请 pid && 设置进程号
    if (pid != &init_struct_pid) {
        pid = alloc_pid(p->nsproxy->pid_ns_for_children, args->set_tid,
                args->set_tid_size);
    }
    ...
    p->pid = pid_nr(pid);
    if (clone_flags & CLONE_THREAD) {
        p->group_leader = current->group_leader;
        p->tgid = current->tgid;
    } else {
        p->group_leader = p;
        // 如果不是创建线程，则设置 tgid 为pid
        p->tgid = p->pid;
    }
    ...
}
```

各核心结构的复制操作，本篇不做展开，仅以 拷贝`files_struct` 为例，创建线程时指定了`CLONE_FILES`：

```c
// linux-5.10.10/kernel/fork.c
static int copy_files(unsigned long clone_flags, struct task_struct *tsk)
{
    struct files_struct *oldf, *newf;
    ...
    oldf = current->files;
    if (!oldf)
        goto out;

    // 传入参数中若指定了 CLONE_FILES，则不复制新的fd文件列表，而只是计数+1
    if (clone_flags & CLONE_FILES) {
        atomic_inc(&oldf->count);
        goto out;
    }

    newf = dup_fd(oldf, NR_OPEN_MAX, &error);
    if (!newf)
        goto out;
    tsk->files = newf;
    ...
}
```

glibc创建线程时，指定了很多flag：

```c
// glibc/nptl/pthread_create.c
const int clone_flags = (CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SYSVSEM
                           | CLONE_SIGHAND | CLONE_THREAD
                           | CLONE_SETTLS | CLONE_PARENT_SETTID
                           | CLONE_CHILD_CLEARTID
                           | 0);
```

对于创建进程和创建线程的不同，这里用 [进程和线程之间有什么根本性的区别？](https://mp.weixin.qq.com/s/--S94B3RswMdBKBh6uxt0w) 中的两张图进行说明：

**创建进程**：地址空间`mm_struct`、挂载点`fs_struct`、打开文件列表`files_struct` 都是独立拥有的，都申请了单独的内存

![create_process_overview](/images/create_process_overview.png)

**创建线程**：仍由`task_struct`管理，但其地址空间`mm_struct`、目录信息`fs_struct`、打开文件列表`files_struct`都是和创建它的父进程/线程共享的。即从内核的角度看，用户态的线程本质上还是一个进程。

![create_thread_overview](/images/create_thread_overview.png)

## 4. 内核的内存管理

上面简要跟踪梳理了创建进程/线程的流程，其中包含的 `mm_struct` 虚拟内存地址空间结构，本小节进行说明。

### 4.1. 拷贝虚拟内存空间

每个进程都有唯一的`mm_struct`结构体，也就是前边提到的每个进程的虚拟地址空间都是**独立，互不干扰**的。线程则是和其父进程共享虚拟地址空间。

展开跟踪一下上面的`copy_mm`：

```cpp
// linux-5.10.10/kernel/fork.c
static int copy_mm(unsigned long clone_flags, struct task_struct *tsk)
{
    // 子进程虚拟内存空间，父进程虚拟内存空间
    struct mm_struct *mm, *oldmm;
    int retval;
    ...
    tsk->mm = NULL;
    tsk->active_mm = NULL;
    // 获取父进程虚拟内存空间
    oldmm = current->mm;
    if (!oldmm)
        return 0;
    ...
    // 通过 vfork 或者 clone 系统调用创建出的子进程（线程）和父进程共享虚拟内存空间
    if (clone_flags & CLONE_VM) {
        // 增加父进程虚拟地址空间的引用计数
        mmget(oldmm);
        // 直接将父进程的虚拟内存空间赋值给子进程（线程）
        // 线程共享其所属进程的虚拟内存空间
        mm = oldmm;
        goto good_mm;
    }

    retval = -ENOMEM;
    // 如果是 fork 系统调用创建出的子进程，则将父进程的虚拟内存空间以及相关页表拷贝到子进程中的 mm_struct 结构中。
    mm = dup_mm(tsk, current->mm);
    ...
good_mm:
    // 将拷贝出来的父进程虚拟内存空间 mm_struct 赋值给子进程
    tsk->mm = mm;
    tsk->active_mm = mm;
    ...
}
```

### 4.2. 虚拟内存空间的结构

展开 `mm_struct`，内容也比较多，截取空间结构相关的部分，其中分别定义了虚拟内存各段的区间大小。

内核通过该核心结构将虚拟内存各区域组织起来，见下面注释：

```cpp
// linux-5.10.10/include/linux/mm_types.h
struct mm_struct {
    struct {
        // vm_area_struct 用于表示每个 虚拟内存区域（VMA），通过该结构将这些区域组织起来
        struct vm_area_struct *mmap;    /* list of VMAs */
        struct rb_root mm_rb;
        ...
        unsigned long mmap_base;  /* base of mmap area */
        ...
        unsigned long task_size;    /* size of task vm space */
        ...
        // total_vm 表示在进程虚拟内存空间中总共与物理内存映射的页 的总数
        unsigned long total_vm;    /* Total pages mapped */
        // locked_vm 表示不能换出到硬盘的页总数（当内存吃紧的时候，有些页可以换出到硬盘上，而有些页因为比较重要，不能换出）
        unsigned long locked_vm;  /* Pages that have PG_mlocked set */
        // pinned_vm 表示既不能换出，也不能移动的内存页总数
        unsigned long pinned_vm;  /* Refcount permanently increased */
        // data_vm 表示数据段中映射的内存页数目
        unsigned long data_vm;    /* VM_WRITE & ~VM_SHARED & ~VM_STACK */
        // exec_vm 是代码段中存放可执行文件的内存页数目
        unsigned long exec_vm;    /* VM_EXEC & ~VM_WRITE & ~VM_STACK */
        // stack_vm 是栈中所映射的内存页数目
        unsigned long stack_vm;    /* VM_STACK */
        unsigned long def_flags;

        spinlock_t arg_lock; /* protect the below fields */
        // start_code 和 end_code 定义代码段的起始和结束位置，程序编译后的二进制文件中的机器码被加载进内存之后就存放在这里
        // start_data 和 end_data 定义数据段的起始和结束位置，初始化的全局变量和静态变量被加载进内存中就存放在这里
        unsigned long start_code, end_code, start_data, end_data;
        // start_brk 定义堆的起始位置，brk 定义堆当前的结束位置
        // start_stack 是栈的起始位置在 RBP 寄存器中存储
        // end_data 和 start_brk 之间是 BSS段，所以不用单独定义BSS段相关边界字段
        unsigned long start_brk, brk, start_stack;
        // arg_start 和 arg_end 是参数列表的位置
        // env_start 和 env_end 是环境变量的位置
        unsigned long arg_start, arg_end, env_start, env_end;
        ...
    } __randomize_layout;
    unsigned long cpu_bitmap[];
}
```

结构和内存空间结构各段的示意图如下：

![mm_struct_overview](/images/mm_struct_overview.png)

### 4.3. 虚拟内存区域VMA

展开 `vm_area_struct`，内容不长，下面是全部内容：

```cpp
// linux-5.10.10/include/linux/mm_types.h
// 该结构是一个双向链表，将虚拟内存空间中的这些虚拟内存区域 VMA 串联起来
struct vm_area_struct {
    /* The first cache line has the info for VMA tree walking. */
    // 本VMA区域的起始和结束地址
    unsigned long vm_start;     /* Our start address within vm_mm. */
    unsigned long vm_end;       /* The first byte after our end address within vm_mm. */

    // vm_next，vm_prev 指针分别指向 VMA 节点所在双向链表中的后继节点和前驱节点
    struct vm_area_struct *vm_next, *vm_prev;

    // 每个 VMA 区域都是红黑树中的一个节点，通过 vm_rb 将自己连接到红黑树中
    struct rb_node vm_rb;

    unsigned long rb_subtree_gap;

    /* Second cache line starts here. */
    // 双向链表的头指针存储在内存描述符 struct mm_struct 结构中的 mmap 中
    // 正是这个 mmap 串联起了整个虚拟内存空间中的虚拟内存区域（对应进程结构体task_struct中的mm_struct）
    struct mm_struct *vm_mm;	/* The address space we belong to. */

    pgprot_t vm_page_prot;
    unsigned long vm_flags;

    struct {
        struct rb_node rb;
        unsigned long rb_subtree_last;
    } shared;

    struct list_head anon_vma_chain;
    struct anon_vma *anon_vma;
    const struct vm_operations_struct *vm_ops;
    unsigned long vm_pgoff;
    struct file * vm_file;
    void * vm_private_data;

#ifdef CONFIG_SWAP
    atomic_long_t swap_readahead_info;
#endif
#ifndef CONFIG_MMU
    struct vm_region *vm_region;	/* NOMMU mapping region */
#endif
#ifdef CONFIG_NUMA
    struct mempolicy *vm_policy;	/* NUMA policy for the VMA */
#endif
    struct vm_userfaultfd_ctx vm_userfaultfd_ctx;
} __randomize_layout;
```

`vm_area_struct`和`mm_struct`结构组织示意图，具体描述见参考链接：

![mm_struct_vma_overview](/images/mm_struct_vma_overview.png)

### 4.4. 二进制文件如何映射到虚拟内存空间

> 内核中完成这个映射过程的函数是 `load_elf_binary` ，这个函数的作用很大，加载内核的是它，启动第一个用户态进程 init 的是它，fork 完了以后，调用 exec 运行一个二进制程序的也是它。当 exec 运行一个二进制程序的时候，除了解析 ELF 的格式之外，另外一个重要的事情就是建立上述提到的内存映射。

暂做标记，后续再深入梳理。

```cpp
// linux-5.10.10/fs/binfmt_elf.c
static int load_elf_binary(struct linux_binprm *bprm)
{
    ...
}
```

## 5. 小结

梳理进程管理以及内存管理相关流程。

## 6. 参考

* [一步一图带你深入理解 Linux 虚拟内存管理](https://mp.weixin.qq.com/s/uWadcBxEgctnrgyu32T8sQ)
* [一步一图带你深入理解 Linux 物理内存管理](https://mp.weixin.qq.com/s/Cn-oX0W5DrI2PivaWLDpPw)
* [Linux进程是如何创建出来的？](https://mp.weixin.qq.com/s/ftrSkVvOr6s5t0h4oq4I2w)
* [进程和线程之间有什么根本性的区别？](https://mp.weixin.qq.com/s/--S94B3RswMdBKBh6uxt0w)
* linux-5.10.10、glibc 源码
