# Fix dual-investment.skill.md Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 dual-investment.skill.md，使其成为可严格执行的 checklist，覆盖低买+高卖，包含异常处理。

**Architecture:** 重写 Skill 为严格的 step-by-step checklist 格式，每一步都有明确的命令、预期输出、异常处理。

**Tech Stack:** Markdown, Bash (curl/jq), Binance API, Polymarket API, Deribit API

---

## Chunk 1: 问题清单与文件结构

### 当前问题

| 问题 | 影响 |
|------|------|
| 只有低买（PUT），没有高卖（CALL） | 功能不完整 |
| DVOL API 返回 null 没有异常处理 | 执行中断 |
| 宏观事件只在"核心逻辑"提到，流程里没有 | 功能缺失 |
| Polymarket Volume 过滤写了但没有具体实现 | 数据质量无保障 |
| 步骤描述模糊，不是可执行命令 | Agent 无法严格执行 |
| 架构图没有放进文档 | 用户难以理解 |

### 文件结构

- Modify: `dual-investment.skill.md` — 完全重写

---

## Chunk 2: 重写 Skill

### Task 1: 重写 dual-investment.skill.md

**Files:**
- Modify: `dual-investment.skill.md`

- [ ] **Step 1: 备份当前文件**

```bash
cp dual-investment.skill.md dual-investment.skill.md.bak
```

- [ ] **Step 2: 重写 Skill 文件**

新内容结构：

```
---
frontmatter
---

# 标题

## 架构图（ASCII）

## 推荐标准

## 工作流程（严格 checklist）

### Step 1: 检查配置
- [ ] 读取 config.json
- [ ] 如果不存在，提示用户配置
- [ ] 预期输出：config 对象

### Step 2: 获取数据（并行）
- [ ] 2.1 Polymarket BTC/ETH 概率
  - 命令：curl ...
  - 预期输出：JSON
  - 异常处理：如果失败，提示用户
- [ ] 2.2 Deribit 价格/DVOL/OI
  - 命令：curl ...
  - 预期输出：JSON
  - 异常处理：DVOL 返回 null 时显示 "N/A"
- [ ] 2.3 币安低买产品（PUT）
  - 命令：curl ...
- [ ] 2.4 币安高卖产品（CALL）
  - 命令：curl ...
- [ ] 2.5 宏观事件（Web Search）
  - 搜索词：US economic calendar this week CPI NFP FOMC

### Step 3: 计算推荐
- [ ] 3.1 低买推荐
- [ ] 3.2 高卖推荐

### Step 4: 输出推荐（固定格式）

### Step 5: 用户选择 + 申购

### Step 6: 到期提醒

## 本地存储

## 安全规则
```

- [ ] **Step 3: 验证新 Skill 可执行**

手动按新 Skill 执行一遍，确认每一步都能跑通。

- [ ] **Step 4: 提交**

```bash
git add dual-investment.skill.md
git commit -m "fix: 重写 Skill 为严格可执行 checklist

- 新增高卖（CALL）流程
- 新增宏观事件 Web Search
- 新增 DVOL 异常处理
- 新增架构图
- 所有步骤改为可执行命令"
```

---

## Chunk 3: 更新 README

### Task 2: 更新 README 架构图

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 添加架构图到 README**

在"核心逻辑"部分添加 ASCII 架构图。

- [ ] **Step 2: 简化安装说明**

用户只需要：
1. 下载仓库
2. 配置 API Key
3. 加载 Skill

- [ ] **Step 3: 提交**

```bash
git add README.md
git commit -m "docs: 添加架构图，简化安装说明"
```

---

## Chunk 4: 验证

### Task 3: 端到端测试

- [ ] **Step 1: 用新 Skill 执行完整流程**

1. 加载 Skill
2. 按 checklist 执行每一步
3. 确认输出格式正确
4. 确认低买+高卖都有推荐

- [ ] **Step 2: 记录问题（如有）**

- [ ] **Step 3: 推送到 GitHub**

```bash
git push origin main
```

---

Plan complete.
