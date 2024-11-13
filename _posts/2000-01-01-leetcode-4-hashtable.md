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

## 4. 202.快乐数

[202. Happy Number](https://leetcode.cn/problems/happy-number/)

快乐数：正整数，每次取每位的平方和，若最后平方和为1则为快乐数；若最后无限循环则非快乐数

比如 19： `1^2+9^2 = 82` -> `8^2+2^2 = 68` -> `6^2+8^2 = 100` -> `1^2+0+0 = 1`，则19为快乐数

比如2: 2^2=4 -> 4^2=16 -> 1+6^2=37 -> 9+49=58 -> 25+64=89 -> 64+81=145 -> 1+16+25=42 ...，非快乐数（怎么证明？）

### 4.1. 思路和解法

无限循环 则说明肯定会出现重复的和，要不总会穷举到10、100、1000之类的数。

可通过`set`记录之前的平方和，若新的平方和和`set`元素重复则非快乐数；若出现平方和为1则可提前退出

```cpp
class Solution {
public:
    bool isHappy(int n) {
        unordered_set<int> sums;
        int num = n;
        int sum = 0;
        int bit = 0;
        while (true) {
            // 计算平方和
            while (num > 0) {
                bit = num % 10;
                sum += bit * bit;
                num = num / 10;
            }
            if (sum == 1) {
                return true;
            }

            // 找到重复的平方和，说明会无限循环，非快乐数
            if (sums.find(sum) != sums.end()) {
                return false;
            }
            sums.insert(sum);
            // 下一轮
            num = sum;
            sum = 0;
        }
    }
};
```

时间复杂度分析：`O(log n)`

* 单个数n的平方和，复杂度为`O(logn)`，因为数字 n 的位数大约是 `log n`（以10为底）；
* 由于不断地用新的平方和替换原来的数字，实际的输入大小会逐渐减小，直到找到答案或进入循环为止。
    * 为什么实际输入大小会逐渐减小
    * 1、理解平方和的最大值限制：
        * 对于一个 `d` 位数，最大的数字是`10^d - 1`，最大平方和为`9^2 * d = 81d`
        * 比如对于一个三位数，最大可能的平方和为 `81*3 = 243`，比`999`小得多
    * 2、数值缩小的趋势：
        * 随着数字变大，虽然它的位数增加，但平方和的增长速度远远低于数字本身的增长速度。这意味着，即使对于较大的数字，经过几次转换后，平方和也会显著减小。
* 时间复杂度可以粗略地认为是 `O(k log n)`，其中 k 是迭代次数，而 `log n` 表示每次迭代中的操作复杂度。在实际情况中，k 通常不会非常大，因为非快乐数很快就会陷入已知的循环中。

## 5. 两数之和

[1. Two Sum](https://leetcode.cn/problems/two-sum/description/)

### 5.1. 思路和解法



## 6. 参考

1、[代码随想录 -- 链表篇](https://www.programmercarl.com/%E9%93%BE%E8%A1%A8%E7%90%86%E8%AE%BA%E5%9F%BA%E7%A1%80.html)

2、[数据结构与算法之美 -- 散列表](https://time.geekbang.org/column/article/64586)

3、[LeetCode中文站](https://leetcode.cn/)
