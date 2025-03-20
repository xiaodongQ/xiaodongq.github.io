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

在[CPU及内存调度（一） -- 进程、线程、系统调用、协程上下文切换](https://xiaodongq.github.io/2025/03/09/context-switch)中已经介绍过Linux通过页表机制进行内存映射管理，涉及TLB、MMU、缺页中断等，并发与异步编程系列梳理学习中，也涉及内存序和CPU缓存等问题，本篇开始梳理学习Linux内存管理，以及相关的进程、线程创建过程。

主要参考：

* [一步一图带你深入理解 Linux 虚拟内存管理](https://mp.weixin.qq.com/s/uWadcBxEgctnrgyu32T8sQ)
* [一步一图带你深入理解 Linux 物理内存管理](https://mp.weixin.qq.com/s/Cn-oX0W5DrI2PivaWLDpPw)
* 以及进程创建流程相关文章：
    * [Linux进程是如何创建出来的？](https://mp.weixin.qq.com/s/ftrSkVvOr6s5t0h4oq4I2w)
    * [进程和线程之间有什么根本性的区别？](https://mp.weixin.qq.com/s/--S94B3RswMdBKBh6uxt0w)

上述参考文章内容写得很好，由浅入深介绍内存结构、内存管理，并跟踪相关内核代码进行说明，其中用exclidraw画的配图也很直观。本篇博客中的配图，若无特别出处备注，均出自参考文章。

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
* 编译器确定：
    * **代码段**存储二进制文件中的机器码、**数据段**存储指定了初始值的 全局变量和静态变量、**BSS段**存储未指定初始值的全局变量和静态变量
* 运行器确定：
    * **堆**存储动态的申请内存
    * **文件映射与匿名映射区**，用于存储：
        * 1）程序运行依赖的动态链接库，这些动态链接库也有自己的对应的代码段，数据段，BSS 段，加载到内存需要的空间
        * 2）内存文件映射的系统调用`mmap`，映射的内存空间
    * **栈**，存储程序运行期间，函数调用过程中用到的局部变量和参数
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

详细说明可见参考链接。

## 3. 内核的进程空间管理

既然说进程的虚拟内存空间管理，那就离不开进程的创建。下面先看下内核中创建进程的简要流程，再跟进其中涉及的内存管理相关结构和机制。

### 3.1. 内核创建进程

结合 [Linux进程是如何创建出来的？](https://mp.weixin.qq.com/s/ftrSkVvOr6s5t0h4oq4I2w) 和 [进程和线程之间有什么根本性的区别？](https://mp.weixin.qq.com/s/--S94B3RswMdBKBh6uxt0w) 一起梳理。

进程/线程的核心结构：`task_struct`，定义在`include/linux/sched.h`，自己本地5.10.10的内核代码：linux-5.10.10/include/linux/sched.h。

`struct task_struct`中的内容特别多，算上注释和一些空格、条件编译，5.10.10版本里有`700`多行。

对比了一下参考链接（基于3.10.0内核）中的字段，在5.10.10中基本都一样，只是顺序略有不同，所以此处还是贴一下参考链接的结构体定义，便于和后续流程说明保持一致。

```cpp
// include/linux/sched.h
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
* **进程地址空间**：`struct mm_struct *mm, *active_mm;`，内存描述符，是**下述章节的重点**，暂时不做展开。
* fs_struct：进程文件系统信息
    * 描述进程的文件位置等信息
* files_struct：进程打开的文件信息
    * 每个进程用一个 files_struct 结构来记录文件描述符的使用情况， 这个 files_struct 结构称为用户打开文件表。
    * 其中核心结构：`struct file __rcu * fd_array[NR_OPEN_DEFAULT];`，在数组元素中记录了当前进程打开的每一个文件的指针。这个文件是 Linux 中抽象的文件，可能是真的磁盘上的文件，也可能是一个 socket。
    * 定义位于：`linux-5.10.10/include/linux/fdtable.h`

### 3.2. 内存管理结构

## 4. 小结


## 5. 参考

* [一步一图带你深入理解 Linux 虚拟内存管理](https://mp.weixin.qq.com/s/uWadcBxEgctnrgyu32T8sQ)
* [一步一图带你深入理解 Linux 物理内存管理](https://mp.weixin.qq.com/s/Cn-oX0W5DrI2PivaWLDpPw)
* [Linux进程是如何创建出来的？](https://mp.weixin.qq.com/s/ftrSkVvOr6s5t0h4oq4I2w)
* [进程和线程之间有什么根本性的区别？](https://mp.weixin.qq.com/s/--S94B3RswMdBKBh6uxt0w)
