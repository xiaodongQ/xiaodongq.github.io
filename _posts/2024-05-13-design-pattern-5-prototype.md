---
layout: post
title: 创建型设计模式-原型模式
categories: 设计模式
tags: 设计模式
---

* content
{:toc}

创建型设计模式-原型模式示例记录



## 1. 背景

最近梳理项目模块代码，其中部分模块和工具涉及一些设计模式，画了一些相关的流程图和草图。重新打开极客时间里设计模式课程，通过示例(C++)加强一些体感。

## 2. 23种设计模式简要说明

![23种设计模式](/images/2024-05-12-20240512100608.png)

这里说明原型模式

## 3. 原型模式(Prototype Pattern)

如果对象的创建成本比较大，而同一个类的不同对象之间差别不大（大部分字段都相同），在这种情况下，我们可以利用对已有对象（原型）进行复制（或者叫拷贝）的方式来创建新对象，以达到节省创建时间的目的。**这种基于已有对象来创建对象的方式就叫作原型设计模式（Prototype Design Pattern），简称原型模式。**

tips：有别于 Java、C++ 等基于类的面向对象编程语言，JavaScript 是一种基于原型的面向对象编程语言。

### 3.1. 特点和应用场景

特点：

1. 由原型对象自身创建目标对象：对象创建的动作发自原型对象本身。
2. 目标对象是原型对象的一个克隆：通过原型模式创建的对象，不仅与原型对象具有相同的结构，还具有相同的值。
3. 浅克隆与深克隆：根据对象克隆深度层次的不同，有**浅克隆**（只复制对象的浅层数据结构和引用，不复制对象引用的对象）与**深克隆**（复制对象的所有层次，包括对象引用的对象）。

应用场景：

1. 需要创建大量相似对象：避免重复的初始化，提高对象的创建效率。
2. 创建对象的过程复杂：需要多次初始化不同的属性时，使用原型模式可以简化对象的创建过程。
3. 需要动态地改变对象的属性：通过克隆来创建新的对象，避免修改原有对象的属性。
4. 系统需要保护对象的状态：创建对象的副本进行操作，不影响原对象的状态。

### 3.2. 示例

```cpp
#include <iostream>  
#include <string>  
#include <memory> // 用于智能指针  
  
// 抽象原型类  
class Prototype {  
public:  
    virtual ~Prototype() {}  
  
    // 声明克隆接口为纯虚函数  
    virtual std::unique_ptr<Prototype> clone() const = 0;  
  
    // 其他成员函数...  
    void setSomeValue(const std::string& value) {  
        someValue = value;  
    }  
  
    std::string getSomeValue() const {  
        return someValue;  
    }  
  
private:  
    std::string someValue;  
};  
  
// 具体原型类  
class ConcretePrototype : public Prototype {  
public:  
    ConcretePrototype(const std::string& value) { setSomeValue(value); }  
  
    // 实现克隆接口  
    std::unique_ptr<Prototype> clone() const override {  
        // 使用new来动态分配内存，并包装在unique_ptr中  
        return std::unique_ptr<ConcretePrototype>(new ConcretePrototype(*this));  
    }  
  
    // 可能还需要其他成员函数...  
};  
  
// 使用原型模式的示例  
int main() {  
    // 使用智能指针来管理Prototype对象的生命周期  
    // std::unique_ptr<Prototype> proto = std::make_unique<ConcretePrototype>("Hello, Prototype!");  
    // 注意：std::make_unique是C++14引入的，C++11中需要直接使用new  
    // 如果编译器不支持std::make_unique，可以这样写：  
    std::unique_ptr<Prototype> proto(new ConcretePrototype("Hello, Prototype!"));  
  
    std::cout << "Original: " << proto->getSomeValue() << std::endl;  
  
    // 使用原型克隆新对象  
    std::unique_ptr<Prototype> cloned = proto->clone();  
    std::cout << "Cloned: " << cloned->getSomeValue() << std::endl;  
  
    // 不需要手动delete，因为智能指针会自动管理内存  
  
    // 如果需要修改克隆对象的值  
    cloned->setSomeValue("Modified Clone");  
    std::cout << "Modified Cloned: " << cloned->getSomeValue() << std::endl;  
  
    // 原始对象的值并未改变  
    std::cout << "Original Still: " << proto->getSomeValue() << std::endl;  
  
    return 0;  
}
```

g++ prototype.cpp -std=c++11

## 4. 小结

1、通过示例介绍了原型模式

## 5. 参考

1、[极客时间：设计模式之美](https://time.geekbang.org/column/article/200786)

2、GPT
