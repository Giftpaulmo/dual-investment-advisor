# 双币赢 AI Skill 设计文档 v1.0

## 目标

在可接受风险下最大化 APR，目标年化 12%。

## 核心原则

- KISS：最简单但有用
- 用户来就是为了双币投资，不需要额外触发词
- Agent 做不好 = 方案有问题

## 决策框架

| 维度 | 作用 | 逻辑 |
|------|------|------|
| Polymarket 概率 | 定行权价 | 触达概率 < 15% = 推荐区 |
| DVOL | 定仓位建议 | > 60 建议减半仓，> 80 建议观望 |
| Deribit OI | 展示参考 | 不参与决策 |
| 宏观事件 | 风险提示 | 不参与决策 |

## 推荐标准

| 档位 | 触达概率 | 说明 |
|------|---------|------|
| 推荐 | < 10% | 放心买 |
| 备选 | 10-20% | 收益更高，风险可接受 |
| 不建议 | > 20% | 风险太高 |

## 用户流程

```
1. 用户配置 Binance API Key（一次性）
2. Agent 拉取数据，直接给出三个期限的推荐：

   日内 | 低买 $65,000 | APR 32% | 触达概率 8%
   3天  | 低买 $63,000 | APR 45% | 触达概率 6%
   一周 | 低买 $60,000 | APR 58% | 触达概率 4%

3. 用户选期限 + 输入金额
4. Agent 记住偏好（存配置），下次直接用
5. 用户输入 CONFIRM → 执行申购
```

## 数据源

| 数据源 | 需要 Key | 用途 |
|--------|---------|------|
| Polymarket Gamma API | 否 | 触达概率（主决策） |
| Deribit API | 否 | DVOL、OI 分布（参考） |
| Binance API | 是 | 产品列表、申购执行 |
| Web Search | 否 | 宏观事件提示 |

## Polymarket 数据获取

### API 端点

```
GET https://gamma-api.polymarket.com/events?active=true&closed=false&tag_slug=crypto&limit=300
```

### 目标事件 slug 模式

| 期限 | slug 模式 | 示例 |
|------|----------|------|
| 日度 | `bitcoin-above-on-{month}-{day}` | `bitcoin-above-on-march-13` |
| 日度 | `ethereum-above-on-{month}-{day}` | `ethereum-above-on-march-13` |
| 月度 | `what-price-will-bitcoin-hit-in-{month}` | `what-price-will-bitcoin-hit-in-march-2026` |
| 月度 | `what-price-will-ethereum-hit-in-{month}` | `what-price-will-ethereum-hit-in-march-2026` |
| 年度 | `what-price-will-bitcoin-hit-before-2027` | 备用参考 |

### 数据结构

```json
{
  "id": "250212",
  "title": "Bitcoin above ___ on March 13?",
  "markets": [
    {
      "id": "1515849",
      "question": "Will the price of Bitcoin be above $70,000 on March 13?",
      "outcomePrices": "[\"0.93\", \"0.07\"]",  // [Yes概率, No概率]
      "volume": "297679.99"
    }
  ]
}
```

### 概率解读

- `outcomePrices[0]` = Yes 概率 = 涨到该价位的概率
- `1 - Yes` = 跌破该价位的概率（用于低买决策）
- 示例：Yes 93% 涨到 $70K → 7% 跌破 $70K → 低买 $70K 风险 7%

### 数据质量过滤

- Volume < $100K 的市场不采信
- 如果某期限没有合格市场，跳过或用更长期限数据作保守估计

## 输出格式

```
📊 双币赢推荐 — 2026-03-13

当前: BTC $70,000 | ETH $2,100
DVOL: BTC 55% | ETH 62%

━━ BTC 低买推荐 ━━

日内 | $66,000 | APR 28% | 概率 9% | 推荐
3天  | $64,000 | APR 42% | 概率 7% | 推荐
一周 | $61,000 | APR 55% | 概率 5% | 推荐

━━ ETH 低买推荐 ━━

日内 | $1,950 | APR 25% | 概率 11% | 备选
3天  | $1,850 | APR 38% | 概率 8% | 推荐
一周 | $1,750 | APR 48% | 概率 6% | 推荐

━━ 风险提示 ━━
• 周三 CPI 数据公布，注意波动
• Deribit $60,000 有大额 PUT OI

选择期限和金额后输入 CONFIRM 申购。
```

## 配置存储

用户偏好存储在 Agent 配置中：
- `期限偏好`: 日内 / 3天 / 一周
- `单次金额`: 数字（USDT）
- `Binance API Key`: 加密存储

## 安全规则

- API Key 不完整显示
- 申购前必须 CONFIRM
- 所有分析标注"不构成投资建议"

## Polymarket 数据质量

- Volume < $100K 的市场不采信
- Spread 过大的市场降权
- 如果某期限没有合格市场，跳过或降级提示

## 高卖逻辑

决策依据：
- Polymarket "涨到 $X" 概率 < 10% → 可高卖
- 用户可配置心理锚点（如 BTC $100K 以上才高卖）

## 到期提醒

到期时推送结算结果 + 历史战绩：

```
📊 到期结算 — 2026-03-13

上周买入: BTC 低买 $65,000 | 3天 | APR 45%
结算价: $68,200
结果: ✅ 未行权，收益 +$135

━━ 历史战绩 ━━
总次数: 23 | 胜率: 87% | 累计: +$2,340 | 年化: 14.2%
```

## 本地存储

配置文件（一次性）：
- Binance API Key
- 期限偏好
- 单次金额
- 高卖心理锚点

历史记录（每次申购追加）：
- 时间、币种、方向
- 行权价、期限、APR、金额
- 结算价、结果、收益
