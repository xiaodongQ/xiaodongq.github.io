---
title: 构建工程化的makefile
categories: C/C++
tags: [makefile, C/C++]
---

构建一个Linux下通用的C/C++工程Makefile

## 缘由

启动一个新的C/C++项目时，编译方式目前自己一般都是用Makefile(Cmake跨平台特性比较好，一直说要用一下，拖到现在orz)。

参与既有项目的维护开发，一般工程化的编译脚本/Makefile/Cmake都已经由前人写好了。

对于我，只会去大概看一下知道各行含义，要是让自己手写还是会觉得比较麻烦，各种文件路径、包含关系、排除目录、宏开关等，写着写着就会冒出一个觉得必要的东西，然后就是各种搜索。 看到某个用法后对于扩展的用法又觉得有必要了解一下，到后面就成了广度+深度遍历...

最近起的一个C++项目就是如此，其实各种用法在之前维护其他模块的时候就已经这样走过一遍了。不过笔记没有留下来。所以这次是整理温习的同时，也是做一个归档，便于后续温故知新和复用。

最近开始也在归档一些与工作项目业务不关联、通用的笔记记录，还是比较有必要的，这是缘起。


## 投入使用的makefile文件

直接上文件就行了，一些语法用法不了解单独再查。

(若有多个需要单独编译的子目录makfile，一些通用的配置也可以单独抽取成配置文件，然后各个makefile去加载一下)

```sh
CXX = g++

# 项目路径, makefile文件放在项目路径最外层
PRJ_DIR=.
# $(warning)用于打印信息
$(warning PRJ_DIR: [$(PRJ_DIR)])

#################### 源码路径 ####################
# 跳过不进行编译的源码路径, 新增路径均-o -path形式，不需要跳过可以注释掉
# 跳过src/xdtemp目录编译
PRUNE_SRC_DIR_FLAGS = \( -path $(PRJ_DIR)/src/xdtemp
PRUNE_SRC_DIR_FLAGS += \) -prune -o
SRC_DIR = $(shell find $(PRJ_DIR)/src $(PRUNE_SRC_DIR_FLAGS) -type d -print)
$(warning SRC_DIR: [$(SRC_DIR)])
#################### 所有源文件 ####################
# 遍历获取所有cpp文件
SRC_CPP_FILES = $(foreach dir,$(SRC_DIR),$(wildcard $(dir)/*.cpp))
# 遍历获取所有cc文件
SRC_CC_FILES = $(foreach dir,$(SRC_DIR),$(wildcard $(dir)/*.cc))

# 所有源文件对于的.o目标文件, 将所有.cpp和.cc替换为.o
SRC_OBJS = $(patsubst %.cpp, %.o, $(SRC_CPP_FILES))
SRC_OBJS += $(patsubst %.cc, %.o, $(SRC_CC_FILES))
$(warning SRC_OBJS: [$(SRC_OBJS)])

#################### 头文件包含路径 ####################
#################### 头文件标志 每个路径加前缀-I ####################
# 跳过不进行编译的头文件路径, 新增路径均-o -path形式(+= -o -path dir111)
PRUNE_INC_DIR_FLAGS = \( -path $(PRJ_DIR)/include/xdtemp
PRUNE_INC_DIR_FLAGS += -o -path $(PRJ_DIR)/src/xdtemp2
PRUNE_INC_DIR_FLAGS += \) -prune -o
INC_DIR = $(shell find $(PRJ_DIR)/include $(PRUNE_INC_DIR_FLAGS) -type d -print)
INC_DIR += $(shell find $(PRJ_DIR)/src $(PRUNE_INC_DIR_FLAGS) -type d -print)
$(warning INC_DIR: [$(INC_DIR)])
INC_FLAGS = $(foreach dir,$(INC_DIR),$(addprefix -I, $(dir)))
$(warning INC_FLAGS: [$(INC_FLAGS)])

#################### 宏定义 ####################
# 某些库编译需要定义宏
DEF_FLAGS = -DXDTEMP_LIB

# 选项根据具体项目调整 此处开启了-g
CPPFLAGS = -g -Wall -std=c++11
CPPFLAGS += $(INC_FLAGS)
CPPFLAGS += $(DEF_FLAGS)

TARGET_PROG = xdTempServer

# 需要链接的一些库，pkg-config会自动获取库对应的选项。注意链接库顺序，越基础的库放在越后面，依赖某个库会向后查找
LDFLAGS += `pkg-config --cflags protobuf grpc` -ldl -lpthread


.PHONY: all clean
all:$(TARGET_PROG)

# $@通配符代表目标文件，$^代表所有依赖文件
$(TARGET_PROG):$(SRC_OBJS)
    $(CXX) -o $@ $^ $(CPPFLAGS) $(LDFLAGS)
    mv $(TARGET_PROG) $(PRJ_DIR)/bin/ -f

#编译规则 $@代表目标文件 $< 代表第一个依赖文件
%.o:%.cpp
    $(CXX) -o $@ -c $< $(CPPFLAGS) $(LDFLAGS)

%.o:%.cc
    $(CXX) -o $@ -c $< $(CPPFLAGS) $(LDFLAGS)

clean:
    rm -f $(PRJ_DIR)/bin/$(TARGET_PROG) $(SRC_OBJS)
```

