---
layout: post
title: C和C++的历史版本迭代整理
categories: C/C++
tags: C/C++版本
---

* content
{:toc}

介绍C和C++的历史版本迭代。部分常用特性说明。



## C++各版本

C++版本之前也讲到过：[C++中的RAII机制和互斥锁应用](https://xiaodongq.github.io/2019/10/16/C++%E4%B8%AD%E7%9A%84RAII%E6%9C%BA%E5%88%B6%E5%92%8C%E4%BA%92%E6%96%A5%E9%94%81%E5%BA%94%E7%94%A8/)

百度百科：[c++0x](https://baike.baidu.com/item/c%2B%2B0x)

* 1998年是C++标准委员会成立的第一年，以后每5年视实际需要更新一次标准。
* 2009年，C++标准有了一次更新，一般称该草案为C++0x。
* C++0x是C++11标准成为正式标准之前的草案临时名字。
* 后来，2011年，C++新标准标准正式通过，更名为ISO/IEC 14882:2011，简称C++11。

维基百科：[C++11](https://zh.wikipedia.org/wiki/C%2B%2B11#cite_note-1)

* C++11，先前被称作C++0x，即ISO/IEC 14882:2011，是C++编程语言的一个标准。
    - 它取代第二版标准ISO/IEC 14882:2003
    （第一版ISO/IEC 14882:1998公开于1998年，
      第二版于2003年更新，分别通称C++98以及C++03，两者差异很小），且已被C++14取代
* C++14 旨在作为C++11的一个小扩展，主要提供漏洞修复和小的改进。
    - 2014年8月18日，经过C++标准委员投票，C++14标准获得一致通过。ISO/IEC 14882:2014
* C++17 又称C++1z，是继 C++14 之后，C++ 编程语言 ISO/IEC 标准的下一次修订的非正式名称。
    - 官方名称 ISO/IEC 14882:2017
    - 基于 C++ 11，C++ 17 旨在简化该语言的日常使用，使开发者可以更简单地编写和维护代码。
    - C++ 17是对 C++ 语言的重大更新
    - [C++ 17 标准正式发布](https://blog.csdn.net/csdnnews/article/details/78737012)

相比于C++03，C++11标准包含核心语言的新机能，而且扩展C++标准程序库，并入了大部分的C++ Technical Report 1程序库（数学的特殊函数除外）。

关于C++11的版本发布过程...：

>上一个版本的C++国际标准是2003年发布的，所以叫C++ 03。然后C++国际标准委员会在研究C++ 03的下一个版本的时候，一开始计划是07年发布，所以最初这个标准叫C++ 07。但是到06年的时候，官方觉得07年肯定完不成C++ 07，而且官方觉得08年可能也完不成。最后干脆叫C++ 0x。x的意思是不知道到底能在07还是08还是09年完成。结果2010年的时候也没完成，最后在2011年终于完成了C++标准。所以最终定名为C++11。  参考：[c++ 0x和c++ 11是什么关系？0x又是什么意思？](https://www.zhihu.com/question/20141092/answer/21463744)

### C++11新特性

参考：

[C++11 新特性](https://www.jianshu.com/p/3ac281aa457f)

#### 关键字及新语法

* auto 关键字及用法
    - C++11 之前，auto 具有存储期说明符的语义。auto在C++98中的标识临时变量的语义，由于使用极少且多余，在C++11中已被删除。前后两个标准的auto，完全是两个概念。
* nullptr 关键字及用法
    - 引入nullptr，是因为重载函数处理 NULL 的时候会出问题，二义性

```cpp
    void foo(int);   //(1)
    void foo(void*); //(2)

    foo(NULL);    // 重载决议选择 (1)，但调用者希望是 (2)
    foo(nullptr); // 调用(2)
```

* for 循环语法
    - for ( 范围声明 : 范围表达式 ) 循环语句

#### STL 容器

* std::array
    - std::array 提供了静态数组，编译时确定大小、更轻量、更效率，当然也比 std::vector 有更多局限性。
* std::forward_list
    - 单向链表
* std::unordered_map
* std::unordered_set

#### 多线程

* std::thread
    - 在 C++11 以前，C++ 的多线程编程均需依赖系统或第三方接口实现
    - 一定程度上影响了代码的移植性。
    - C++11 中，引入了 boost 库中多线程的部分内容，形成标准后的接口与 boost 库基本没有变化，这样方便了使用者切换使用 C++ 标准接口。
* std::atomic
    - 从实现上，可以理解为这些原子类型内部自己加了锁。
* std::condition_variable

#### 智能指针内存管理

* std::shared_ptr
* std::weak_ptr

#### 其他

* std::function、std::bind 封装可执行对象
* lambda 表达式
    - lambda 表达式用于定义并创建匿名的函数对象，以简化编程工作。

### C++11 编译器支持：

参考的知乎问答：

[C++11编译器的支持](https://zhuanlan.zhihu.com/p/27010179)

* 编译器对C++0x和C++11的支持
* GCC编译器对C++11的特性支持
    - codecvt用于编码转换，在GCC 5时引入，在GCC 7（C++17）时废弃。
    - GCC 4.9时正则表达式
    - GCC 4.8时引入了类成员变量函数返回值的左值、右值引用
    - GCC 4.7时正式启用-std=c++11，之前都是使用-std=c++0x
    - GCC 4.6时引入了range based for，即for each。
    - GCC 4.5时引入了lambda表达式，大大方便了函数式编程。
    - stoi/stod和to_string系列函数其实很早就引入了GCC（< 4.5）

参考zh.cppreference.com整理的对于各个标准特性的支持情况(包含C++11,C++14,17等等)：

[C++ 编译器支持情况表](https://zh.cppreference.com/w/cpp/compiler_support#cpp11)

选取GCC中个人目前注意的几个：

* auto, 4.4
    - C++0x/C++11 为 auto 关键字定义了完全不同的语义,4.5开始支持 参考：[GCC 4.5 中的 C++0x 特性支持](https://www.ibm.com/developerworks/cn/aix/library/au-gcc/index.html)
* nullptr, 4.6
* 范围 for 循环, 4.6
    - for ( 范围声明 : 范围表达式 ) 循环语句
* noexcept, 4.6
    - 指定函数是否抛出异常。 `void f() noexcept; // 函数 f() 不抛出`
* override 与 final, 4.7
    - override 指定一个虚函数覆盖另一个虚函数。 [override 说明符](https://zh.cppreference.com/w/cpp/language/override)
    - final 指定某个虚函数不能在子类中被覆盖，或者某个类不能被子类继承。 [final 说明符](https://zh.cppreference.com/w/cpp/language/final)
* decltype 4.8.1
    - 检查实体的声明类型，或表达式的类型和值类别。

## C各版本

参考：

维基百科：[C语言](https://zh.wikipedia.org/wiki/C%E8%AF%AD%E8%A8%80#C99)

* C语言早期
    - 最早由丹尼斯·里奇（Dennis Ritchie）为了在PDP-11电脑上运行的Unix系统所设计出来的编程语言
    - 第一次发展在1969年到1973年之间。
    - 在PDP-11出现后，丹尼斯·里奇与肯·汤普逊着手将Unix移植到PDP-11上
    - 1973年，Unix操作系统的核心正式用C语言改写，这是C语言第一次应用在操作系统的核心编写上。
    - 1975年C语言开始移植到其他机器上使用。史蒂芬·强生实现了一套“可移植编译器”
* K&R C
    - 1978年，丹尼斯·里奇和布莱恩·柯林汉合作出版了《C程序设计语言》的第一版。 “K&R C”（柯里C）。
* C89
    - 1989年，C语言被美国国家标准协会（ANSI）标准化，这个版本又称为C89
    - 标准化的一个目的是扩展K&R C，增加了一些新特性。
* C90
    - 1990年，国际标准化组织（ISO）规定国际标准的C语言
    - 通过对ANSI标准的少量修改，最终制定了 ISO 9899:1990，又称为C90。
    - 随后，ANSI亦接受国际标准C，并不再发展新的C标准。
* C99
    - 1994年为C语言创建了一个新标准，但是只修正了一些C89标准中的细节和增加更多更广的国际字符集支持。
    - 不过，这个标准引出了1999年ISO 9899:1999的发表。它通常被称为C99。
    - C99被ANSI于2000年3月采用。
* C11
    - 2011年12月8日，ISO正式发布了新的C语言的新标准C11，之前被称为C1X
    - 官方名称为ISO/IEC 9899:2011
    - 新的标准提高了对C++的兼容性，并增加了一些新的特性。
    - 这些新特性包括泛型宏、多线程、带边界检查的函数、匿名结构等。
* C18
    - C18没有引入新的语言特性，只对C11进行了补充和修正。


K&R C语言到ANSI/ISO标准C语言 (C89/C90)的改进包括：

* 增加了真正的标准库
* 新的预处理命令与特性
* 函数原型允许在函数申明中指定参数类型
* 一些新的关键字，包括 const、volatile 与 signed
* 宽字符、宽字符串与多字节字符
* 对约定规则、声明和类型检查的许多小改动与澄清

### C99部分新特性

(只截取了部分本人关注的)：

* 支持不定长的数组，声明时使用 int a[var] 的形式。
* 变量声明不必放在语句块的开头，for 语句提倡写成 for(int i=0;i<100;++i) 的形式
* 允许采用（type_name）{xx,xx,xx} 类似于 C++ 的构造函数的形式构造匿名的结构体。
* 除了已有的 `__line__` `__file__` 以外，增加了 `__func__` 得到当前的函数名。
* 取消了函数返回类型默认为 int 的规定。
* 增加和修改了一些标准头文件(定义bool的<stdbool.h>、定义复数的<complex.h>、<time.h>里增加了 struct tmx，对 struct tm 做了扩展。)

> 但是各个公司对C99的支持所表现出来的兴趣不同。当GCC和其它一些商业编译器支持C99的大部分特性的时候[4]，微软和Borland却似乎对此不感兴趣。

### C11

参考：

维基百科：[C11](https://zh.wikipedia.org/wiki/C11)

* C11：
    - C11（也被称为C1X）指ISO标准ISO/IEC 9899:2011，是当前最新的C语言标准。
    - 在它之前的C语言标准为C99 (1999年ISO 9899:1999)，C99被ANSI于2000年3月采用。
    - 这次修订新增了被主流C语言编译器(如GCC,Clang,Visual C++等)增加的内容
    - 引入了内存模型以更好的执行多线程
    - 之前C99的一些被推迟的计划在C11中增加了，但是对C99仍保留向后兼容。

* 编译器支持
    - GCC从4.6版本开始，已经可以支持一些C11的特性，但多线程相关的库直到2019年还未出现稳定的实现，等于没有编译器可以完整的支持C11
    - GCC 4.6 版本使用参数-std=c1x ，4.7版本以后使用参数-std=c11
    - Clang则是自3.1版开始支持，并在LLVM 3.6版之后默认使用C11的语法
    - 但另一个主流编译器，微软的 Visual Studio 则是自 C99 开始就没有支持新的C语言版本了。

> 虽然 gcc 与 clang 支持C11的语法，却没有实现strcat_s()等边界检查函数以及线程相关<threads.h>库。gcc的支持者狂热的四处宣称这些库是GNU C库的责任而不是gcc的责任——尽管gcc和GNU C库都是GNU项目的子项目。