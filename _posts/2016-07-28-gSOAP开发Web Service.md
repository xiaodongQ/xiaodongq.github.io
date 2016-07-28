---
layout: post
title: Linux下使用gSOAP进行Web Service开发
categories: C
tags: C Web
---

* content
{:toc}

## 介绍

gSOAP是一个跨平台的，用于开发Web Service服务端和客户端的工具，在Windows、Linux、MAC OS和UNIX下使用C和C++语言编码，集合了SSL功能。

gSOAP编译工具提供了一个SOAP/XML关于C/C++的实现，从而让C/C++开发web服务或客户端程序的工作变得方便许多。

gSOAP包括两个工具：wsdl2h和soapcpp2。

  * wsdl2h解析器：用于将WSDL(Web Services Description Language)文件或文件URL生成C/C++头文件

  * soapcpp2预编译器：基于头文件(.h)生成一系列文件(包含服务端、客户端接口，SOAP调用的封装等)



手动安装时：

```
./configure --prefix=XXX(无root权限可用prefix指定安装路径)

make

make install
```

了解WSDL和SOAP，有助于对gSOAP理解得更清楚一点，见下文：

**[使用 WSDL 部署 Web 服务: 第 1 部分](https://www.ibm.com/developerworks/cn/webservices/ws-intwsdl/part1/)**

WSDL中的类型可能在XSD文件中定义。

>WSDL (web Services Description Language)描述你的服务及其操作-服务调用的，这些方法具有参数和返回值
>
>它是一个服务的的行为的说明- - 功能。
>
>XSD ( xml Schema Definition ) 介绍这些服务方法的交换的静态结构的复杂数据类型。 它描述了类型.它们的字段.任何对这些字段的限制(如最大长度或者正规表达式模式)等等。
>
>可以是数据类型的说明和扩展名的静态属性的服务- 是关于数据。

学习和上手很好的一个方法是查看gSOAP安装包中的例子，网上很多介绍的博客都介绍的是samples里的calc的例子，比较同质化，有些介绍得有些突兀。还是自己跟着例子执行一遍，再跟着写一遍，理解起来印象效果更好一点。例子中的README中已经写清楚了步骤，对于英文这个问题程序员还是该好好对待吧。

## wsdl2h简要说明

* wsdl2h的用法（WSDL/schema 解析和代码生成器）

  `sdl2h [opt] 头文件名 WSDL文件名或URL`

  wsdl2h常用选项

  * -o 文件名，指定输出头文件
  * -n 名空间前缀 代替默认的ns
  * -c 产生纯C代码，否则是C++代码
  * -s 不要使用STL代码
  * -e 禁止为enum成员加上名空间前缀

例如：`wsdl2h -s -o calc.h XXX.wsdl`

(参数s就表示生成不带STL的C/C++语法结构的头文件calc.h。
如果不用s就会生成带STL的头文件，这样，在后边的编译中需要加入STL的头。
stlvector.h，位于：gsoap/import/目录下)

## soapcpp2选项简要说明

* soapcpp2的用法（编译和代码生成器）

  `soapcpp2 [opt] 头文件名``

  soapcpp2常用选项

  * -c 产生纯C代码，否则是C++代码(与头文件有关)
  * -i 生成C++封装(代理)，客户端为xxxxProxy.h(.cpp)，服务器端为xxxxService.h(.cpp)。
  * -C 仅生成客户端代码
  * -S 仅生成服务器端代码
  * -L 不要产生soapClientLib.c和soapServerLib.c文件
  * -I 指定import路径
  * -x 不要产生XML示例文件

## 注意

  * 生成文件有点多，一开始可能有点迷糊。

    简要说下samples中的calc例子：

    * 编写calc.h
    * soapcpp2生成调用框架(会生成一系列文件)
    * 编写服务端程序，使用soapService服务端类，并在文件中实现add等运算功能，测试时可启动一个服务，需指定端口(e.g. 7000)进行绑定
    * 编写客户端程序，使用soapProxy代理类，定义一个实例指定一下地址(endpoint中指定,e.g. http://localhost:7000)直接使用即可

    **分别编译服务器端和客户端时，有多个一起编译的文件**

    **具体查看安装包中的例子和README，比较清晰**

  * 把gsoap目录下的stdsoap2.h和stdsoap2.cpp拷到项目目录，编译需要(无则会报错提示)
