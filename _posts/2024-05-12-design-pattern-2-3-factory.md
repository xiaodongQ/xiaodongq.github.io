---
title: 创建型设计模式-工厂模式
categories: 设计模式
tags: 设计模式
---

创建型设计模式-工厂模式示例记录

## 1. 背景

最近梳理项目模块代码，其中部分模块和工具涉及一些设计模式，画了一些相关的流程图和草图。重新打开极客时间里设计模式课程，通过示例(C++)加强一些体感。

## 2. 23种设计模式简要说明

![23种设计模式](/images/2024-05-12-20240512100608.png)

工厂模式通常分为简单工厂模式、工厂方法模式和抽象工厂模式。

在 GoF 的《设计模式》一书中，它将简单工厂模式看作是工厂方法模式的一种特例，所以工厂模式只被分成了 **工厂方法** 和 **抽象工厂** 两类。

## 3. 工厂方法

### 3.1. 简单工厂模式(Simple Factory Pattern)

通过一个工厂类来创建不同类的对象，而无需直接在客户端代码中指定要创建的具体对象类。

简单工厂模式的主要优点是客户端代码与具体的产品类解耦，使得系统更加灵活和可扩展。但是，当系统中需要添加新的产品时，可能需要修改工厂类，这在一定程度上违反了开闭原则(Open Closed Principle, OCP。对扩展开放、对修改关闭)。如果需要更高级别的灵活性和可扩展性，可以考虑使用抽象工厂模式或工厂方法模式。

```cpp
#include <iostream>  
#include <string>  
using namespace std;

// 产品接口  
class Shape {  
public:  
    virtual void draw() const = 0;  
    virtual ~Shape() {}  
};  
  
// 具体产品类：圆形  
class Circle : public Shape {  
public:  
    void draw() const override {  
        std::cout << "Drawing Circle.\n";  
    }  
};  
  
// 具体产品类：矩形  
class Rectangle : public Shape {  
public:  
    void draw() const override {  
        std::cout << "Drawing Rectangle.\n";  
    }  
};  

/* -------------------------------------- */
// 简单工厂类  
class ShapeFactory {  
public:  
    // 静态方法，用于创建产品对象  
    static Shape* createShape(const std::string& shapeType) {  
        if (shapeType == "circle") {  
            return new Circle();  
        } else if (shapeType == "rectangle") {  
            return new Rectangle();  
        }  
        // 如果没有找到匹配的类型，则返回nullptr或抛出异常  
        return nullptr;  
    }  
};

/* -----------客户端代码使用简单工厂来创建产品对象-------------- */
// 可和不用设计模式时对比：if...else，根据类型分别new不同实现类
int main() {  
    // 使用简单工厂创建圆形  
    Shape* circle = ShapeFactory::createShape("circle");  
    if (circle != nullptr) {  
        circle->draw();  
        delete circle; // 不要忘记释放内存  
    }  
  
    // 使用简单工厂创建矩形  
    Shape* rectangle = ShapeFactory::createShape("rectangle");  
    if (rectangle != nullptr) {  
        rectangle->draw();  
        delete rectangle; // 不要忘记释放内存  
    }  
  
    // 尝试创建一个不存在的形状类型  
    Shape* unknown = ShapeFactory::createShape("unknown");  
    if (unknown == nullptr) {  
        std::cout << "Unsupported shape type.\n";  
    }  
  
    return 0;  
}
```

### 3.2. 工厂方法模式(Factory Method Pattern)

定义了一个用于创建对象的接口，但让子类决定实例化哪一个类。工厂方法模式使得一个类的实例化延迟到其子类。

工厂方法模式的主要优点是增加了系统的可扩展性，当需要添加新的产品时，只需要创建新的产品类和相应的工厂类，而不需要修改已有的代码。

