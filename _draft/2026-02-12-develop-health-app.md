---
title: 利用AI开发一个体检指标跟踪应用
description: 利用AI开发一个体检指标跟踪应用
categories: [AI, LLM]
tags: [AI, Vibe Coding]
---

## 1. 引言

先说下初衷：家人有慢性病，需要定期到医院开药和检查指标，一些关注指标目前靠手动记录对比，而且要推算下次去医院的时间。于是准备利用AI开发一个简单的应用，能手动记录每次结果，自动生成变化趋势，最好能跟微信小程序打通。

一、基本需求梳理如下：
* 1、支持按照日期添加体检指标记录
* 2、支持展示指标变化趋势
* 3、支持添加提醒事项：检查、开药

二、阶段二需求：
* 1、支持通过微信小程序访问和添加记录
* 2、微信小程序临期自动提醒

三、后续需求：
* 1、支持上传体检报告自动添加指标记录
* 2、对接LLM API，根据指标情况提供饮食建议
* 此外，可以结合openclaw、skill进行结合实践

## 2. 程序开发

### 2.1. IDE和模型说明

主要是利用LLM进行Vibe Coding：
* VSCode + Cline
* LLM API：阿里云百炼`Coding Plan`
    * 推理模型（Plan模式）：qwen3-max-2026-01-23
    * 代码生成模型（Act模式）：qwen3-coder-plus

### 2.2. 技术栈和代码开发

相关技术栈说明：
* Go实现后端，Gin提供Web框架
* 数据库使用SQLite，简化环境依赖和操作
* 页面基于简单HTML+JS+CSS，暂不引入前端框架

经过几轮提示和修改，代码层次如下（代码可见：[health_app](https://github.com/xiaodongQ/health_app)）：

```sh
[MacOS-xd@qxd ➜ health_app git:(main) ✗ ]$ tree
.
├── add_test_records.sh
├── configs
│   └── config.go
├── go.mod
├── go.sum
├── health_app.db
├── internal
│   ├── api
│   │   ├── health_config.go
│   │   ├── health_records.go
│   │   ├── reminders.go
│   │   └── user.go
│   ├── models
│   │   ├── health_record.go
│   │   └── user.go
│   ├── repository
│   │   ├── health_record_repository.go
│   │   ├── reminder_repository.go
│   │   └── user_repository.go
│   └── service
│       ├── health_record_service.go
│       ├── reminder_service.go
│       └── user_service.go
├── main.go
└── web
    └── index.html
```

### 2.3. 程序效果

1、总览：  
![总览](/images/2026-02-12_health_app_overview.png)

2、添加记录：  
![添加记录](/images/2026-02-12_health_app_add.png)

3、趋势图表：  
![趋势图表](/images/2026-02-12_health_app_chart.png)

## 3. 集成微信小程序



## 4. 小结


## 5. 参考


