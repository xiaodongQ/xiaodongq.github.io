---
layout: post
title: LeetCode刷题学习（五） -- 字符串
categories: LeetCode
tags: LeetCode 数据结构与算法
---

* content
{:toc}

LeetCode刷题学习记录，字符串篇。



## 1. 344.反转字符串

[344. Reverse String](https://leetcode.cn/problems/reverse-string/)

要求原地反转字符串，只借助`O(1)`的额外空间。

### 1.1. 思路和解法

双指针。

```cpp
class Solution {
public:
    void reverseString(vector<char>& s) {
        int left = 0;
        int right = s.size() - 1;
        // 保持区间的开闭一致
        char tmp;
        while (left <= right) {
            tmp = s[left];
            s[left] = s[right];
            s[right] = tmp;
            left++;
            right--;
        }
    }
};
```

参考链接中，还提供了通过`位运算`（异或）进行交换的实现方式。

```cpp
s[i] ^= s[j]; // 两数的异或结果
s[j] ^= s[i]; // 由于异或运算可逆，得到原来的s[i]
s[i] ^= s[j]; // 得到 s[j]
```

for循环更简洁一点：

```cpp
void reverseString(vector<char>& s) {
    // for循环更简洁
    char tmp;
    for (int left = 0, right = s.size() - 1; left < s.size()/2; left++, right--) {
        tmp = s[left];
        s[left] = s[right];
        s[right] = tmp;
    }
}
```

## 2. 541.反转字符串II

[541. Reverse String II](https://leetcode.cn/problems/reverse-string-ii/description/)

给定整数k，每2k个字符进行处理，只反转每2k中的前k个字符。

如果剩余字符少于 k 个，则将剩余字符全部反转，如：`abcdefgh`，给定3，则变为`cba def hg`

如果剩余字符小于 2k 但大于或等于 k 个，则反转前 k 个字符，其余字符保持原样，如：`abcde`，给定3，则变为`cba de`

### 2.1. 思路和解法

比 344.反转字符串 复杂一些。

思路：每次移动2k，再单独看2k内的区间怎么处理。

```cpp
class Solution {
public:
    string reverseStr(string s, int k) {
        // 每次移动2k
        for (int i = 0; i < s.size(); i += 2*k) {
            // 剩余字符少于 k 个，反转剩下所有字符
            if (s.size() - i < k) {
                // 这里用了STL的reverse算法（若不是直接的解题关键，也可以用库函数）
                reverse(s.begin() + i, s.end());
            } else {
                // 每k个进行反转
                reverse(s.begin() + i, s.begin() + i + k);
            }
        }

        return s;
    }
};
```

概率上还是>=k会概率高一些，可以放前面（不过if...else分支无所谓，如果还有其他情况则可将概率高的放前面以减少判断次数）

```cpp
if (s.size() - i >= k) {
    // 每k个进行反转
    reverse(s.begin() + i, s.begin() + i + k);
} else {
    // 反转剩余字符
    reverse(s.begin() + i, s.end());
}
```

`reverse`算法也可调整成自己实现，`void my_reverse(string &s, int start, int end)`，其中实现即"344.反转字符串"对应解法。

## 3. 替换数字

非原题：[替换数字](https://www.programmercarl.com/kamacoder/0054.%E6%9B%BF%E6%8D%A2%E6%95%B0%E5%AD%97.html)

给定一个字符串 s，它包含小写字母和数字字符，请编写一个函数，将字符串中的字母字符保持不变，而将每个数字字符替换为number。

示例："a1b2c3"，函数应该将其转换为 "anumberbnumbercnumber"

### 3.1. 思路和解法

先遍历数组获取 数字字符 的数量，然后扩容字符串大小，从后往前填充（原位置`idx1--`，新位置`idx2--`）

## 4. 参考

1、[代码随想录 -- 字符串](https://www.programmercarl.com/0344.%E5%8F%8D%E8%BD%AC%E5%AD%97%E7%AC%A6%E4%B8%B2.html)

2、[LeetCode中文站](https://leetcode.cn/)
