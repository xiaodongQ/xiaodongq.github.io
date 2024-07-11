---
layout: post
title: 行为型设计模式-策略模式
categories: 设计模式
tags: 设计模式
---

* content
{:toc}

行为型设计模式-策略模式模式示例记录



## 1. 背景

通过示例(C++)加强对设计模式的体感。

## 2. 23种设计模式简要说明

![23种设计模式](/images/2024-05-12-20240512100608.png)

这里说明策略模式

## 3. 策略模式(Strategy Pattern)

策略模式（Strategy Pattern）是一种行为设计模式，它使你能够定义一系列算法，并将每一个算法封装起来，使它们可以互相替换。策略模式使得算法可以独立于使用它的客户端变化。

策略模式包含以下三个主要角色：

1. **策略接口（Strategy）**：定义了一个算法的接口，所有的具体策略类都需要实现这个接口。这样，客户端就可以通过策略接口来调用不同的策略算法。

2. **具体策略（Concrete Strategy）**：实现了策略接口，封装了具体的算法逻辑。客户端可以通过策略接口来调用这些具体的算法。

3. **上下文（Context）**：也被称为策略使用者，它持有一个策略接口的引用，用于调用具体的策略算法。上下文通常使用策略接口来配置其所需的行为。

```cpp
#include <iostream>  
#include <string>  
#include <memory>  
  
// 策略接口（抽象类）  
class RenderingStrategy {  
public:  
    virtual ~RenderingStrategy() = default;  
    virtual std::string render(const std::string& data) const = 0;  
};  
  
// 具体策略：ProductRenderingStrategy  
class ProductRenderingStrategy : public RenderingStrategy {  
public:  
    std::string render(const std::string& data) const override {  
        return "<table><tr><td>" + data + "</td></tr></table>";  
    }  
};  
  
// 具体策略：UserRenderingStrategy  
class UserRenderingStrategy : public RenderingStrategy {  
public:  
    std::string render(const std::string& data) const override {  
        return "{\"user\":\"" + data + "\"}";  
    }  
};  
  
// 上下文类（Context）  
class RenderingContext {  
private:  
    std::unique_ptr<RenderingStrategy> strategy;  
  
public:  
    // 构造函数接收一个std::unique_ptr<RenderingStrategy>  
    RenderingContext(std::unique_ptr<RenderingStrategy> s) : strategy(std::move(s)) {}  
  
    std::string renderData(const std::string& data) {  
        return strategy->render(data);  
    }  
  
    // 可以通过成员函数来改变策略，但需要传入新的std::unique_ptr<RenderingStrategy>  
    void setStrategy(std::unique_ptr<RenderingStrategy> s) {  
        strategy = std::move(s);  
    }  
};  
  
int main() {  
    // 使用std::make_unique创建具体策略对象的unique_ptr  
    auto productStrategy = std::make_unique<ProductRenderingStrategy>();  
    auto userStrategy = std::make_unique<UserRenderingStrategy>();  
  
    // 创建上下文对象，并传入unique_ptr  
    RenderingContext context(std::move(productStrategy));  
    std::string productHtml = context.renderData("Product A");  
    std::cout << "Product Rendered: " << productHtml << std::endl;  
  
    // 改变策略并重新渲染  
    context.setStrategy(std::move(userStrategy));  
    std::string userJson = context.renderData("User123");  
    std::cout << "User Rendered: " << userJson << std::endl;  
  
    return 0;  
}
```

g++ strategy.cpp -std=c++14 -o strategy (std::make_unique在C++14中才支持)

```cpp
#include <iostream>  
#include <string>  
#include <memory>  
  
// 策略接口（抽象类）  
class RenderingStrategy {  
public:  
    virtual ~RenderingStrategy() = default;  
    virtual std::string render(const std::string& data) const = 0;  
};  
  
// 具体策略：ProductRenderingStrategy  
class ProductRenderingStrategy : public RenderingStrategy {  
public:  
    std::string render(const std::string& data) const override {  
        return "<table><tr><td>" + data + "</td></tr></table>";  
    }  
};  
  
// 具体策略：UserRenderingStrategy  
class UserRenderingStrategy : public RenderingStrategy {  
public:  
    std::string render(const std::string& data) const override {  
        return "{\"user\":\"" + data + "\"}";  
    }  
};  
  
// 上下文类（Context）  
class RenderingContext {  
private:  
    std::unique_ptr<RenderingStrategy> strategy;  
  
public:  
    // 构造函数接收一个裸指针，并用 std::unique_ptr 管理它  
    RenderingContext(RenderingStrategy* s) : strategy(s) {}  
  
    // 更安全的构造函数，使用 std::unique_ptr 管理 new 分配的对象  
    explicit RenderingContext(std::unique_ptr<RenderingStrategy> s) : strategy(std::move(s)) {}  
  
    std::string renderData(const std::string& data) {  
        return strategy->render(data);  
    }  
  
    // 可以通过成员函数来改变策略  
    void setStrategy(std::unique_ptr<RenderingStrategy> s) {  
        strategy = std::move(s);  
    }  
};  
  
int main() {  
    // 使用 new 运算符创建具体策略对象，并用 std::unique_ptr 管理  
    std::unique_ptr<RenderingStrategy> productStrategy(new ProductRenderingStrategy());  
    std::unique_ptr<RenderingStrategy> userStrategy(new UserRenderingStrategy());  
  
    // 创建上下文对象，并传入 std::unique_ptr  
    RenderingContext context(std::move(productStrategy));  
    std::string productHtml = context.renderData("Product A");  
    std::cout << "Product Rendered: " << productHtml << std::endl;  
  
    // 改变策略并重新渲染  
    context.setStrategy(std::move(userStrategy));  
    std::string userJson = context.renderData("User123");  
    std::cout << "User Rendered: " << userJson << std::endl;  
  
    return 0;  
}
```

g++ strategy.cpp -std=c++11 -o strategy

## 4. 小结

1、通过示例介绍了策略模式

## 5. 参考

1、GPT