```cpp
#include <iostream>  
#include <string>  
#include <memory> // 使用智能指针管理内存
using namespace std;

// 产品抽象基类和具体类同上面的简单工厂(Shape、Circle、Rectangle)

/* ------------定义一个工厂接口(抽象类)，它包含一个创建产品的工厂方法---------- */
// 工厂接口  
class ShapeFactory {  
public:  
    virtual Shape* createShape() const = 0;  
    virtual ~ShapeFactory() {}  
};
/* -------------为每种产品创建一个具体的工厂类---------- */
// 圆形工厂类  
class CircleFactory : public ShapeFactory {  
public:  
    Shape* createShape() const override {  
        return new Circle();  
    }  
};  
  
// 矩形工厂类  
class RectangleFactory : public ShapeFactory {  
public:  
    Shape* createShape() const override {  
        return new Rectangle();  
    }  
};

/* --------------客户端代码使用具体的工厂类来创建产品对象------------------- */
int main() {  
    // 创建圆形工厂并生成圆形对象
    std::unique_ptr<ShapeFactory> circleFactory(new CircleFactory());  
    // 如果需要共享则调整成shared_ptr
    std::unique_ptr<Shape> circle(circleFactory->createShape());  
    circle->draw();  
  
    // 创建矩形工厂并生成矩形对象  
    std::unique_ptr<ShapeFactory> rectangleFactory(new RectangleFactory());  
    std::unique_ptr<Shape> rectangle(rectangleFactory->createShape());  
    rectangle->draw();  
  
    return 0;  
}
```

### 3.3. 使用场景说明

在选择简单工厂和工厂方法模式时，通常需要根据具体的应用场景和需求来决定。以下是对这两种模式适用场景的一些解释：

1. **简单工厂模式**：

    * **适用场景**：
        + **创建对象少**：当工厂类负责创建的对象比较少时，简单工厂模式是一个好的选择。
        + **不关心创建过程**：客户端只需要知道传入工厂类的参数，而不需要关心对象的具体创建过程。
    * **优点**：
        + 客户端只需要传入正确的参数，就可以获取需要的对象，无需知道创建细节。
        + 工厂类中有必要的判断逻辑，可以根据当前的参数创建对应的产品实例。
        + 实现了对创建实例和使用实例的责任分割。
    * **缺点**：
        + 工厂类职责过重，当需要创建的产品种类增加时，工厂类的代码可能会变得复杂和难以维护。
2. **工厂方法模式**：

    * **适用场景**：
        + **重复代码**：当创建对象需要使用大量重复的代码时，工厂方法模式可以通过定义一个单独的创建实例对象的方法来解决这个问题。
        + **不关心创建过程**：与简单工厂模式相似，客户端不依赖产品类，不关心实例如何被创建等细节。
        + **子类指定创建对象**：当一个类通过其子类来指定创建哪个对象时，工厂方法模式是一个好的选择。
    * **优点**：
        + 通过子类实现具体的工厂方法，可以创建具体的实例对象，使得代码更加结构化和易于维护。
        + 客户端不需要知道具体产品类的类名，只需要知道所对应的工厂即可。
    * **缺点**：
        + 相对于简单工厂模式，工厂方法模式更加复杂，需要定义更多的类和接口。
        + 当产品种类较多时，可能会导致类的数量增加，从而增加了系统的复杂性。

**选择建议**：

* 如果你的应用场景中需要创建的对象种类较少，且不需要频繁地添加新的对象种类，那么简单工厂模式可能是一个更好的选择。
* 如果你的应用场景中需要创建的对象种类较多，或者需要频繁地添加新的对象种类，那么工厂方法模式可能更适合你。通过定义一个接口和多个实现类，你可以更加灵活地扩展和管理你的代码。
* 另外，如果你的应用需要遵循开闭原则（即对扩展开放，对修改封闭），那么工厂方法模式也是一个更好的选择，因为它允许你在不修改已有代码的情况下添加新的产品种类。

## 4. 抽象工厂模式(Abstract Factory Pattern)

抽象工厂模式的应用场景比较特殊，没有前两种常用。

