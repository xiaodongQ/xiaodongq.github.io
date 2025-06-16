---
title: 编译基础知识笔记
description: 整理一些编译基础知识
categories: [编译原理]
tags: [编译原理, CSAPP]
---


## 1. 引言

编译相关原理一直没系统梳理过，不定期看过后面不怎么直接使用到就又忘了。近期梳理协程有涉及到编译和汇编相关内容，趁此机会稍微整理编译相关的一些知识和实践笔记，后续增量更新。

部分参考：

* [CSAPP 第七章笔记：链接过程](https://www.bluepuni.com/archives/csapp-chapter7/)

*说明：本博客作为个人学习实践笔记，可供参考但非系统教程，可能存在错误或遗漏，欢迎指正。若需系统学习，建议参考原链接。*

## 2. 程序编译过程

> 此处仅说明gcc对C/C++的编译。

gcc对C程序的编译过程：

* 预处理（`preprocessing`）
    * 包含头文件处理、宏定义展开、条件编译处理
    * 得到预处理后的代码（`.i`文件）
    * `gcc -E hello.c -o hello.i`
* 编译（`compilation`）
    * 将预处理后的代码转换为汇编代码（`.s`文件）
    * 这是整个编译器最核心的部分，包含：
        * 词法分析（Lexical Analysis） → 
        * 语法分析（Syntactic Analysis） → 
        * 语义分析（Semantic Analysis） → 
        * 中间代码生成（Intermediate Code Generation） → 
        * 优化（Optimization） → 
        * **目标代码生成（汇编）**（Code Generation）
    * `gcc -S hello.i -o hello.s`
* 汇编（`assembly`）
    * 将汇编代码翻译成机器可识别的**目标代码**（二进制），生成目标文件（`.o`文件）
        * 对应**目标代码生成（机器码）**，是**机器可识别**的机器码，而上一步编译中生成的目标代码是汇编语言的目标代码
    * `gcc -c hello.s -o hello.o`，或直接 `gcc -c hello.c -o hello.o`
* 链接（`linking`）
    * 将多个`.o`目标文件和库文件链接在一起，生成可执行文件
    * `gcc hello.o -o hello`，或直接 `gcc hello.c -o hello`

## 3. ELF布局

### 3.1. `readelf`查看程序启动位置

通过`readelf`来查看ELF文件对应的头信息，可从 `Entry point address` 中查看程序启动位置。

以 [2fiber](https://github.com/xiaodongQ/coroutine-lib/blob/main/fiber_lib/2fiber/) 中编译的可执行文件为例操作。

```sh
[root@xdlinux ➜ 2fiber git:(main) ✗ ]$ readelf -h test 
ELF Header:
  Magic:   7f 45 4c 46 02 01 01 03 00 00 00 00 00 00 00 00 
  Class:                             ELF64
  Data:                              2's complement, little endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - GNU
  ABI Version:                       0
  Type:                              EXEC (Executable file)
  Machine:                           Advanced Micro Devices X86-64
  Version:                           0x1
  Entry point address:               0x402230
  Start of program headers:          64 (bytes into file)
  Start of section headers:          84360 (bytes into file)
  Flags:                             0x0
  Size of this header:               64 (bytes)
  Size of program headers:           56 (bytes)
  Number of program headers:         14
  Size of section headers:           64 (bytes)
  Number of section headers:         35
  Section header string table index: 34
```

Linux的内存管理和空间分布，可见之前的梳理：[CPU及内存调度（二） -- Linux内存管理](https://xiaodongq.github.io/2025/03/20/memory-management/)。此处贴一下32位系统下进程的虚拟内存空间分布示意：

![virtual-memory-struct-32bit](/images/virtual-memory-struct-32bit.png)  
[出处](https://mp.weixin.qq.com/s/uWadcBxEgctnrgyu32T8sQ)

### 3.2. `objdump`反汇编

`objdump`对ELF文件进行**反汇编**：`objdump -d test > disassemble_d.txt`。

而后查看上述启动地址（`0x402230`）对应的信息，查找 `402230`，可看到调用到是`__libc_start_main`。

```sh
# vim disassemble_d.txt
Disassembly of section .text:
            
0000000000402230 <_start>:
  402230:   f3 0f 1e fa             endbr64 
  402234:   31 ed                   xor    %ebp,%ebp
  402236:   49 89 d1                mov    %rdx,%r9
  402239:   5e                      pop    %rsi
  40223a:   48 89 e2                mov    %rsp,%rdx
  40223d:   48 83 e4 f0             and    $0xfffffffffffffff0,%rsp
  402241:   50                      push   %rax
  402242:   54                      push   %rsp
  402243:   45 31 c0                xor    %r8d,%r8d
  402246:   31 c9                   xor    %ecx,%ecx
  402248:   48 c7 c7 d1 3e 40 00    mov    $0x403ed1,%rdi
  40224f:   ff 15 8b 9d 00 00       callq  *0x9d8b(%rip)        # 40bfe0 <__libc_start_main@GLIBC_2.34>
  402255:   f4                      hlt    
  402256:   66 2e 0f 1f 84 00 00    nopw   %cs:0x0(%rax,%rax,1)
  40225d:   00 00 00 
```

## 4. 全局符号

[协程梳理实践（四） -- sylar协程API hook封装](https://xiaodongq.github.io/2025/06/10/coroutine-api-hook/) 中，`动态库hook方式`小节描述了动态库的**全局符号**覆盖机制。

