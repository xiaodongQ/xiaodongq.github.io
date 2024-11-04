---
layout: post
title: LeetCode刷题学习（三） -- 链表篇
categories: LeetCode
tags: LeetCode 数据结构与算法
---

* content
{:toc}

LeetCode刷题学习记录，链表篇。



## 1. 基础

链表定义：

```cpp
// 单链表
struct ListNode {
    int val;  // 节点上存储的元素
    ListNode *next;  // 指向下一个节点的指针
    ListNode(int x) : val(x), next(NULL) {}  // 节点的构造函数
};

// 示例，初始化一个链表，构造函数便于初始化时对节点赋值
ListNode* head = new ListNode(5);
```

## 2. 203.移除链表元素

[203. Remove Linked List Elements](https://leetcode.com/problems/remove-linked-list-elements/)

### 2.1. 思路和解法

技巧：定义虚拟头节点，避免头节点单独处理。

另外有几个注意点：

* 虚拟头节点记得释放空间，不要直接`return dummyHead->next`
* C++里要删除的节点，一般也释放其空间
* 注意循环中判断`currNode->next`，而不是用 `currNode != nullptr`，并对`currNode`迭代

```cpp
/**
 * Definition for singly-linked list.
 * struct ListNode {
 *     int val;
 *     ListNode *next;
 *     ListNode() : val(0), next(nullptr) {}
 *     ListNode(int x) : val(x), next(nullptr) {}
 *     ListNode(int x, ListNode *next) : val(x), next(next) {}
 * };
 */
class Solution {
public:
    ListNode* removeElements(ListNode* head, int val) {
        // 定义一个虚拟节点，指向链表头
        ListNode *dummyHead = new ListNode();
        dummyHead->next = head;
        ListNode *currNode = dummyHead;
        // 注意循环中判断next，而不是用 currNode != nullptr，并对currNode迭代
        while (currNode->next != nullptr) {
            if (currNode->next->val == val) {
                // 下一个节点和val相等，则移除下个节点
                ListNode *tmp_node = currNode->next;
                currNode->next = currNode->next->next;
                delete tmp_node;
            } else {
                // 没有匹配到相等节点时迭代下一个，上面匹配到时next已经指向下一个了
                currNode = currNode->next;
            }
        }

        // dummyHead 是临时申请的空间，需要释放掉
        ListNode *node = dummyHead->next;
        delete dummyHead;

        // 返回的节点指针，是原来链表中已有的节点
        return node;
    }
};
```

### 2.2. Rust解法

Rust中如果要实现链表的话比较复杂，可作了解：[手把手带你实现链表](https://course.rs/too-many-lists/intro.html)

上面的题目链接（[203. Remove Linked List Elements](https://leetcode.com/problems/remove-linked-list-elements/)）中，已经给出了Rust中的链表定义。

```rust
#[derive(PartialEq, Eq, Clone, Debug)]
pub struct ListNode {
  pub val: i32,
  // Option枚举类型，Some(T)和None；返回Some(T)时，是堆上分配的Box智能指针
  pub next: Option<Box<ListNode>>
}

impl ListNode {
  // 内联属性
  #[inline]
  // 这里的new只是创建了一个新的ListNode实例，不是指分配在堆内存上
  fn new(val: i32) -> Self {
    ListNode {
      next: None,
      val
    }
  }
}
```

学习参考链接中的题解：

```rust
impl Solution {
    pub fn remove_elements(head: Option<Box<ListNode>>, val: i32) -> Option<Box<ListNode>> {
        // 使用智能指针
        let mut dummyHead = Box::new(ListNode::new(0));
        dummyHead.next = head;
        let mut cur = dummyHead.as_mut();
        // 使用take()替换std::mem::replace(&mut node.next, None)达到相同的效果，并且更普遍易读
        while let Some(nxt) = cur.next.take() {
            if nxt.val == val {
                cur.next = nxt.next;
            } else {
                cur.next = Some(nxt);
                cur = cur.next.as_mut().unwrap();
            }
        }
        dummyHead.next
    }
}
```

## 3. 设计链表

[707. Design Linked List](https://leetcode.com/problems/design-linked-list/description/)

### 3.1. 思路和解法

注意题目要求中的几个小点和边界：

* `0 <= index, val <= 1000` 范围都是正整数，代码中可以不判断`< 0`的边界
    * 若在实际开发中，建议还是加上显式校验，弱约束依赖调用方的靠谱程度
* `int get(int index)`，如果索引无效则返回`-1`
* `void addAtIndex(int index, int val)`，在`index`节点前插入节点，如果`index`等于链表长度，则在最后插入，否则不插入

插入和删除都需要先找到前一个节点，所以从`虚拟头节点`开始会更方便；而`get`查找，从第一个节点开始即可，更容易理解。

```cpp
class MyLinkedList {
public:
    // 定义链表结构
    struct LinkedNode {
        int val;
        LinkedNode *next;
        LinkedNode(int val):val(val), next(nullptr){}
    };

    MyLinkedList() {
        size = 0;
        dummyHead = new LinkedNode(0);
    }
    
    int get(int index) {
        // 题目的约束中限制了`>=0`，实际还是显式判断下不能`<0`
        if (index > size - 1 || index < 0) {
            return -1;
        }

        // 从第一个节点（index下标为0）开始遍历
        LinkedNode *cur = dummyHead->next;

        // for (int i = 0; i < index; i++) {
        //     cur = cur->next;
        // }
        // while循环更简洁一点，不用临时变量
        while (index--) {
            cur = cur->next;
        }
        return cur->val;
    }
    
    void addAtHead(int val) {
        LinkedNode *node = new LinkedNode(val);
        node->next = dummyHead->next;
        dummyHead->next = node;
        size++;
    }
    
    void addAtTail(int val) {
        LinkedNode *cur = dummyHead;
        // 遍历到最后节点
        while (cur->next != nullptr) {
            cur = cur->next;
        }
        LinkedNode *node = new LinkedNode(val);
        cur->next = node;
        size++;
    }
    
    // 插入到index前面
    void addAtIndex(int index, int val) {
        // 写边界时，可代入一个特殊值，如size=1时，须满足index<=1，两者相等时插入到队尾
        if (index > size) {
            return;
        }
        // 虽然题目有边界，index<0的边界还是显式处理下
        if (index < 0) {
            index = 0;
        }

        // 遍历到index前一个节点，需要从虚拟头开始
        LinkedNode *cur = dummyHead;
        while (index--) {
            cur = cur->next;
        }
        LinkedNode *node = new LinkedNode(val);
        node->next = cur->next;
        cur->next = node;
        size++;
    }
    
    void deleteAtIndex(int index) {
        // 虽然题目边界index>=0，实际编程中还是硬性判断一下
        if (index > size - 1) {
            return;
        }
        // 遍历到index前一个节点
        LinkedNode *cur = dummyHead;
        while (index--) {
            cur = cur->next;
        }
        LinkedNode *node = cur->next;
        cur->next = cur->next->next;
        delete node;
        size--;
    }

private:
    // 链表长度，获取指定索引时需要校验
    int size;
    // 虚拟头节点，实际next为链表
    LinkedNode *dummyHead;
};
```

## 4. 206.反转链表

[206. Reverse Linked List](https://leetcode.com/problems/reverse-linked-list/description/)

### 4.1. 思路和解法

利用两个指针，记录后一个节点和前一个节点，依次两两调整指向。

```cpp
/**
 * Definition for singly-linked list.
 * struct ListNode {
 *     int val;
 *     ListNode *next;
 *     ListNode() : val(0), next(nullptr) {}
 *     ListNode(int x) : val(x), next(nullptr) {}
 *     ListNode(int x, ListNode *next) : val(x), next(next) {}
 * };
 */
class Solution {
public:
    ListNode* reverseList(ListNode* head) {
        // 不需要虚拟头节点
        ListNode* prev = nullptr;
        ListNode* cur = head;
        ListNode* tmp = nullptr;
        while (cur != nullptr) {
            // 先记录下个节点，因为cur下面会改变，导致其next指向也变化
            ListNode* tmp = cur->next;
            cur->next = prev;
            prev = cur;
            cur = tmp;
        }
        // 最后cur是nullptr，链表头应该为prev
        return prev;
    }
};
```

## 5. 参考

1、[代码随想录 -- 链表篇](https://www.programmercarl.com/%E9%93%BE%E8%A1%A8%E7%90%86%E8%AE%BA%E5%9F%BA%E7%A1%80.html)

2、[LeetCode中文站](https://leetcode.cn/)

3、[LeetCode英文站](https://leetcode.com/)