在简单工厂和工厂方法中，类只有一种分类方式。比如，在规则配置解析中，解析器类只会根据配置文件格式（Json、Xml、Yaml……）来分类。但是，如果类有两种分类方式，比如，我们既可以按照配置文件格式来分类，也可以按照解析的对象（Rule 规则配置还是 System 系统配置）来分类，那就会双倍的 parser 类，如果我们未来还需要增加针对业务配置的解析器（比如 IBizConfigParser），那就要再对应地增加 4 个工厂类。

抽象工厂就是针对这种非常特殊的场景而诞生的。可以让一个工厂负责创建多个不同类型的对象，而不是只创建一种 parser 对象。这样就可以有效地减少工厂类的个数。

以下是一个简单示例：创建一个可以生产“家具”的工厂，具体来说，有两种家具类型：椅子和桌子。同时，我们有两个不同风格的家具系列：现代风格和古典风格。

```cpp
#include <iostream>  
#include <memory> // 使用智能指针  
/* ----------------定义产品的抽象基类-------------- */
// 椅子的抽象基类  
class Chair {  
public:  
    virtual void sit() = 0;  
    virtual ~Chair() {}  
};  
  
// 桌子的抽象基类  
class Table {  
public:  
    virtual void placeObject() = 0;  
    virtual ~Table() {}  
};  
  
// 现代风格的椅子  
class ModernChair : public Chair {  
public:  
    void sit() override {  
        std::cout << "Sitting on a modern chair.\n";  
    }  
};  
  
// 古典风格的椅子  
class ClassicChair : public Chair {  
public:  
    void sit() override {  
        std::cout << "Sitting on a classic chair.\n";  
    }  
};  
  
// 现代风格的桌子  
class ModernTable : public Table {  
public:  
    void placeObject() override {  
        std::cout << "Placing object on a modern table.\n";  
    }  
};  
  
// 古典风格的桌子  
class ClassicTable : public Table {  
public:  
    void placeObject() override {  
        std::cout << "Placing object on a classic table.\n";  
    }  
};

/* ----------------定义抽象工厂接口和具体工厂实现-------------- */
// 抽象工厂接口  
class FurnitureFactory {  
public:  
    virtual Chair* createChair() = 0;  
    virtual Table* createTable() = 0;  
    virtual ~FurnitureFactory() {}  
};  
  
// 现代风格家具工厂  
class ModernFurnitureFactory : public FurnitureFactory {  
public:  
    Chair* createChair() override {  
        return new ModernChair();  
    }  
  
    Table* createTable() override {  
        return new ModernTable();  
    }  
};  
  
// 古典风格家具工厂  
class ClassicFurnitureFactory : public FurnitureFactory {  
public:  
    Chair* createChair() override {  
        return new ClassicChair();  
    }  
  
    Table* createTable() override {  
        return new ClassicTable();  
    }  
};

/* ----------------客户端代码使用抽象工厂接口来创建产品对象------------- */
int main() {  
    // 使用现代风格家具工厂  
    std::unique_ptr<FurnitureFactory> modernFactory(new ModernFurnitureFactory());  
    std::unique_ptr<Chair> modernChair(modernFactory->createChair());  
    std::unique_ptr<Table> modernTable(modernFactory->createTable());  
  
    modernChair->sit();  
    modernTable->placeObject();  
  
    // 使用古典风格家具工厂  
    std::unique_ptr<FurnitureFactory> classicFactory(new ClassicFurnitureFactory());  
    std::unique_ptr<Chair> classicChair(classicFactory->createChair());  
    std::unique_ptr<Table> classicTable(classicFactory->createTable());  
  
    classicChair->sit();  
    classicTable->placeObject();  
  
    return 0;  
}
```

## 5. 小结

1、通过示例介绍了简单工厂、工厂方法、抽象工厂模式

## 6. 参考

1、[极客时间：设计模式之美](https://time.geekbang.org/column/article/198614)

2、GPT
