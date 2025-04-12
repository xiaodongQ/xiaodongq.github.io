---
layout: _post
title: STL容器之容器基本操作和删除成员需注意的陷阱
categories: C/C++
tags: STL
---

* content
{:toc}

STL容器之容器基本操作和删除成员需注意的陷阱



## vector

### 查找

vector没有find()成员函数，其find是依靠algorithm来实现的

```cpp
#include <algorithm>
vector<int>::iterator it = find(vec.begin(), vec.end(), 6);
```

### 删除

**使用`vector.erase(迭代器)`删除成员，如果是循环注意指针陷阱**

注意：remove不是vector的成员函数，而是<algorithm>中实现

`remove(v.begin(), v.end(), 99);`

参考：
[STL Vector remove()和erase()的使用](https://blog.csdn.net/yockie/article/details/7859330)

remove只是将成员前移，原来的位置的值还在。 e.g. 9 10 8 7, remove 10则变成9 8 7 7

从一个容器中remove元素不会改变容器中元素的个数

如果你真的要删除东西的话，你应该在remove后面接上erase。

v.erase(remove(v.begin(), v.end(), 99), v.end());  // 真的删除所有等于99的元素

把remove的返回值作为erase区间形式第一个参数传递很常见，这是个惯用法。事实上，remove和erase是亲密联盟，这两个整合到list成员函数remove中。这是STL中唯一名叫remove又能从容器中除去元素的函数：

>对于list，调用remove成员函数比应用erase-remove惯用法更高效

```cpp
list<int> li;   // 建立一个list
    // 放一些值进去
li.remove(99);   // 除去所有等于99的元素：
    // 真的删除元素，
    // 所以它的大小可能改变了
```

## list

```cpp
遍历，使用迭代器，不能使用下标
iter = list1.begin(); != end(); iter++

List.push_back(info);  添加到末尾
List.pop_back();       删除末尾元素
List.pop_front();      删除第一个元素

iter = List.insert(iter, info);  插入后iter指向新插入的元素
iter = std::find(List.begin(), List.end(), info);  查找
```

## map

迭代器遍历

```cpp

//错误
for(iter=begin; ...; iter++)
{
    erase(iter)
}
//错误
for(iter=begin; ...; )
{
    erase(iter)
    iter++
}

//正确
for(iter=begin; ...; )
{
    erase(iter++)
}

同:
temp = iter;
iter++;
erase(temp);

//分支
for(vector<int>::iterator iter=veci.begin(); iter!=veci.end(); )
{
    if(*iter == 3)
        iter = veci.erase(iter);
    else
        iter ++ ;
}
```

### 新增记录

```cpp
(1) map的变量名[key] = value;
(2) PeopleMap.insert(map<int, string>::value_type(111, “zhang wu” ));
(3) PeopleMap.insert(pair<int, string>(222, "zhang liu"));      //常用的
(4) PeopleMap.insert(make_pair<int, string>(222, "zhang liu")); //常用的
```