## 编译时找不到库 和 运行时找不到库

报错情形：

碰到**编译时**-l明明链接了库，但是找不到，或者报链接失败，这时大概率检查两个可能：

    1. 链接顺序不对而找不到依赖关系，底层库放在前面链接，应用程序的库放在后面：调整库之间的顺序 或者 调整源文件和库之间的顺序试一下
      原来编译.o文件：$(CXX) $(CPPFLAGS) $(LDFLAGS) -o $@ -c $<，现调整为 $(CXX) -o $@ -c $< $(CPPFLAGS) $(LDFLAGS) (前者正好遇到了引用库中函数的源码放在-l库之后的坑)

    2. 链接库查找路径未包含，可用 -L指定链接路径
        a. 如果是不想每次指定路径，可以在.bashrc中把路径加入到环境变量LIBRARY_PATH

        b. 用pkg-config自动获取编译选项的情况，可能是.pc文件路径并没有加到pkg-config查找的路径，设置下PKG_CONFIG_PATH变量

* -l 顺序问题的历史原因，早期gcc链接器为了节约内存，只扫描一遍要链接的库。可参考下面的链接
  - [GCC链接库的一个"坑"：动态库存在却提示未定义动态库的函数](https://www.cnblogs.com/gmpy/p/11089572.html)
  - [Why does the order of '-l' option in gcc matter?](https://stackoverflow.com/questions/11893996/why-does-the-order-of-l-option-in-gcc-matter)

**运行**项目找不到动态库，可能是系统中查找动态库的目录范围没有该库路径，

    1. 添加ldconfig遍历路径

        假如是/usr/local/lib路径下的库找不到，则：

          vi /etc/ld.so.conf，添加一行 /usr/local/lib，然后执行ldconfig

    2. 或应用程序启动前，将库路径加到LD_LIBRARY_PATH

        export LD_LIBRARY_PATH=/usr/local/lib:$(LD_LIBRARY_PATH)

### pkg-config

[pkg-config 详解](https://blog.csdn.net/newchenxf/article/details/51750239)

pkg-config是一个linux下的命令，用于获得某一个库/模块的所有编译相关的信息。

```sh
pkg-config --cflags --libs libmongocxx 执行结果为：

-I/usr/local/include/mongocxx/v_noabi -I/usr/local/include/bsoncxx/v_noabi  -L/usr/local/lib -lmongocxx -lbsoncxx
```

一般开源项目中都会配置好pkg-config文件，便于使用者直接使用，而不用去管各种链接库的依赖关系。

> 如果你写了一个库，不管是静态的还是动态的，要提供给第三方使用，那除了给人家库/头文件，最好也写一个pc文件，这样别人使用就方便很多，不用自己再手动写依赖了你哪些库，只需要敲一个”pkg-config [YOUR_LIB] --libs --cflags”。

pkg-config信息两个来源

  第一种：取系统的/usr/lib下的所有*.pc文件。

  第二种：PKG_CONFIG_PATH环境变量所指向的路径下的所有*.pc文件。

编译项目pkg-config找不到库，则要检查pkg-config去查找的目录中是否包含你安装的库所在的路径，可用find查找库的路径，一般在同路径下会有这个库的pkg-config定义文件(.pc后缀)

    假如要链接的库 在/usr/local/lib/下，且其.pc文件是否放在 /usr/local/lib/pkgconfig路径

      .bashrc中，export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH，然后. ~/.bashrc重新加载下

### ldconfig

ldconfig 运行时找库

运行项目找不到动态库，系统中添加路径，或LD_LIBRARY_PATH

  vi /etc/ld.so.conf，添加一行 /usr/local/lib，然后执行ldconfig


## makefile中涉及的一些文件和字符串处理函数说明

**注意！ `PRJ_DIR="${shell cd ..;pwd}"       #注释说明`, 这样注释处理会将空格也赋值给PRJ_DIR**

注释尽量单独写一行，要不空格问题容易搞乌龙

参考：
[Makefile编译目录下多个文件以及函数wildcard用法](https://blog.csdn.net/hunanchenxingyu/article/details/12205305)

[makefile 中字符串处理和文件处理函数](https://blog.csdn.net/qhexin/article/details/16951097)

```sh
1. wildcard
  找出目录和指定目录下所有的后缀为c和cpp的文件
  $(wildcard *.c, *.cpp, /***/***/*.c)
    C_SRC = $(wildcard *.c)
    同C_SRC=$(shell echo *.c)

2. foreach
  组合foreach查找多个路径
    SRC_FILES += $(foreach dir,$(SRC_DIR),$(wildcard $(dir)/*.cpp))

3. patsubst 模式字符串替换函数
  $(patsubst <pattern>,<replacement>,<text>)
    <pattern>可以包括通配符“%”，表示任意长度的字串
    如果<replacement>中也包含“%”，那么，<replacement>中的这个“%”将是<pattern>中的那个“%
    以“\%”来表示真实含义的"%"
  e.g.
      将所有的cpp文件的后缀替换为o文件
      CPP_OBJ = $(patsubst %cpp, %o, $(CPP_SRC))
        同CPP_OBJ=$(CPP_SRC:%.cpp=%.o)

4. notdir
  dir=$(notdir $(src)) 把带路径的文件去掉路径，只留文件名

5. subst 字符串替换函数
  $(subst <from>,<to>,<text>)
  e.g.
    $(subst ee,EE,feet on the street)， 将"feet on the street"中的"ee"替换为"EE"，若要替换为空则,,

  其他字符串处理：
    去空格函数——strip
    e.g.
      $(strip a b c ) 把字串“a b c ”去到开头和结尾的空格，结果是“a b c”。

    过滤函数——filter
      sources := foo.c bar.c baz.s ugh.h
      $(filter %.c %.s,$(sources))返回的值是“foo.c bar.c baz.s”。
    反过滤函数——filter-out
      objects=main1.o foo.o main2.o bar.o
      mains=main1.o main2.o
      $(filter-out $(mains),$(objects)) 返回值是“foo.o bar.o”
    排序函数——sort
      $(sort foo bar lose)返回“bar foo lose”
    取单词函数——word
      取第n个，从1开始数
      $(word 2, foo bar baz)返回值是“bar”
    取单词串函数——wordlist
      第几到第几个
      $(wordlist 2, 3, foo bar baz)返回值是“bar baz”
    单词个数统计函数——words
      $(words, foo bar baz)返回值是“3”
    首单词函数——firstword
      $(firstword foo bar)返回值是“foo”
  文件名操作函数：
    取目录函数——dir
      目录部分是指最后一个反斜杠（“/”）之前的部分。如果没有反斜杠，那么返回“./”
      $(dir src/foo.c hacks)返回值是“src/ ./”
    取文件函数——notdir
      非目录部分是指最后一个反斜杠（“/”）之后的部分
      $(notdir src/foo.c hacks)返回值是“foo.c hacks”
    取后缀函数——suffix
      如果文件没有后缀，则返回空字串
      $(suffix src/foo.c src-1.0/bar.c hacks)返回值是“.c .c
    取前缀函数——basename
      如果文件没有前缀，则返回空字串
      $(basename src/foo.c src-1.0/bar.c hacks)返回值是“src/foo src-1.0/bar hacks”
    加后缀函数——addsuffix
      $(addsuffix .c,foo bar)返回值是“foo.c bar.c”
    加前缀函数——addprefix
      $(addprefix src/,foo bar)返回值是“src/foo src/bar”
    连接函数——join
      $(join <list1>,<list2>)
      如果<list1>的单词个数要比<list2>的多，那么，<list1>中的多出来的单词将保持原样。如果<list2>的单词个数要比<list1>多，那么，<list2>多出来的单词将被复制到list1中末尾
      $(join aaa bbb , 111 222 333)返回值是“aaa111 bbb222 333”
```

```
通配符$@、$^、$<

这三个分别表示：
$@          --代表目标文件(target)
$^          --代表所有的依赖文件(components)
$<          --代表第一个依赖文件(components中最左边的那个)。
```

```sh
main.out:main.o line1.o line2.o
  g++ -o $@ $^
main.o:main.c line1.h line2.h
  g++ -c $<
line1.o:line1.c line1.h
  g++ -c $<
line2.o:line2.c line2.h
  g++ -c $<
```
