---
layout: post
title: LeetCode之1_TwoSum
categories: LeetCode
tags: LeetCode
---

* content
{:toc}

LeetCode之1_TwoSum



## 题目

给定一个整数数组 nums 和一个目标值 target，请你在该数组中找出和为目标值的那 两个 整数，并返回他们的数组下标。

你可以假设每种输入只会对应一个答案。但是，你不能重复利用这个数组中同样的元素。

示例:

给定 nums = [2, 7, 11, 15], target = 9

因为 nums[0] + nums[1] = 2 + 7 = 9
所以返回 [0, 1]

来源：力扣（LeetCode）
链接：https://leetcode-cn.com/problems/two-sum
著作权归领扣网络所有。商业转载请联系官方授权，非商业转载请注明出处。

## 解答

### C++

```cpp
class Solution {
public:
    // 结果：29 / 29 个通过测试用例, 执行用时:368 ms, cpp中>16.14%; 内存消耗:9.3MB, cpp中>75.78%
    // 时间：O(n^2) 空间：O(1)
    vector<int> twoSum(vector<int>& numkus, int target) {
        for(int iIndex1 = 0; iIndex1 < numkus.size()-1; iIndex1++)
        {
            for (int iIndex2 = iIndex1+1; iIndex2 < numkus.size(); iIndex2++)
            {
                if (numkus[iIndex1] + numkus[iIndex2] == target)
                {
                    // int arrRes[] = {iIndex1, iIndex2};
                    // return vector<int>(arrRes, arrRes + 2); // 首地址和尾地址， [first, last)
                    return {iIndex1, iIndex2}; // {}方式构造vector
                }
            }
        }
        return {};
    }

    // 遍历vecotr，把 target - vector[i] 放入map(key:target-本次成员,value:本次下标)，每次遍历成员时找map里有没有和本次遍历配对之和满足target的元素
    // 如果有相同元素的值，map的key重复，此情况暂不考虑
    // 参考：[twoSum.cpp](https://github.com/haoel/leetcode/blob/master/algorithms/cpp/twoSum/twoSum.cpp)
    // 对应git记录 e052ec0 结果：执行用时:16 ms, cpp中>77.55%; 内存消耗:10.6MB, cpp中>10.02%
    // 结果：执行用时:12 ms, cpp中>91.26%; 内存消耗:9.9MB, cpp中>44.19%，每次执行消耗依赖用例集(并不说明优于twoSum3)
    // 时间：O(n) 空间：O(n)
    vector<int> twoSum2(vector<int>& numkus, int target) {
        unordered_map<int, int> mapNum;
        for(int iIndex1 = 0; iIndex1 < numkus.size(); iIndex1++)
        {
            if (mapNum.find(numkus[iIndex1]) == mapNum.end())
            {
                // 没找到则把 target-numkus[iIndex1] 存起来放map中，并记录 numkus[iIndex1] 的下标
                mapNum[target - numkus[iIndex1]] = iIndex1;
            }
            else
            {
                // map中找到了符合要求的记录，则说明其配对的另一个元素的下标也知道了，即key对应的value
                // 注意key是本次索引对应的值
                return {mapNum[numkus[iIndex1]], iIndex1};
            }
        }
        return {};
    }

    // 或者存本次元素的值(个人倾向于该种理解方式，本次遍历没找到符合条件的就先缓存起来)

    /* 本注释块中结果不对应当前代码，对应git记录 e052ec0
     结果：执行用时:12 ms, cpp中>91.32%; 内存消耗:10.4MB, cpp中>未记下来
     第二次执行结果：执行用时:16 ms, cpp中>77.55%; 内存消耗:10.7MB, cpp中>7.34% */
    // 可以看到，leetcode系统中的用例每次不一定都是一样的，相同代码根据每次执行情况的消耗有区别
    // 结果：执行用时:16 ms, cpp中>77.45%; 内存消耗:9.9MB, cpp中>44.03%
    // 时间：O(n) 空间：O(n)
    vector<int> twoSum3(vector<int>& numkus, int target) {
        unordered_map<int, int> mapNum;
        for(int iIndex1 = 0; iIndex1 < numkus.size(); iIndex1++)
        {
            if (mapNum.find(target - numkus[iIndex1]) == mapNum.end())
            {
                // 没找到则把 本次numkus[iIndex1] 存起来放map中，并记录 numkus[iIndex1] 的下标
                mapNum[numkus[iIndex1]] = iIndex1;
            }
            else
            {
                // map中找到了符合要求的记录，则说明其配对的另一个元素的下标也知道了，即key对应的value
                // 注意key是成员的值
                return {mapNum[target - numkus[iIndex1]], iIndex1};
            }
        }
        return {};
    }
};
```

### Golang

```golang
// 结果：执行用时:4 ms, golang中>97.39%; 内存消耗:3.7MB, golang中>46.28%
// 时间：O(n) 空间：O(n)
func twoSum(nums []int, target int) []int {
    mapInt := make(map[int]int)
    for index, v := range nums {
        iNum, ok := mapInt[target-v]
        if ok {
            return []int{iNum, index}
        }
        mapInt[v] = index
    }
    return []int{}
}
```

## 思考

* 对比C++和Go的时间和效率，有点疑问
    - C++
        + 执行用时:16 ms, cpp中>77.45%; 内存消耗:9.9MB, cpp中>44.03%
        + 时间：O(n) 空间：O(n)
    - Go
        + 执行用时:4 ms, golang中>97.39%; 内存消耗:3.7MB, golang中>46.28%
        + 时间：O(n) 空间：O(n)

看提交记录，Go的执行用时只有4ms，比C++快了不少，内存也小很多，有些疑问，知道比较两个东西需要看适用场景，但是这个场景下的差别以现在的知识储备还是留下了一个大大的问号。

* 怀疑原因(不是很有根据的怀疑)：
    - 逻辑里主要是数组遍历和map的查找两块比较耗时，C++的unordered_map和Go的map底层也是一个hash表，两者的hash实现是否有hash冲突，是否经常有rehash，下面示例里问的perl/C++/Golang的hash，为什么C++比较慢，具体hash内部先不作深入，数据结构还要再加强
    - 里面使用valgrind --tool=cachegrind工具分析CPU的缓存，以后也可以了解一下 [Performance of hash table, why is C++ the slowest? Jens' answer](https://stackoverflow.com/questions/33950565/performance-of-hash-table-why-is-c-the-slowest)

查找关于Go的性能问题，看到这篇文章里关于一个编程比赛用Go实现的回答，里面的Go实现觉得可以学习一下(进去看不少东西不懂)：

[为什么 Go 语言的性能还不如 Java？ - 冯若航的回答 - 知乎](https://www.zhihu.com/question/59481694/answer/293789587)

代码实现GitHub链接：
[ACDAT in Go](https://github.com/Vonng/ac)