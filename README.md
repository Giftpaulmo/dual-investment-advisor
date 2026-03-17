# 双币赢 Delta 智能顾问 v2.4

> Deribit 预言机打价 + 币安真实 APR，车轮策略全闭环。

用 Delta 量化行权概率，自动在低买/高卖之间轮转，让双币赢变成可持续的收益策略。

---

## 核心逻辑

```
Deribit Delta（行权概率）
  PUT Delta -0.15 = 15% 概率被行权
  → 专业期权市场的定价，比猜测靠谱
         +
币安真实 APR（收益）
  直接从货架拉取，不是估算
         +
车轮策略（自动轮转）
  低买被行权 → 拿到 BTC → 自动切高卖
  高卖被行权 → 换回 USDT → 自动切低买
         ↓
SCORE = APR / |Delta|
→ 同样的行权风险下，选收益最高的
```

### Delta 风控

| DVOL（波动率） | Delta 上限 | 说明 |
|---------------|-----------|------|
| > 70 | 0.15 | 高波动，只选极安全的 |
| 40-70 | 0.30 | 正常市场 |
| < 40 | 0.35 | 低波动，可以激进一点 |

---

## 快速开始

1. 克隆仓库
```bash
git clone https://github.com/Giftpaulmo/dual-investment-advisor.git
```

2. 在 Claude Code / Cursor 等 Agent 中加载 `SKILL.md`

3. 提供 Binance API Key（确保关闭提现权限）

4. 告诉 Agent："用 5000U 做双币赢"

Agent 会自动：
- 获取 Deribit Delta + 币安货架
- 计算最优产品
- 给出推荐，等你确认后申购
- 到期后自动推荐下一期（或自动复投）

---

## 两种复投模式

| 模式 | 行为 |
|------|------|
| 自动复投 | 到期后自动申购下一期，每次通知你结果。说"停"终止 |
| 手动复投 | 到期后推荐下一期，等你 CONFIRM 才申购 |

---

## 仓位隔离

Agent 只操作你指定的策略资金，不碰账户里的其他资产：

- 你说"用 5000U"→ 只用这 5000U
- 低买被行权拿到 0.05 BTC → 只用这 0.05 BTC 做高卖
- 不会动你账户里原有的 BTC

---

## 文件结构

```
dual-investment-advisor/
├── SKILL.md      ← Agent 执行逻辑（加载这个）
├── README.md     ← 你正在看的
├── config.json   ← 本地配置（不上传）
└── LICENSE       ← MIT
```

---

## 数据源

| 数据源 | 需要 Key？ | 用途 |
|--------|-----------|------|
| Deribit Public API | ❌ | Delta、DVOL、现价 |
| Binance API | ✅ 你的 Key | 货架、申购 |

---

## 安全说明

- Binance API Key **必须关闭提现权限**
- 主网申购前必须 CONFIRM
- 所有分析不构成投资建议，DYOR

---

## License

MIT
