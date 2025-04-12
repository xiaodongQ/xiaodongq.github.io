---
title: C++构造函数的隐式转换和转换函数
categories: C/C++
tags: [类型转换, 智能指针]
---

C++构造函数的隐式转换和转换函数说明，和explicit关键字使用。

近期使用智能指针，涉及到一些相关概念和特性(值语义/value semantics 和 对象语义/object semantics)，于此记录说明(智能指针别处单独说明)。

## explicit说明符

参考：

[explicit 说明符](https://zh.cppreference.com/w/cpp/language/explicit)

* 指定构造函数 或 转换函数(C++11 起)为显式，即它不能用于隐式转换和复制初始化。
    - 声明时不带函数说明符 explicit 的拥有单个无默认值形参的 (C++11 前)构造函数被称作转换构造函数
    - 构造函数（除了复制/移动）和用户定义转换函数都可以是函数模板；explicit 的含义不变。

## 隐式类型转换和转换函数

### 隐式类型转换

* 为什么c++需要隐式类型转换
    - c++多态的特性，就是通过父类的对象实现对子类的封装，以父类的类型返回之类对象。
    - c++中使用父类的地方一定可以使用子类代替，这也得益于隐式类型转换。
    - c++是一种强类型的语言，有着非常严格的类型检查，采用隐式类型转换会使程序员更方便快捷一点。
    - 但是在享受方便的时候，风险也紧跟其后。

参考(注意其中Sales_data的示例没有把combine函数实现放进去，只做了声明，编译需要加实现)：

[C++类型转换：隐式类型转换、类类型转换、显式类型转换](https://segmentfault.com/a/1190000016582440)

在C++语言中，类型转换有两种方式，隐式类型转换和显式类型转换。

* 隐式类型转换针对不同的类型有不同的转换方式，总体可以分为两种类型，算术类型和类类型。
    - 算术类型转换的设计原则就是尽可能避免损失精度。
        + 将小整数类型转换成较大的整数类型
        + 有符号类型转换为无符号类型
        + 在条件判断中，非布尔类型自动转换为布尔类型
        + 类类型转换
    - 类类型转换
        + 如果一个类的某个**构造函数**只接受**一个参数**，且**没有被声明为explicit**，则它实际上定义了将这个参数的类型转换为此类类型的隐式转换机制，我们把这种构造函数称为**转换构造函数**。
            * e.g. C类型字符串转换为string类型 `string s = "hello world"`，因为string类有一个构造函数`string(const char *s)`，所以"hello world"字符串可以自动转换为一个string类型的临时变量，然后将这个临时变量的值复制到s中。
            * e.g. class A中只有一个成员变量string b, 则定义变量时，`A(string("abc"))`也是成功的
            * 只有一次的隐式类类型转换是可行的，`A("abc")`时错误的，存在两次隐式转换
        + 如果不想隐式转换，以防用户误操作
            * 可以通过将构造函数声明为explicit来阻止隐式转换。
            * explicit构造函数只能用于直接初始化。不允许编译器执行其它默认操作（比如类型转换，赋值初始化）。
            * **关键字explicit只对一个实参的构造函数有效。**

### 转换函数

* 反向转换(转换函数)
    + 既然基本数据类型通过隐式转换为类，那么也可以做相反的转换，使用operator 类型转换操作符 参考：[C++ 类的隐式转换与explicit](https://blog.csdn.net/wysnkyd/article/details/82712289)，其中"反向转换(转换函数)"

#### 示例

```cpp
class Per {
    int i;
    public:
    Per(int i)
    {
        i = i;
        cout << __FUNCTION__ << " i: "  << i << endl;
    }
};

class Person {
public:
    Person() {
        cout << "no param constructor!" << endl;
        mAge = 0;
    }
    Person(int age) {
        cout << "1 param constructor!" << endl;
        mAge = age;
    }
    Person(int age,int b) {
        cout << "2 param constructor!" << endl;
        mAge = age;
    }
    ~Person() {
        cout << "析构函数已调用" << endl;
    }
    // 转换函数
    operator int() {
        return mAge;
    }
    // 转换函数，int到Per类的转换函数
    operator Per() {
        return mAge;
    }
private:
    int mAge;
};

int main(int argc, const char *argv[])
{
    Person p1 = 100;     //等号右边转换为对象，调用有参构造，发生隐式转换
    Person p2 =(100,100);//这个不会调用两个参数的构造函数，不存在这种用法
    int a = p1;          //因为有operator int() {return mAge;}，此处转换函数成功转换
    cout << "a: " << a << endl;

    cout << "============" << endl;
    //类和类之间也可以转换，
    // 此处需要Per类中存在int到Per类的构造函数，且Person中定义了转换函数
    Per p = p1;
    return 0;
}
```

编译运行：

```sh
[➜ /home/xd/workspace/src ]$ g++ test_implicit_conversion.cpp -std=c++11
[➜ /home/xd/workspace/src ]$ ./a.out
1 param constructor!
1 param constructor!
a: 100
============
Per i: 100
析构函数已调用
析构函数已调用
```

* 构造函数或者转换函数添加explicit，则不允许隐式转换
    - `explicit Person(int age){...}` 编译报错：`错误：请求从‘int’转换到非标量类型‘Person’`
    - `explicit operator int() {...}` 编译报错：`不能在初始化时将‘Person’转换为‘int’`

## 显式类型转换

* 显式类型转换
    - C风格的强制转换 `type val = (type)(expression);`
    - C++命名的强制类型转换，C++提供了4个命名的强制类型转换
        + `static_cast<type>(expression);` 很像 C 语言中的旧式类型转换，是非安全的
        + `dynamic_cast` 主要用来在继承体系中的安全向下转型,是实现多态的一种方式。
        + `const_cast` 可去除对象的常量性（const）还可以去除对象的易变性（volatile）
        + `reinterpret_cast` 用来执行低级转型，如将执行一个 int 的指针强转为 int
            * 其转换结果与编译平台息息相关，不具有可移植性，因此在一般的代码中不常见到它。