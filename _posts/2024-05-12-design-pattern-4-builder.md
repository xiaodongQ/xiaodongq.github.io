---
title: 创建型设计模式-建造者模式
categories: 设计模式
tags: 设计模式
---

创建型设计模式-建造者模式示例记录

## 1. 背景

最近梳理项目模块代码，其中部分模块和工具涉及一些设计模式，画了一些相关的流程图和草图。重新打开极客时间里设计模式课程，通过示例(C++)加强一些体感。

## 2. 23种设计模式简要说明

![23种设计模式](/images/2024-05-12-20240512100608.png)

这里说明建造者模式

## 3. 建造者模式(Builder Pattern)

Builder 模式，中文翻译为建造者模式或者构建者模式，也有人叫它生成器模式。

允许你在不改变类结构的情况下，将对象的构建过程与它的表示分离。

### 3.1. 适用场景

建造者模式的原理和代码实现非常简单，掌握起来并不难，难点在于应用场景。

1. 对象构建复杂：当一个对象的构建过程需要多个步骤，且这些步骤可能依赖于不同的输入参数或者构建选项时，使用建造者模式可以清晰地组织这些步骤，并允许客户端代码在不直接操作对象内部表示的情况下创建对象。
2. 构建过程需要统一控制：在某些情况下，对象的构建过程需要遵循一定的顺序或者规则，而这些规则可能随着版本迭代或者业务需求的改变而发生变化。
3. 产品类需要扩展：如果产品类（即需要构建的对象）经常需要添加新的属性或者构建步骤，而又不希望修改已有的客户端代码，那么可以使用建造者模式。
4. 减少构造函数参数数量：当一个类的构造函数需要传入大量参数，并且这些参数中的一部分或全部可能是可选的时，使用建造者模式可以将这些参数封装在建造者类中，并提供链式调用的方式设置这些参数。这样不仅可以减少构造函数中的参数数量，还可以提高代码的可读性和可维护性。
5. 测试场景：在编写单元测试时，可能需要创建具有特定属性和状态的对象。使用建造者模式可以方便地创建具有不同属性和状态的对象实例，以便进行测试。
6. 多个相似产品族的构建：如果系统需要支持多个产品族（即多个不同但相似的产品集合），且这些产品族具有相同的构建步骤但使用不同的实现，那么可以使用建造者模式。每个产品族可以对应一个具体建造者类，而指挥者类可以保持不变，只需在创建指挥者对象时传入不同的具体建造者对象即可。

举例：游戏角色创建

    在游戏开发中，角色的创建通常涉及多个步骤和多种属性。例如，一个战士角色可能需要设置生命值、攻击力、防御力、技能等属性。

    这个场景中，可以有一个抽象的“角色建造者”接口，定义了设置各种属性的方法。然后，你可以创建具体的“战士建造者”类，实现这个接口并添加特定的战士属性设置方法。最后，你可以有一个“角色指挥者”类，它使用角色建造者来构建角色，并按照一定的顺序调用建造者的方法。这样，你就可以通过调用指挥者的方法来创建具有不同属性和技能的角色了。

### 3.2. 示例

定义一个产品类，进行构建示例

```cpp
#include <iostream>  
#include <string>  

// 产品类  
class Product {  
public:  
    void setPartA(std::string partA) { this->partA = partA; }  
    void setPartB(std::string partB) { this->partB = partB; }  
    void setPartC(std::string partC) { this->partC = partC; }  
  
    // 输出产品信息  
    void display() {  
        std::cout << "Product created with parts: "  
                  << "A = " << partA << ", "  
                  << "B = " << partB << ", "  
                  << "C = " << partC << std::endl;  
    }  
  
private:  
    std::string partA, partB, partC;  
};  
  
// 此处是将Builder设计成单独的实现类，也有场景会将其设计成上述类的内部类
// 抽象建造者  
class Builder {  
public:  
    virtual void buildPartA(std::string partA) = 0;  
    virtual void buildPartB(std::string partB) = 0;  
    virtual void buildPartC(std::string partC) = 0;  
    virtual Product* getResult() = 0;  
};  
  
// 具体建造者  
// 可以根据不同产品创建不同的具体建造类
class ConcreteBuilder : public Builder {  
private:  
    Product* product;  
  
public:  
    ConcreteBuilder() {  
        product = new Product();  
    }  
  
    ~ConcreteBuilder() {  
        delete product;  
    }  
  
    void buildPartA(std::string partA) override {  
        product->setPartA(partA);  
    }  
  
    void buildPartB(std::string partB) override {  
        product->setPartB(partB);  
    }  
  
    void buildPartC(std::string partC) override {  
        product->setPartC(partC);  
    }  
  
    Product* getResult() override {  
        return product;  
    }  
};  
  
// 指挥者类  
class Director {  
private:  
    Builder* builder;  
  
public:  
    Director(Builder* builder) : builder(builder) {}  
  
    void constructProduct() {  
        builder->buildPartA("PartA");  
        builder->buildPartB("PartB");  
        builder->buildPartC("PartC");  
    }  
  
    Product* getProduct() {  
        return builder->getResult();  
    }  
};  
  
// 使用示例  
int main() {  
    Builder* builder = new ConcreteBuilder();  
    // 将对象的构建过程与它的表示分离，只需要传入不同对象的具体构建类
    Director* director = new Director(builder);  
  
    director->constructProduct();  
  
    Product* product = director->getProduct();  
    product->display();  
  
    delete builder;  
    delete director;  
  
    return 0;  
}
```

## 4. 小结

1、通过示例介绍了建造者模式

## 5. 参考

1、[极客时间：设计模式之美](https://time.geekbang.org/column/article/198614)

2、GPT
