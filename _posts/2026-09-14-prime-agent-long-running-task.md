---
title: Prime Agent 长程任务架构解析
description: 深入分析 Prime Agent 的长程任务处理机制，与 LangGraph 等开源方案进行对比
categories: [AI, Agent]
tags: [AI, Agent, PrimeAgent, LangGraph, SWE-agent]
---

## 1. 背景

之前写过一篇文章 [AI长程任务方案分析设计](https://xiaodongq.github.io/2026/09/09/long-term-ai-task/)，分析了业界 AI Agent 的长程任务处理思路。最近在研究 [Prime Agent](https://github.com/PrimeIntellect-ai/prime-agent) 时，发现它的实现很有特色，特此记录。

## 2. Prime Agent 长程任务处理机制

### 2.1 核心架构：多层循环

Prime Agent 的 agent loop 实现位于 `packages/agent/src/agent-loop.ts`，采用三层循环结构：

```typescript
// packages/agent/src/agent-loop.ts:304-449
async function runLoop(currentContext, newMessages, config, signal, emit, streamFn) {
  let firstTurn = true;
  let lastTurn;
  
  while (true) {
    // 外层循环: 多轮对话
    while (hasMoreToolCalls || pendingMessages.length > 0) {
      // 中层循环: 处理单轮 tool calls
      const message = await streamAssistantResponse(...);
      const toolResults = await executeToolCalls(...);
      hasMoreToolCalls = !executedToolBatch.terminate;
    }
    
    // 检查 followUp 消息
    pendingMessages = pollMessagesUnlessAborted(config.getFollowUpMessages, ...);
    if (pendingMessages.length > 0) continue;
    
    // 关键机制: getContinuationMessages - 长程任务恢复点
    continuationMessages = config.getContinuationMessages?.(lastTurn, signal);
    if (continuationMessages.length > 0) continue;
    
    break;
  }
}
```

### 2.2 Continuation 机制

Prime Agent 通过 `getContinuationMessages` hook 实现长程任务的自动续期：

```typescript
// packages/agent/src/types.ts:231-243
/**
 * Returns continuation messages when the agent would otherwise stop.
 * Called after follow-up messages have been polled and none are available.
 * If messages are returned, they're added to the context and the agent
 * continues with another turn.
 * 
 * Use this for host-owned continuation policies such as long-running goals.
 */
getContinuationMessages?: (context: GetContinuationMessagesContext, signal?: AbortSignal) => Promise<AgentMessage[]>;
```

这意味着：
- 当 Agent 正常结束一个 turn 后
- 如果有 active goal，会自动生成 continuation message 继续执行
- 不会因为"本轮结束"就中断

### 2.3 Goal 目标系统

Prime Agent 的 goal 系统实现于 `packages/coding-agent/src/core/goals.ts`：

```typescript
// packages/coding-agent/src/core/goals.ts
export type GoalStatus = "idle" | "active" | "paused" | "budget_limited" | "complete" | "error";

export interface GoalState {
  active: boolean;
  status: GoalStatus;
  goalId?: string;
  objective?: string;
  tokenBudget?: number;
  tokensUsed: number;
  timeUsedSeconds: number;
  continuationsUsed: number;
}
```

**Continuation 逻辑** (`agent-session.ts:3423-3459`)：

```typescript
private async _getGoalContinuationMessages(context, signal): Promise<AgentMessage[]> {
  // 1. terminal message 检查
  if (this._stopGoalContinuationForTerminalMessage(context.message)) return [];
  
  // 2. 检查是否有 unsettled RLM work（如子 agent 还在跑）
  if (this._hasUnsettledRlmQuiescenceWork()) {
    this._goalContinuationAwaitsRlmWork = true;
    return [];
  }
  
  // 3. 激活 goal runtime 并生成 continuation message
  this._ensureGoalRuntimeActive(context.context);
  return [createGoalContextMessage(this._goalState, "continuation")];
}
```

**优先级机制** (`agent-session.ts:3461-3496`)：

```typescript
private async _getContinuationMessages(...) {
  // Goal continuation 优先于 autonomous continuation
  const goalMessages = await this._getGoalContinuationMessages(context, signal);
  if (goalMessages.length > 0) return goalMessages;
  
  // 然后才是 autonomous continuation (心跳、自动任务等)
  const autonomousMessage = await nextAutonomousContinuation(...);
  return autonomousMessage ? [autonomousMessage] : [];
}
```

### 2.4 会话持久化

Prime Agent 通过 SessionManager 将所有消息追加写入 `.jsonl` 文件：

```typescript
// packages/coding-agent/src/core/session-manager.ts
export class SessionManager {
  // 追加写入，支持崩溃恢复
  _persist(entry: SessionEntry): void {
    if (!this.persist || !this.sessionFile) return;
    // 支持 crash damage repair
    appendFileSync(this.sessionFile, `${JSON.stringify(entry)}\n`);
  }
}
```

**关键特性**：
- append-only 写入，崩溃后可恢复
- 支持 compaction 压缩历史消息
- 通过 `thread_goal_state` custom entry 持久化 goal 状态

### 2.5 AbortSignal 中断机制

虽然有 `abort()` 方法，但通过 `shouldStopAfterTurn` 提供受控停止：

```typescript
// packages/coding-agent/src/core/agent-session.ts:2345
private async _shouldStopAfterTurn(context: ShouldStopAfterTurnContext): Promise<boolean> {
  // 处理 budget limit
  if (this._accountGoalUsageForAssistantMessage(context.message)) {
    const message = createGoalContextMessage(this._goalState, "budget_limit");
    await this._queuePreparedPrompt("steer", ...);
  }
  
  // 阈值压缩检查
  if (await this._shouldStopForThresholdCompaction(context)) {
    return true;
  }
  
  return this._steeringStopPending;
}
```

## 3. 开源方案对比

### 3.1 LangGraph Checkpointing

LangGraph 提供了成熟的 checkpoint 机制：

**核心组件**：
- **Checkpointer** - 每轮后保存状态快照
- **Store** - 跨线程长期存储
- **Thread-based execution** - 通过 `thread_id` 持久化会话

```python
from langgraph.checkpoint.sqlite import SqliteSaver
checkpointer = SqliteSaver.from_conn_string("agent.db")
app = graph.compile(checkpointer=checkpointer)

# 通过相同 thread_id 恢复
config = {"configurable": {"thread_id": "user-42"}}
agent.invoke({"messages": [...]}, config)

# Time travel - 从任意检查点恢复
history = list(agent.get_state_history(config))
agent.invoke(None, config=history[3].config)
```

**特点**：
- ✅ 成熟的 checkpoint 实现
- ✅ 支持 time travel 调试
- ✅ 多种后端（Memory/SQLite/Postgres）
- ⚠️ 需要显式管理 thread_id
- ⚠️ 状态需要设计好 reducers

[LangGraph Persistence 文档](https://docs.langchain.com/oss/python/langgraph/persistence)

### 3.2 SWE-agent

SWE-agent 专注于代码修复任务：

```bash
# 使用方式
swe-agent --repo https://github.com/user/repo --issue 123
```

**特点**：
- ✅ 针对 SWE-bench 优化
- ✅ 简洁的单任务设计
- ⚠️ 不支持通用 goal 续期
- ⚠️ 无原生 checkpoint 机制

[SWE-agent GitHub](https://github.com/CodeByteMe/SWE-agent)

### 3.3 对比总结

| 特性 | Prime Agent | LangGraph | SWE-agent |
|------|-------------|-----------|-----------|
| **Goal 支持** | 原生 goal 状态机 | 需自行实现 | 无 |
| **Checkpoint** | Session 持久化 | Checkpointer 机制 | 无 |
| **自动续期** | getContinuationMessages | 需自行实现 | 无 |
| **RLM 子 Agent** | 支持等待子 Agent | 需自行实现 | 无 |
| **Budget 控制** | token/time budget | 需自行实现 | 无 |
| **复杂度** | 高（功能全面） | 中（需设计状态） | 低（单任务） |

## 4. Prime Agent Goal 的关键创新

### 4.1 RLM-aware 设计

Prime Agent 的 goal continuation 会检查子 agent 状态：

```typescript
// 等待 RLM 子 agent 完成后再继续
if (this._hasUnsettledRlmQuiescenceWork()) {
  this._goalContinuationAwaitsRlmWork = true;
  return [];
}
```

### 4.2 多级优先级

```
用户输入 > Goal Continuation > Autonomous Continuation
```

确保用户优先级最高，同时 goal 优先于后台自动任务。

### 4.3 Prompt Injection 而非原生支持

Prime Agent 通过 `createGoalContextMessage` 向 context 注入 prompt：

```typescript
function continuationPrompt(goal: GoalState): string {
  return `Continue working toward the active thread goal.
  The goal persists across turns. Ending one turn does not reduce or redefine the objective.
  If the goal is not complete yet, make concrete progress toward the full objective.`;
}
```

**优点**：无需修改 LLM 行为，通过 prompt engineering 实现  
**缺点**：依赖 prompt 模板质量，消耗 token

## 5. PI 与 Prime Agent 的架构关系

### 5.1 架构分层

Prime Agent 基于 [pi (earendil-works/pi)](https://github.com/earendil-works/pi) monorepo 构建，架构分层清晰：

```
@earendil-works/pi (pi monorepo)
├── @earendil-works/pi-ai           # 统一 LLM API 层
├── @earendil-works/pi-agent-core   # 通用 Agent 核心（agent loop）
├── @earendil-works/pi-coding-agent # Coding Agent CLI
└── @earendil-works/pi-tui         # 终端 UI 库

Prime Agent (fork + 扩展)
└── 基于 pi packages 构建，添加：
    - Prime Agent 特有配置
    - Goal/RLM 功能
    - 特定集成
```

### 5.2 Prime Agent Packages 对应关系

| Prime Agent Package | 对应 pi package | 用途 |
|-------------------|-----------------|------|
| `packages/agent` | `@earendil-works/pi-agent-core` | Agent 循环、状态管理 |
| `packages/ai` | `@earendil-works/pi-ai` | 多 provider LLM API |
| `packages/coding-agent` | `@earendil-works/pi-coding-agent` | Python REPL、session 管理 |
| `packages/tui` | `@earendil-works/pi-tui` | 终端界面组件 |

### 5.3 调用栈

```
用户输入
    ↓
coding-agent (业务逻辑, goal/RLM)
    ↓
agent (agent loop, tool execution)
    ↓
pi-ai (LLM API 调用)
    ↓
各 Provider (Anthropic/OpenAI/MiniMax/Google...)
```

### 5.4 分工设计的好处

1. **模块化** - 各层职责清晰，可独立替换
2. **可复用** - pi packages 可被其他项目使用
3. **可定制** - Prime Agent 通过 fork 方式保留定制能力
4. **可测试** - 各层可单独测试

### 5.5 pi-ai 统一 LLM API

`@earendil-works/pi-ai` 封装了多种 LLM provider：

```typescript
// packages/ai/package.json
{
  "exports": {
    ".": "./dist/index.js",              // 统一入口
    "./anthropic": "./dist/providers/anthropic.js",
    "./openai-responses": "./dist/providers/openai-responses.js",
    "./google": "./dist/providers/google.js",
    // ...更多 provider
  }
}
```

支持 providers：
- Anthropic (Claude)
- OpenAI (GPT-4/Codex)
- Google (Gemini)
- AWS Bedrock
- Mistral
- MiniMax
- OpenRouter

## 6. 结论

Prime Agent 的长程任务设计采用了**混合策略**：

1. **goal 驱动** - 每个 goal 有状态机和 budget 追踪
2. **每轮自动续期** - `getContinuationMessages` 实现自动恢复
3. **会话持久化** - 崩溃后可从 `.jsonl` 恢复
4. **compaction 压缩** - 防止 context 过长

相比 LangGraph 需要自行设计状态和 checkpoint，Prime Agent 提供了开箱即用的长程任务方案，但代价是更高的复杂性。

对于需要精细控制长程任务的场景，Prime Agent 的设计值得参考；对于简单场景，直接使用 LangGraph 的 checkpoint 机制可能更合适。

## 7. 参考

- [Prime Agent GitHub](https://github.com/PrimeIntellect-ai/prime-agent)
- [pi monorepo](https://github.com/earendil-works/pi)
- [LangGraph Persistence](https://docs.langchain.com/oss/python/langgraph/persistence)
- [SWE-agent](https://github.com/CodeByteMe/SWE-agent)
- [AI长程任务方案分析设计](https://xiaodongq.github.io/2026/09/09/long-term-ai-task/)
