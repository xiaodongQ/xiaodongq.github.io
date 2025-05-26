---
title: Ceph学习笔记（三） -- Ceph对象存储
description: 梳理Ceph对象存储和相关流程。
categories: [存储和数据库, Ceph]
tags: [存储, Ceph]
---


## 1. 引言

前面梳理了Ceph的基本架构，并简单搭建了Ceph集群。现在进入到代码层，对Ceph功能进行进一步深入，本篇梳理 **<mark>对象存储</mark>**，并跟踪梳理代码处理流程。

## 2. 对象存储说明

### 2.1. Ceph对象存储架构

Ceph`对象存储`包含一个`Ceph存储集群`和一个`对象网关`（Ceph Object Gateway）。

* **Ceph存储集群**：如前面 [Ceph集群构成](https://xiaodongq.github.io/2025/05/03/ceph-overview/#22-ceph%E9%9B%86%E7%BE%A4%E6%9E%84%E6%88%90) 中所述，一个Ceph存储集群中至少包含`monitor`、`manager`、`osd`，文件存储则还包含`mds`。
* **对象网关**：构建在`librados`之上，通过`radosgw`守护进程提供服务，为应用程序提供对象存储`RESTful API`，用于操作Ceph存储集群。

Ceph支持两种对象存储接口，两者共享一个命名空间（namespace），意味着一类接口写的数据可以通过另一类接口读取。

* `S3`兼容接口，Amazon S3 RESTful API
* `Swift`兼容接口，OpenStack Swift API

![ceph-object-storage](/images/ceph-object-storage.png)  
[出处](https://docs.ceph.com/en/squid/radosgw/)

### 2.2. S3对象存储

> 详情可见：[Amazon Simple Storage Service](https://docs.aws.amazon.com/AmazonS3/latest/API/Welcome.html)。

介绍下`Amazon`的`S3（Simple Storage Service ）`对象存储，用户可以通过任意支持HTTP协议的工具，基于`REST API`来访问可读对象（object）。`REST API`中使用标准的HTTP头和状态码，因此一些标准浏览器和工具箱（toolkit）都可以正常访问S3。

若在代码里直接使用`REST API`，需要编写计算签名的代码来对请求进行鉴权。**建议**使用下述两种方式：

* 1、使用 [AWS SDKs](https://aws.amazon.com/cn/developer/tools/?nc1=f_dr) 来发送请求，SDK客户端会根据用户提供的`access keys`来进行校验。如果没有其他更好的理由，**一般都使用`AWS SDKs`方式**。
* 2、使用 `AWS CLI` 来触发S3 API。

#### 2.2.1. S3 API

> 详情可见：[S3 API Reference](https://docs.aws.amazon.com/AmazonS3/latest/API/Type_API_Reference.html)。

S3 API包含`操作`（actions/operations）和`数据类型`（data types）两部分，并组织成了 **`3`个集合**：
* `Amazon S3`，定义了`bucket`和`object`层级的API操作
* `Amazon S3 Control`，定义了管理其他S3资源的API操作
* `Amazon S3 on Outposts`，可以扩展AWS到用户本地环境

这里看下针对`bucket`和`object`的 [Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/API/API_Operations_Amazon_Simple_Storage_Service.html) 部分操作：

* **创建bucket**：`CreateBucket`
    * 创建bucket需要一个AK（Access Key），不允许匿名创建请求。
    * 详情和示例可见：[CreateBucket](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateBucket.html)

示例：创建名为`amzn-s3-demo-bucket`的bucket

```html
    <!-- 请求 -->
    PUT / HTTP/1.1
    Host: amzn-s3-demo-bucket.s3.<Region>.amazonaws.com
    Content-Length: 0
    Date: Wed, 01 Mar  2006 12:00:00 GMT
    Authorization: authorization string

    <!-- 应答 -->
    HTTP/1.1 200 OK
    x-amz-id-2: YgIPIfBiKa2bj0KMg95r/0zo3emzU4dzsD4rcKCHQUAdQkf3ShJTOOpXUueF6QKo
    x-amz-request-id: 236A8905248E5A01
    Date: Wed, 01 Mar  2006 12:00:00 GMT

    Location: /amzn-s3-demo-bucket
    Content-Length: 0
    Connection: close
    Server: AmazonS3
```

* **创建object**：`PutObject`
    * 向bucket中添加一个object
    * S3是一个分布式系统，可以通过`S3 Object Lock`进行并发请求的保护
    * URI请求参数很多，具体可见：[PutObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObject.html)

示例：将图片`my-image.jpg`存入到名为`myBucket`的bucket中，下面的`[11434 bytes of object data]`表示具体二进制数据

```html
    <!-- 请求 -->
    PUT /my-image.jpg HTTP/1.1
    Host: myBucket.s3.<Region>.amazonaws.com
    Date: Wed, 12 Oct 2009 17:50:00 GMT
    Authorization: authorization string
    Content-Type: text/plain
    Content-Length: 11434
    x-amz-meta-author: Janet
    Expect: 100-continue
    [11434 bytes of object data]

    <!-- 应答 -->
    HTTP/1.1 100 Continue

    HTTP/1.1 200 OK
    x-amz-id-2: LriYPLdmOdAiIfgSm/F1YsViT1LW94/xUQxMsF7xiEb1a0wiIOIxl+zbwZ163pt7
    x-amz-request-id: 0A49CE4060975EAC
    Date: Wed, 12 Oct 2009 17:50:00 GMT
    ETag: "1b2cf535f27731c974343645a3985328"
    Content-Length: 0
    Connection: close
    Server: AmazonS3
```

* **下载object**：`GetObject`
    * 指定object的完整key名
    * [GetObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObject.html)

示例：下载 my-image.jpg 对象，应答中的`[434234 bytes of object data]`表示图片对象的二进制数据

```html
    <!-- 请求 -->
    GET /my-image.jpg HTTP/1.1
    Host: amzn-s3-demo-bucket.s3.<Region>.amazonaws.com
    Date: Mon, 3 Oct 2016 22:32:00 GMT
    Authorization: authorization string
    
    <!-- 应答 -->
    HTTP/1.1 200 OK
    x-amz-id-2: eftixk72aD6Ap51TnqcoF8eFidJG9Z/2mkiDFu8yU9AS1ed4OpIszj7UDNEHGran
    x-amz-request-id: 318BC8BC148832E5
    Date: Mon, 3 Oct 2016 22:32:00 GMT
    Last-Modified: Wed, 12 Oct 2009 17:50:00 GMT
    ETag: "fba9dede5f27731c9771645a39863328"
    Content-Length: 434234

    [434234 bytes of object data]
```

* **获取bucket列表**：`ListBuckets`
    * [ListBuckets](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListBuckets.html)

只要URI即可，不需要HTTP body，URI里可以设置条件，比如此处限制bucket数量为1000：

```html
    <!-- 请求 -->
    GET /?max-buckets=1000&host:s3.us-east-2.amazonaws.com HTTP/1.1

    <!-- 应答 -->
    HTTP/1.1 200 OK
    <ListAllMyBucketsResult>
    ...
    </ListAllMyBucketsResult>
```

#### 2.2.2. S3 SDK

通过上面的S3 SDK链接可看到支持多种编程语言的SDK，比如`C++`、`Go`、`Java`、`JS`、`Rust`等等，这里简单看下 [C++ SDK](https://sdk.amazonaws.com/cpp/api/LATEST/root/html/index.html)。

`C++`的S3 SDK基于CMake构建，C++标准需`>= C++11`。使用C++ SDK的示例，可见：[example_code](https://github.com/awsdocs/aws-doc-sdk-examples/tree/main/cpp/example_code)。

比如：[put_object.cpp](https://github.com/awsdocs/aws-doc-sdk-examples/blob/main/cpp/example_code/s3/put_object.cpp)

```cpp
bool AwsDoc::S3::putObject(const Aws::String &bucketName,
                           const Aws::String &fileName,
                           const Aws::S3::S3ClientConfiguration &clientConfig) {
    Aws::S3::S3Client s3Client(clientConfig);
    
    Aws::S3::Model::PutObjectRequest request;
    request.SetBucket(bucketName);
    // 此处以文件名为key，具体以实际为准
    request.SetKey(fileName);
    std::shared_ptr<Aws::IOStream> inputData =
            Aws::MakeShared<Aws::FStream>("SampleAllocationTag",
                                          fileName.c_str(),
                                          std::ios_base::in | std::ios_base::binary);
    request.SetBody(inputData);

    // 请求
    Aws::S3::Model::PutObjectOutcome outcome =
            s3Client.PutObject(request);
    if (!outcome.IsSuccess()) {
        std::cerr << "Error: putObject: " << outcome.GetError().GetMessage() << std::endl;
    } else {
        std::cout << "Added object '" << fileName << "' to bucket '" << bucketName << "'.";
    }
    return outcome.IsSuccess();
}

int main(int argc, char* argv[])
{
    ...
    Aws::SDKOptions options;
    Aws::InitAPI(options);
    {
        const Aws::String fileName = argv[1];
        const Aws::String bucketName = argv[2];

        Aws::S3::S3ClientConfiguration clientConfig;
        // Optional: Set to the AWS Region in which the bucket was created (overrides config file).
        // clientConfig.region = "us-east-1";

        AwsDoc::S3::putObject(bucketName, fileName, clientConfig);
    }
    Aws::ShutdownAPI(options);
    return 0;
}
```

### 2.3. Swift对象存储

> 详情可见：[Introduction to Object Storage](https://docs.openstack.org/swift/latest/admin/objectstorage-intro.html)，以及[Object Storage API](https://docs.openstack.org/api-ref/object-store/index.html#)

`OpenStack`对象存储（也称`Swift`）是一个高可用、分布式、最终一致性的对象存储，通过`REST（Representational State Transfer） API`进行创建、修改、获取对象和元数据。

* 创建容器：`PUT /v1/{account}/{container}`
    * 示例：创建名为`steven`的container时不带元数据，`curl -i $publicURL/steven -X PUT -H "Content-Length: 0" -H "X-Auth-Token: $token"`
* 创建对象：`PUT /v1/{account}/{container}/{object}`
    * 示例：向名为`janeausten`的container中创建`helloworld.txt`对象，`url -i $publicURL/janeausten/helloworld.txt -X PUT -d "Hello" -H "Content-Type: text/html; charset=UTF-8" -H "X-Auth-Token: $token"`

## 3. Ceph对象存储代码流程

为了便于代码查看和跳转，为clangd生成`compile_commands.json`（电脑快用9年了，cpptools跑起来风扇就呼呼响）。自己在MacOS上很多依赖安装有不少问题，折腾了挺久，在linux上生成后再替换路径可以勉强使用。

### 3.1. main函数入口

rgw的入口在`rgw_main.cc`中。

```cpp
// ceph-v19.2.2/src/rgw/rgw_main.cc
// 相对于17.2.x，main代码的组织简洁了很多，之前版本main函数有好几百行
int main(int argc, char *argv[])
{
  ...
  // 入参转换为vector
  auto args = argv_to_vec(argc, argv);
  ...
  // 全局初始化，其中会分配ceph上下文类`CephContext`并初始化、并设置实例指针到 g_ceph_context 全局变量
  auto cct = rgw_global_init(&defaults, args, CEPH_ENTITY_TYPE_CLIENT,
                             CODE_ENVIRONMENT_DAEMON, flags);

  DoutPrefix dp(cct.get(), dout_subsys, "rgw main: ");
  // rgw的主服务类
  rgw::AppMain main(&dp);

  // RGW 的前端（Frontend）负责处理客户端的请求：监听网络端口、处理HTTP/HTTPS请求、路由请求到后端的 RADOS 存储集群
  main.init_frontends1(false /* nfs */);
  // 根据配置绑定numa亲和性
  main.init_numa();
  ...
  // 定时器初始化
  init_timer.init();
  ...
  common_init_finish(g_ceph_context);
  // 初始化异步信号的处理器（其中是一个线程，利用poll轮询检测32个信号注册的读事件）
  init_async_signal_handler();
  // 注册部分信号和对应处理函数
  register_async_signal_handler(SIGHUP, rgw::signal::sighup_handler);
  register_async_signal_handler(SIGTERM, rgw::signal::handle_sigterm);
  register_async_signal_handler(SIGINT, rgw::signal::handle_sigterm);
  ...
  main.init_perfcounters();
  // 初始化DNS、curl、http客户端和kmip秘钥管理
  main.init_http_clients();

  r = main.init_storage();
  ...
  // 初始化s3、swift对应的rest api
  main.cond_init_apis();
  main.init_ldap();
  main.init_opslog();
  main.init_tracepoints();
  main.init_lua();
  // 里面包含了RGW前端具体初始化操作
  r = main.init_frontends2(nullptr /* RGWLib */);
  ...
  rgw::signal::wait_shutdown();
  ...
}
```

## 4. 小结

简单梳理Ceph对象存储，跟踪main函数流程。

## 5. 参考

* [Ceph Object Gateway](https://docs.ceph.com/en/squid/radosgw/#object-gateway)
* [Ceph Git仓库](https://github.com/ceph/ceph)
* [Amazon Simple Storage Service](https://docs.aws.amazon.com/AmazonS3/latest/API/Welcome.html)
* [Introduction to Object Storage -- Swift](https://docs.openstack.org/swift/latest/admin/objectstorage-intro.html)
* [浅析开源项目之Ceph](https://zhuanlan.zhihu.com/p/360355168)
* [解读RGW中request的处理流程](https://cloud.tencent.com/developer/article/1032838)
* LLM