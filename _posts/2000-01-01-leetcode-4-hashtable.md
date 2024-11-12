---
layout: post
title: LeetCode刷题学习（四） -- 哈希表
categories: LeetCode
tags: LeetCode 数据结构与算法
---

* content
{:toc}

LeetCode刷题学习记录，哈希表篇。



## 1. 基础

`哈希表`（Hash Table），也称`散列表`。

散列冲突/哈希碰撞（hash collision）常用的两类解决方法：

* `链表法`（chaining）/`拉链法`：，发生冲突的元素都存储在链表中
    * 链表法更常用，相比开放寻址法简单很多。每个“桶（bucket）”或者“槽（slot）”会对应一条链表
    * 基于链表的散列冲突处理方法比较适合存储大对象、大数据量的散列表，而且，比起开放寻址法，它更加灵活，支持更多的优化策略，比如用`红黑树`、`跳表`代替链表。
* `开放寻址法`（open addressing）：出现了散列冲突，就重新探测一个空闲位置，将其插入
    * 比如简单的 `线性探测法（Linear Probing）`：哈希冲突时，从当前哈希值位置开始，依次往后查找，看是否有空闲位置，直到找到为止
        * 查找时，如果哈希值下标处的键值和要查找元素相等，则说明要找的元素；否则就顺序往后依次查找。如果遍历到数组中的空闲位置，还没有找到，就说明要查找的元素并没有在散列表中
        * 线性探测法其实存在很大问题：当散列表中插入的数据越来越多时，散列冲突发生的可能性就会越来越大，空闲位置会越来越少，线性探测的时间就会越来越久。
    * 优点：不像链表法，其可以有效地利用 CPU 缓存加快查询速度
        * 当数据量比较小、装载因子小的时候，适合采用开放寻址法。比如Java中的`ThreadLocalMap`就是使用开放寻址法解决散列冲突
    * 对于开放寻址冲突解决方法，除了线性探测方法之外，还有另外两种比较经典的探测方法，二次探测（Quadratic probing）和双重散列（Double hashing）。
    * 一般会尽可能保证散列表中有一定比例的空闲槽位，用`装载因子（load factor）`来表示空位的多少（装载因子=填入表中的元素个数/散列表的长度）

`双向链表`和`散列表`经常会一起使用，用以加快涉及查找的操作。应用场景比如：Redis有序集合、Java的LinkedHashMap。

常见的几种哈希结构：

* 数组：哈希值作为下标索引，`O(1)`查找
* set：集合
    * `std::set`，底层实现为`红黑树`，有序、不可重复、数值不可改，增删查均为`O(logn)`
    * `std::multiset`，底层实现为`红黑树`，有序、可重复、数值不可改，增删查均为`O(logn)`
    * `std::unordered_set`，底层实现为`哈希表`，无序、不可重复、数值不可改，增删查均为`O(1)`
* map：映射
    * `std::map`，底层实现为`红黑树`，有序，key不可重复、key不可改、增删查均为`O(logn)`
    * `std::multimap`，底层实现为`红黑树`，有序，key可重复、key不可改、增删查均为`O(logn)`
    * `std::unordered_map`，底层实现为`哈希表`，无序、key不可重复、key不可改、增删查均为`O(1)`

应用场景：

* 当要使用集合来解决哈希问题的时候，优先使用`unordered_set`，因为它的查询和增删效率是最优的
* 如果需要集合是有序的，那么就用`set`，如果要求不仅有序还要有重复数据的话，那么就用`multiset`
* 当要快速判断一个元素是否出现集合里的时候，考虑`哈希法`，用空间换时间

## 2. 242.有效的字母异位词

[242. Valid Anagram](https://leetcode.cn/problems/valid-anagram/description/)

### 2.1. 思路和解法

字母异位词：相同字母，顺序不一定相同

题目约束了两个字符串都是小写的英文字母，通过一个数组`int[26]`，标识`字母-'a'`对应索引的出现次数，两个字符串一加一减最后再对比各索引次数是否恢复为0

```cpp
class Solution {
public:
    bool isAnagram(string s, string t) {
        int arr[26] = {0};
        for (int i=0; i < s.length(); i++) {
            arr[s[i] - 'a']++;
        }
        for (int i=0; i < t.length(); i++) {
            arr[t[i] - 'a']--;
        }
        for (int i=0; i < 26; i++) {
            if (arr[i] != 0) {
                return false;
            }
        }
        return true;
    }
};
```

时间复杂度：`O(n)`  
空间复杂度：由于借助常量级长度数组，`O(1)`

## 3. 349.两个数组的交集

[349. Intersection of Two Arrays](https://leetcode.cn/problems/intersection-of-two-arrays/)

### 3.1. 思路和解法

结果中相同元素只需要一次，可借助`unordered_set`记录第一个数组各成员，并遍历第二个数组跟集合匹配，有记录则加入返回集合

```cpp
class Solution {
public:
    vector<int> intersection(vector<int>& nums1, vector<int>& nums2) {
        // 结果还是利用set来去重
        unordered_set<int> result_set;
        // 通过构造函数进行vector到orderend_set的转换(C++11起)
        unordered_set<int> memb(nums1.begin(), nums1.end());
        for (int i = 0; i < nums2.size(); i++) {
            if (memb.end() != memb.find(nums2[i])) {
                result_set.insert(nums2[i]);
            }
        }

        // 迭代器构造进行转换
        return vector<int>(result_set.begin(), result_set.end());
    }
};
```

## 4. 参考

1、[代码随想录 -- 链表篇](https://www.programmercarl.com/%E9%93%BE%E8%A1%A8%E7%90%86%E8%AE%BA%E5%9F%BA%E7%A1%80.html)

2、[数据结构与算法之美 -- 散列表](https://time.geekbang.org/column/article/64586)

3、[LeetCode中文站](https://leetcode.cn/)
