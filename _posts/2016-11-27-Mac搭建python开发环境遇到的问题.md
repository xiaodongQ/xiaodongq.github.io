---
layout: post
title: Mac搭建python开发环境搭建及学习笔记
categories: Linux
tags: Linux Mac Python pip
---

* content
{:toc}

在慕课网上了解python的web框架django，搭建python环境时遇到些问题。

OS X系统自带了python运行环境，但作为开发不是很方便，tab键无补全提示；另外后续需要安装一些模块。所以安装一下ipython和pip。




## 工具安装

使用`easy_install pip`安装pip，但由于网络原因一直下载安装不成功，于是又安装了一个python 2.7.11，
`brew install python`，安装python会自带pip。

由于gfw的因素安装软件很慢，还需要改一下pip获取资源的路径，即pypi源，新建 ~/.pipe/pip.conf配置，
使用阿里云，如下

>[global]
>
>index-url = http://mirrors.aliyun.com/pypi/simple/
>
>[install]
>
>trusted-host=mirrors.aliyun.com

ipython就可以通过pip加包名安装了 `pip install ipython`

ipython 能够完成补齐操作(包括对象的属性等)，调试时比较方便

## django使用简介

### django简单测试

创建工程 `django-admin startproject mysite`

启动服务，进入mysite目录 `python manage.py runserver` 

	指定任意ip访问和端口 `manage.py runserver 0.0.0.0:8088`

### 目录结构：

1. manage.py (用来管理项目，几乎所有工作都通过该文件来做，数据库建立、服务运行、测试等)

	子命令：
		migrate 数据库
		shell 可调出ipython

2. mysite
		
	* settings.py 配置 应用、中间件、数据库、静态目录

	* urls.py   urlpatterns表，url映射配置：决定一个url被哪个程序访问

	* wsgi.py  django 轻量级调试服务器，Python应用程序或框架和web服务器之间接口

### 创建应用步骤

* 创建 `python manage.py startapp blog`

* 添加  在settings.py 中的INSTALLED_APPS中添加应用名

* 编辑展示的界面(添加函数) views.py(响应用户请求返回html页面)

* 映射 urls.py 用户在浏览器指定的url映射到函数(调用函数)

* 启动server，指定url e.g. http://127.0.0.1:8000/helloworld

* 其他文件

	models.py 定义数据库中的表

	admin.py  admin相关

	test.py   测试相关

### Django概述

1. url配置 简历url与响应函数间的关系
2. 视图 views 响应客户http请求，进行逻辑处理，返回给用户html页面
3. 模型 models 描述服务器存储的数据(数据库的表)
4. 模板 templates 用来生产html页面。返回给用户的html，是由数据(模型)和模板渲染出来的

## Requests库

### 环境搭建

安装 virtualenv  `pip install virtualenv`
`pip freeze` 可查看安装的工具或库
安装后执行，`virtualenv .env`生成虚拟机，`pip freeze`时无任何库。
激活进入虚拟机 `source .env/bin/activate`
安装requests，`pip install requests`

服务端使用httpbin.org，requests作者所写，美国服务器，访问较慢
使用gunicorn 搭建，爬包。先安装gunicorn和httpbin
`pip install gunicorn httpbin` (使用flask框架) 
安装后，使用`gunicorn httpbin:app`启动服务

### demo

1. 使用urllib

	urllib,urllib2,urllib3
	urllib和urllib2是相互独立的模块，requests库使用了urllib3，(多次请求重复使用一个socket)

2. 使用requests

	github api https://developer.github.com

	GET查看资源 POST增加资源 PATCH更新资源 PUT替换资源 DELETE删除资源 HEAD查看响应头 OPTIONS查看可用请求方法

### 发送请求

#### HTTP状态码

1xx 消息
2xx 成功
	200 OK
	201 
3xx 重定向
4xx 客户端错误
5xx 服务端错误

### 处理响应

#### 响应基本api

encoding
raw 
content
text
json  获得更多信息

#### 下载图片/文件

#### 处理响应的事件钩子

### 进阶话题

#### HTTP认证
基本认证 用户名/密码
token验证

#### 代理 Proxy
请求转发

1. 启动代理服务Heroku
2. 在主机1080端口启动Socks服务
3. 将请求转发到1080
4. 获取相应资源

#### Session和Cookie
cookie:
浏览器http请求(无cookie)->服务器http响应->浏览器设置cookie，保存本地->http请求(带cookie)->解析cookie识别信息->http响应

每次请求均需带cookie，带宽
cookie在浏览器端，易伪造

session:
http请求->服务器存储session->http响应(set cookie-session-id),浏览器解析cookie保存本地(很小)->http请求(带cookie)->解析sessionid->http响应
session存在服务器端，从网络转到服务器

压力从浏览器到服务器，不安全介质到安全介质

## web.py框架


