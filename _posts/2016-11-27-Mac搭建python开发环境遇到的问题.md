---
layout: post
title: Mac搭建python开发环境遇到的问题
categories: Linux
tags: Linux Mac Python pip
---

* content
{:toc}

在慕课网上了解python的web框架django，搭建python环境时遇到些问题。

OS X系统自带了python运行环境，但作为开发不是很方便，tab键无补全提示；另外后续需要安装一些模块。所以安装一下ipython和pip。




## 安装

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

## 使用简介

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