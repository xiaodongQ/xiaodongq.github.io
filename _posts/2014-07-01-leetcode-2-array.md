---
layout: post
title: LeetCode刷题学习（二） -- 数组篇
categories: LeetCode
tags: LeetCode 数据结构与算法
---

* content
{:toc}

LeetCode刷题学习记录，数组篇。



## 1. 704.二分查找

### 1.1. 题目

```
给定一个 n 个元素有序的（升序）整型数组 nums 和一个目标值 target  ，写一个函数搜索 nums 中的 target，如果目标值存在返回下标，否则返回 -1。


示例 1:

输入: nums = [-1,0,3,5,9,12], target = 9
输出: 4
解释: 9 出现在 nums 中并且下标为 4
示例 2:

输入: nums = [-1,0,3,5,9,12], target = 2
输出: -1
解释: 2 不存在 nums 中因此返回 -1
 

提示：

你可以假设 nums 中的所有元素是不重复的。
n 将在 [1, 10000]之间。
nums 的每个元素都将在 [-9999, 9999]之间。
```

### 1.2. 思路和解法

二分查找有两种常见写法。循环条件和判断条件容易搞错，记住遵循 `循环不变量规则`（循环过程中每次处理边界时，坚持根据区间的定义来操作）。

* 左闭右闭区间 `[]`
    * 区间：`left=0; right=size()-1`
    * 循环条件：`while(left <= right);`，`left == right`是有意义的，所以用`<=`
    * 区间更新：
        * 中间值更大时查找左区间，`right=middle-1`，即`[left, middle-1]`
        * 中间值更小时查找右区间，`left=middle+1`，因为当前`middle`值肯定不满足`arr[middle] == target`，即`[middle+1, right]`
* 左闭右开区间 `[)`
    * 区间：`left=0; right=size()`
    * 循环条件：`while(left < right)`，由于右开区间时`left == right`没有意义，所以用`<`
    * 区间更新：
        * 中间值更大时找左区间，`right=middle`，因为右开区间不会去比较`arr[middle]`，即`[left, middle)`
        * 中间值更小时找右区间，`left=middle+1`，即`[middle + 1, right)`

左闭右闭区间：

```cpp
int search(vector<int>& nums, int target) {
    int left = 0;
    int right = nums.size() - 1;
    // left == right是有意义的，所以使用 <=
    while (left <= right) {
        // 避免溢出
        int mid = left + (right-left)/2;
        if (target == nums[mid]) {
            return mid;
        }
        // [left, mid-1]
        if (nums[mid] > target) {
            right = mid - 1;
        }else{
            // [mid+1, right]
            left = mid + 1;
        }
    }
    return -1;
}
```

```cpp
// 左闭右开区间，[)
int search(vector<int>& nums, int target) {
    int left = 0;
    int right = nums.size();
    while (left < right) {
        int mid = left + (right-left)/2;
        if (nums[mid] == target) {
            return mid;
        }
        // 左区间 [)
        if (nums[mid] > target) {
            right = mid;
        } else {
            // 右区间
            left = mid + 1;
        }
    }

    return -1;
}
```

### 1.3. STL中的二分查找


## 2. 参考

1、[代码随想录 -- 数组篇](https://www.programmercarl.com/0704.%E4%BA%8C%E5%88%86%E6%9F%A5%E6%89%BE.html)
