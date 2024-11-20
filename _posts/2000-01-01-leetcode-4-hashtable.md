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

## 5. 1.两数之和

[1. Two Sum](https://leetcode.cn/problems/two-sum/description/)

### 5.1. 思路和解法

用`unordered_map<int,int>`来记录数组成员需要的配对数字，以及数组成员的下标，继续遍历数组，并从map里找之前是否需要当前数组值。

```cpp
class Solution {
public:
    vector<int> twoSum(vector<int>& nums, int target) {
        // 由于要返回下标，用unordered_map<int, int>记录<target-值, 下标>
        unordered_map<int, int> tmp;
        for (int i = 0; i < nums.size(); i++) {
            // 看当前成员是否为之前需要的值
            if (tmp.find(nums[i]) != tmp.end()) {
                return vector<int>{tmp[ nums[i] ], i};
            }
            // 记录当前成员需要哪个值就能凑成target，即 target-num 和 它的下标
            tmp[ target-nums[i] ] = i;
        }
        return vector<int>{};
    }
};
```

## 6. 454.四数相加II

[454. 4Sum II](https://leetcode.cn/problems/4sum-ii/description/)

给定4个数组，数组各取一个元素组成四元组，满足元组求和为0的元组有多少个

### 6.1. 思路和解法

思路：前2个数组遍历求和sum1并保存在map里`sum1:出现次数`，后2个数组遍历求和sum2并找`-sum2`是否出现在map中，在则value对应次数累加

```cpp
class Solution {
public:
    int fourSumCount(vector<int>& nums1, vector<int>& nums2, vector<int>& nums3, vector<int>& nums4) {
        int result = 0;
        // 前2个数组遍历求和并保存
        unordered_map<int, int> sum1_map;
        for (int n1 : nums1) {
            for (int n2 : nums2) {
                sum1_map[n1+n2]++;
            }
        }
        // 后2个数组遍历求和
        for (int n3 : nums3) {
            for (int n4 : nums4) {
                // 找 -(n3+n4)
                if (sum1_map.find(-n3-n4) != sum1_map.end()) {
                    result += sum1_map[-n3-n4];
                }
            }
        }
        return result;
    }
};
```

## 7. 383.赎金信

[383. Ransom Note](https://leetcode.cn/problems/ransom-note/)

给定一个赎金信 (ransom) 字符串和一个杂志(magazine)字符串，判断第一个字符串 ransom 能不能由第二个字符串 magazines 里面的字符构成。字母都是英文小写。

为了不暴露赎金信字迹，要从杂志上搜索各个需要的字母。杂志字符串中的每个字符只能在赎金信字符串中使用一次。

### 7.1. 思路和解法

由于都是英文字母小写，通过数组将字符缓存起来，作为哈希结构（`map`需要维护红黑树或者哈希表，且需要哈希计算，时间和空间上该场景数组更优）。

`赎金信`的字符要从`杂志(magazine)`字符中查找，所以缓存`杂志(magazine)`

```cpp
class Solution {
public:
    bool canConstruct(string ransomNote, string magazine) {
        int letters[26] = {0};

        // 小优化，如果ransomNote长度比magazine长度大，则肯定不满足
        if (ransomNote.size() > magazine.size()) {
            return false;
        }

        for (char c : magazine) {
            letters[c - 'a'] ++;
        }

        // 检查赎金信ransomNote中字符是否都能在magazine中，每个字符最多一次
        for (char c : ransomNote) {
            letters[c - 'a']--;
            // 如果出现字符为负，则说明magazine里没有足够的字符能覆盖ransomNote
            if (letters[c - 'a'] < 0) {
                return false;
            }
        }
        return true;
    }
};
```

## 8. 15.三数之和

[15. 3Sum](https://leetcode.cn/problems/3sum/description/)

给定1个数组nums，返回所有满足`nums[i]+nums[j]+nums[k]==0`的3元组，i、j、k各不相等，且要求**三元组不重复**

### 8.1. 思路和解法

#### 8.1.1. 哈希法case1（超时）

哈希法类似两数之和，到map里找`-(num1+num2)`

vector的set集合，借助GPT糊了一个`VecHash`和`VecEqual`，但是超时了：310/313 cases passed (N/A)

```cpp
// 解法超时
class Solution {
public:
    // 自定义哈希函数
    struct VecHash {
        size_t operator()(const std::vector<int>& v) const {
            std::hash<int> hasher;
            size_t seed = 0;
            for (int i : v) {
                // 0x9e3779b9是一个常数，用于增加哈希值的随机性和分散度
                seed ^= hasher(i) + 0x9e3779b9 + (seed<<6) + (seed>>2);
            }
            return seed;
        }
    };
    // 自定义比较函数，用于确保向量相等时哈希值也相同
    struct VecEqual {
        bool operator()(const std::vector<int>& v1, const std::vector<int>& v2) const {
            return v1 == v2;
        }
    };

    vector<vector<int>> threeSum(vector<int>& nums) {
        vector<vector<int>> result;
        // 外层遍历，里层在剩下的成员里找2数之和
        for (int i = 0; i < nums.size(); i++) {
            int sum = -nums[i];
            unordered_map<int, int> tmp_map;
            for (int j = i+1; j < nums.size(); j++) {
                if (tmp_map.find(nums[j]) != tmp_map.end()) {
                    // 满足求和为0，记录成员
                    result.push_back(vector<int>{nums[i], nums[tmp_map[nums[j]]], nums[j]});
                } else {
                    tmp_map[sum - nums[j]] = j;
                }
            }
        }

        // 三值排序
        for (int i = 0; i < result.size(); i++) {
            sort(result[i].begin(), result[i].end());
        }
        // 自定义去重
        unordered_set<vector<int>, VecHash, VecEqual> tmp_set(result.begin(), result.end());
        // unordered_set和vector转换
        vector<vector<int>> result_nums(tmp_set.begin(), tmp_set.end());

        return result_nums;
    }
};
```

#### 8.1.2. 哈希法case2

上面是排序放在后面并遍历了所有记录，这里优化成：先对数组排序，并对第一个数字进行**去重**处理

```cpp
class Solution {
public:
    // 自定义哈希函数
    struct VecHash {
        size_t operator()(const std::vector<int>& v) const {
            std::hash<int> hasher;
            size_t seed = 0;
            for (int i : v) {
                seed ^= hasher(i) + 0x9e3779b9 + (seed<<6) + (seed>>2);
            }
            return seed;
        }
    };
    // 自定义比较函数，用于确保向量相等时哈希值也相同
    struct VecEqual {
        bool operator()(const std::vector<int>& v1, const std::vector<int>& v2) const {
            return v1 == v2;
        }
    };

    vector<vector<int>> threeSum(vector<int>& nums) {
        vector<vector<int>> result;
        // 先对vector排序，便于去重
        sort(nums.begin(), nums.end());
        for( int i = 0; i < nums.size() - 2; i++) {
            // 去重处理，前面已经处理过该值的情况了
            if (i > 0 && nums[i] == nums[i-1]) {
                continue;
            }
            int sum = -nums[i];
            // 处理两数之和
            unordered_map<int, int> tmp_map;
            for (int j = i+1; j < nums.size(); j++) {
                if (tmp_map.find(nums[j]) != tmp_map.end()) {
                    // 满足三数之和为0，按大小顺序添加记录
                    result.push_back(vector<int>{nums[i], nums[ tmp_map[nums[j]] ], nums[j]});
                } else {
                    tmp_map[sum - nums[j]] = j;
                }
            }
        }
        // 当前结果还需要去重处理
        unordered_set<vector<int>, VecHash, VecEqual> tmp_set(result.begin(), result.end());
        // unordered_set再转换为vector
        vector<vector<int>> result_nums(tmp_set.begin(), tmp_set.end());

        return result_nums;
    }
};
```

这次通过了校验，不过可看到耗时还是较高的，只击败4.99%的提交，而且还借助了STL本身提供的构造转换：

```sh
313/313 cases passed (2344 ms)
Your runtime beats 4.99 % of cpp submissions
Your memory usage beats 5.02 % of cpp submissions (462.7 MB)
```

#### 8.1.3. 哈希法case3

看了下代码随想录里的哈希法，自己的思路有点粗糙：

1. 处理两数之和时，可不需map来记录下标，直接用set取数值组装结果记录即可。
2. 同时第2、第3个数需要进一步去重处理：`nums[j]`和`[j-1]`、`[j-2]`相同则跳过，否则结果还是会有重复，需要单独处理

case1和case2里用了自定义`Hash`和`KeyEqual`增加了复杂度：

```cpp
template<
    class Key,
    class Hash = std::hash<Key>,
    class KeyEqual = std::equal_to<Key>,
    class Allocator = std::allocator<Key>
> class unordered_set;
```

调整：

提交时细节很多，很容易出错：`j > i+2`而不是`j>2`，不能忘记`tmp_set.erase(nums[j])`且不是移除`sum - nums[j]`

```cpp
vector<vector<int>> threeSum(vector<int>& nums) {
        vector<vector<int>> result;
        // 先对vector排序，便于去重
        sort(nums.begin(), nums.end());
        for( int i = 0; i < nums.size() - 2; i++) {
            // 去重处理，前面已经处理过该值的情况了
            if (i > 0 && nums[i] == nums[i-1]) {
                continue;
            }
            int sum = -nums[i];
            // 处理两数之和
            // 只要用set记录需要的配对值即可，获取到之后就可以移除掉
            unordered_set<int> tmp_set;
            for (int j = i+1; j < nums.size(); j++) {
                // 去重
                if (j > i+2 && nums[j] == nums[j-1] && nums[j] == nums[j-2]) {
                    continue;
                }

                if (tmp_set.find(nums[j]) != tmp_set.end()) {
                    // 满足三数之和为0，直接组装结果，第2个数（a/b/c中的b），用0-a-c即可
                    result.push_back( vector<int>{nums[i], -nums[i]-nums[j], nums[j]} );
                    tmp_set.erase(nums[j]);
                } else {
                    tmp_set.insert(sum - nums[j]);
                }
            }
        }
        
        return result;
    }
```

提交结果如下，还是比较低效的：

```sh
313/313 cases passed (2571 ms)
Your runtime beats 5.02 % of cpp submissions
Your memory usage beats 5.02 % of cpp submissions (461 MB)
```

#### 8.1.4. 双指针

本题使用双指针法更高效。

思路：从头遍历元素(`i`)，定义双指针，left在`i+1`位置、right在数组尾。若求和`>0`则right左移，`<0`则left右动，若`=0`则做好去重并left和right收缩；

注意点：第一层遍历时，也需要做好去重，后续左右指针移动时再进行第2道去重。

```cpp
class Solution {
public:
    vector<vector<int>> threeSum(vector<int>& nums) {
        vector<vector<int>> result;
        // 记住先得排序
        sort(nums.begin(), nums.end());
        for (int i = 0; i < nums.size(); i++) {
            // 这里要做一道去重
            if (i > 0 && nums[i] == nums[i-1]) {
                continue;
            }

            int left = i+1;
            int right = nums.size() - 1;
            while (left < right) {
                if (nums[i] + nums[left] + nums[right] > 0) {
                    right--;
                } else if (nums[i] + nums[left] + nums[right] < 0) {
                    left++;
                } else {
                    // 满足求和为0
                    result.push_back( vector<int>{nums[i], nums[left], nums[right]} );
                    // 左右都去重处理
                    while (right > left && nums[left] == nums[left+1]) {
                        left++;
                    }
                    while (right > left && nums[right] == nums[right-1]) {
                        right--;
                    }
                    // 由于求和为0，左右一增一减才可能继续求和为0
                    left++;
                    right--;
                }
            }
        }
        return result;
    }
};
```

可看到现在的速度就很可观了：从`2571 ms`到`47 ms`

```sh
313/313 cases passed (47 ms)
Your runtime beats 90.85 % of cpp submissions
Your memory usage beats 30.56 % of cpp submissions (26.9 MB)
```

## 9. 参考

1、[代码随想录 -- 哈希表](https://www.programmercarl.com/%E5%93%88%E5%B8%8C%E8%A1%A8%E7%90%86%E8%AE%BA%E5%9F%BA%E7%A1%80.html)

2、[数据结构与算法之美 -- 散列表](https://time.geekbang.org/column/article/64586)

3、[LeetCode中文站](https://leetcode.cn/)
