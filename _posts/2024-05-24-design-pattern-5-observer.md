---
layout: post
title: 行为型设计模式-观察者模式
categories: 设计模式
tags: 设计模式
---

* content
{:toc}

行为型设计模式-观察者模式示例记录



## 1. 背景

通过示例(C++)加强对设计模式的体感。

## 2. 23种设计模式简要说明

![23种设计模式](/images/2024-05-12-20240512100608.png)

这里说明观察者模式

## 3. 观察者模式(Observer Pattern)

观察者模式（Observer Pattern） 是一种行为设计模式，它定义了一种一对多的依赖关系，让多个观察者对象同时监听某一个主题对象。

这个主题对象在状态发生变化时，会通知所有依赖它的观察者对象，使它们能够自动更新自己。

角色：

主题（Subject）：定义了被观察的对象，它把所有对观察者对象的引用保存在一个集合中，每个主题都可以有任意数量的观察者。

观察者（Observer）：为那些在主题发生改变时需要获得通知的对象定义一个更新接口。这个接口使得主题能够知道观察者的哪一个方法应该被调用。

```cpp
#include <iostream>  
#include <list>  
#include <memory>  
  
// Observer 接口  
class Observer {  
public:  
    virtual ~Observer() = default;  
    virtual void update(const std::string& message) = 0;  
};  
  
// ConcreteObserver 类，实现了 Observer 接口  
class ConcreteObserver : public Observer {  
private:  
    std::string name;  
  
public:  
    ConcreteObserver(const std::string& name) : name(name) {}  
  
    void update(const std::string& message) override {  
        std::cout << name << " received: " << message << std::endl;  
    }  
};  
  
// Subject 类  
class Subject {  
private:  
    std::list<std::shared_ptr<Observer>> observers;  
  
public:  
    void attach(std::shared_ptr<Observer> observer) {  
        observers.push_back(observer);  
    }  
  
    void detach(std::shared_ptr<Observer> observer) {  
        observers.remove(observer);  
    }  
  
    void notify(const std::string& message) {  
        for (const auto& observer : observers) {  
            observer->update(message);  
        }  
    }  
  
    // 假设的状态改变方法  
    void changeState(const std::string& newState) {  
        std::cout << "Subject state changed to: " << newState << std::endl;  
        notify("State changed to " + newState);  
    }  
};  
  
int main() {  
    Subject subject;  
  
    std::shared_ptr<Observer> observer1 = std::make_shared<ConcreteObserver>("Observer 1");  
    std::shared_ptr<Observer> observer2 = std::make_shared<ConcreteObserver>("Observer 2");  
  
    subject.attach(observer1);  
    subject.attach(observer2);  
  
    subject.changeState("New State"); // 这将触发通知  
  
    // 如果我们不再需要某个观察者，可以注销它  
    subject.detach(observer1);  
  
    subject.changeState("Another New State"); // 这将只通知 observer2  
  
    return 0;  
}
```

g++ observer.cpp -std=c++11 -o observer

## 5. 小结

1、通过示例介绍了观察者模式

## 6. 参考

1、大模型
