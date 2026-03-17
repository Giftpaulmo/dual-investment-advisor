---
name: dual-investment-delta
description: |
  BTC/ETH 双币赢 Delta 智能顾问。Deribit 预言机打价 + 币安真实 APR，车轮策略全闭环。
  触发词: "双币赢"、"低买"、"高卖"、"推荐"、"Delta"
metadata:
  version: 2.4.0
  author: Giftpaulmo
  dependencies:
    - binance-skills-hub
  config:
    max_drawdown_alert: 0.30
license: MIT
---

# Agent 执行流

所有浮点运算、日期处理、JSON 清洗在 Python 中完成。严禁 Bash 原生算术。

## Step 0: 初始化（首次对话时执行）

询问用户两件事：

1. **投入金额**："你想用多少 USDT 做双币赢？"
2. **复投模式**：

```
请选择复投模式：

A) 自动复投 — 到期后自动续下一期，每次复投后通知你：
   买了什么、上次收益、累计金额。说"停"随时终止。

B) 手动复投 — 到期后推荐下一期，等你 CONFIRM 才申购。
   不回复即暂停。
```

记录 `STRATEGY_AMOUNT` 和 `REINVEST_MODE`（`AUTO` 或 `MANUAL`）。后续所有轮次沿用，用户可随时说"切换为自动/手动"更改。

---

## Step 1: 状态嗅探

**1.0 现价（必须最先执行）**

```bash
BTC_SPOT=$(curl -s "https://www.deribit.com/api/v2/public/get_index_price?index_name=btc_usd" | jq '.result.index_price')
```

**1.1 确定策略资金（仓位隔离）**

用户首次使用时会指定金额（如"用 5000U 做双币赢"）。Agent 必须记录并追踪**策略内资金**，与用户其他资产完全隔离：

- `STRATEGY_AMOUNT`：用户指定的初始金额（USDT）
- 未行权 → 下期继续用 `STRATEGY_AMOUNT + 累计保费` 做低买
- 被行权 → 记录行权获得的 BTC 数量（= `STRATEGY_AMOUNT / strikePrice`），仅用**这部分 BTC** 做高卖，不碰账户其他 BTC
- 高卖被行权 → 换回的 USDT 就是新的策略资金，继续低买

**MODE 判断**：基于策略内资金状态，不是全账户余额：
- 策略资金为 USDT → `MODE=PUT`
- 策略资金为 BTC（上期低买被行权）→ `MODE=CALL`，申购数量 = 行权获得的 BTC 数量

首次启动时 `MODE=PUT`，`STRATEGY_AMOUNT` = 用户指定金额。

**1.2 成本价防御（仅 MODE=CALL）**

请求 `/sapi/v1/dci/product/positions`（全量拉取，不传未验证参数）。在 Python 中过滤已结算订单，找最近一笔已交割的 PUT 订单，取 `strikePrice` 为 `COST_BASIS`。无历史则 `COST_BASIS = BTC_SPOT`。

计算 `DRAWDOWN = (COST_BASIS - BTC_SPOT) / COST_BASIS`：
- `DRAWDOWN >= config.max_drawdown_alert` → 标记 `DRAWDOWN_ALERT=True`
- 输出时告知用户可说"修改预警线至 X%"调整阈值

---

## Step 2: 币安货架

请求 `/sapi/v1/dci/product/list`：

| 参数 | 值 |
|------|-----|
| optionType | `PUT`（MODE=PUT）或 `CALL`（MODE=CALL） |
| exercisedCoin | `BTC`（或 `ETH`） |
| investCoin | `USDT`（PUT）或 `BTC`（CALL） |
| timestamp | 毫秒时间戳 |
| signature | HMAC SHA256 |

从返回中提取 `canPurchase==true` 的产品：

| 字段 | 用途 |
|------|------|
| id, orderId | 申购用 |
| strikePrice | 行权价 |
| duration | 天数 |
| apr | 年化（小数，×100 得百分比） |
| settleDate | 到期时间戳（匹配 Deribit 用） |

过滤：
- duration 1-5 天
- apr ≥ 0.03（3%）
- MODE=CALL 时：strikePrice ≥ COST_BASIS

若 MODE=CALL 且过滤后为空 → 标记 `NO_CALL_PRODUCT=True`

---

## Step 3: Deribit Delta

**3.1 全量拉取（1 次请求）**

```bash
curl -s "https://www.deribit.com/api/v2/public/get_book_summary_by_currency?currency=BTC&kind=option"
```

Python 过滤：MODE=PUT 取 `-P$`，MODE=CALL 取 `-C$`。

**3.2 模糊匹配**

对每个币安产品，找 Deribit 中**行权价相同 + 到期最近**的合约。

**相对期限熔断**：
```
误差比 = abs(deribit_expiry_ms - binance_settle_ms) / (duration_days * 86400000)
误差比 > 0.5 → 废弃，跳入 3.4
```

**3.3 获取 Delta**

```bash
curl -s "https://www.deribit.com/api/v2/public/ticker?instrument_name={matched}" | jq '.result.greeks.delta'
```

**3.4 BS 兜底（无匹配或熔断触发）**

```python
from scipy.stats import norm
import math

T = (expiry_ms - now_ms) / (1000 * 86400 * 365)
d1 = (math.log(S/K) + (r + sigma**2/2)*T) / (sigma * math.sqrt(T))

put_delta = norm.cdf(d1) - 1   # MODE=PUT
call_delta = norm.cdf(d1)       # MODE=CALL
```

σ = DVOL/100，r = 0.05。

**3.5 DVOL 风控**

```bash
curl -s "https://www.deribit.com/api/v2/public/get_volatility_index_data?currency=BTC&start_timestamp={2天前ms}&end_timestamp={现在ms}&resolution=3600" | jq '.result.data[-1][4]'
```

| DVOL | Delta 上限 |
|------|----------|
| > 70 | 0.15 |
| 40-70 | 0.30 |
| < 40 | 0.35 |

全部情况剔除 |Delta| < 0.05。

---

## Step 4: 排序

```
SCORE = 币安 APR / max(|Delta|, 0.01)
```

按 SCORE 降序。选 Top 1 推荐 + Top 2 备选。

---

## Step 5: 输出

```
📊 双币赢推荐 — {日期}

BTC ${SPOT} | DVOL {dvol}% | 模式: {低买/高卖}
复投: {自动/手动} | 策略资金: {USDT金额 或 BTC数量}（仅追踪策略内资金）
{高卖}: 成本线 ${COST_BASIS} | 行权获得 {BTC数量} BTC

{DRAWDOWN_ALERT}:
🚨 现价较成本跌超 {%}！高卖停滞。评估: 止损换U 或 持币等反弹。
(说"修改预警线至X%"可调整)

{NO_CALL_PRODUCT 且无警报}:
⚠️ 暂无保本高卖产品，建议持币。

━━ 推荐 ━━
{低买/高卖} ${strike} | {d}天 | APR {apr}% | Delta {delta} ({|d|×100}%) | 得分 {SCORE}

━━ 备选 ━━
${strike2} | APR {apr2}% | Delta {delta2} | 得分 {SCORE2}

被行权: 低买→接BTC切高卖 | 高卖→换U切低买

DYOR。
{手动模式}: 金额 + CONFIRM 申购。
{自动模式}: 首次需 CONFIRM，后续自动执行。说"停"终止。
```

---

## Step 6: 申购与复投

**手动模式（REINVEST_MODE=MANUAL）**：
用户输入金额 + CONFIRM 后执行。到期后输出下一期推荐，等待 CONFIRM。不回复即暂停。

**自动模式（REINVEST_MODE=AUTO）**：
首次需要 CONFIRM。后续到期后自动执行 Step 1-5 并直接申购，然后发送通知：

```
✅ 已自动复投 — {日期}

本期: {低买/高卖} ${strike} | {d}天 | APR {apr}%
上期结果: {未行权 ✅ 赚保费 +${保费} / 行权 → 已切换{高卖/低买}}
策略资金: ${当前金额} (初始 ${初始金额}, 累计收益 {+/-}{收益率}%)
累计操作: {n}次 | 胜率: {w/n}%

说"停"终止 | 说"切换手动"改为手动确认
```

**自动模式暂停条件**（暂停后切为手动等用户决定）：
- 割肉防御触发（深套超预警线）
- 货架为空
- API 报错

申购请求：

| 参数 | 值 |
|------|-----|
| id | 产品 ID |
| orderId | 订单 ID |
| depositAmount | 策略内资金（低买用 USDT 金额，高卖用 BTC 数量） |
| timestamp | 毫秒时间戳 |
| signature | HMAC SHA256 |

```bash
curl -s -X POST -H "X-MBX-APIKEY: ${API_KEY}" \
  -H "User-Agent: dual-investment-delta/2.4.0 (Skill)" \
  "https://api.binance.com/sapi/v1/dci/product/subscribe?${PARAMS}&signature=${SIGNATURE}"
```

**不传 `autoCompoundPlan`。** 部署前 Testnet 验证默认行为是否关闭复投。

---

## 签名流程

按 binance-skills-hub `binance/spot` 的 Signing Requests 执行：

1. 拼接参数 + `timestamp`
2. RFC 3986 编码
3. HMAC SHA256 签名
4. 追加 `signature=`
5. Header: `X-MBX-APIKEY` + `User-Agent: dual-investment-delta/2.4.0 (Skill)`

---

## 安全规则

1. Key 显示: API 前5+后4，Secret 仅后5
2. 主网操作必须 CONFIRM
3. Key 只发往 binance.com / deribit.com
4. 不编造 Delta / APR — 全部来自 API
5. 不构成投资建议，DYOR

---

## Agent 约束

1. 现价必须第一步拿，后续所有折算依赖它
2. 浮点/日期/排序全部 Python，禁止 Bash 算术
3. 高卖时行权价 ≥ 成本价，无例外
4. Deribit 合约名禁止拼接，全量拉取后 Python 匹配
5. 低买过滤 `-P$`，高卖过滤 `-C$`
6. Delta 除零保护: `max(|Delta|, 0.01)`
7. **仓位隔离**: 只操作策略内资金，永远不碰用户账户里的其他资产。行权后只用行权获得的币做高卖，不用全账户余额
8. **复投模式**: AUTO 模式到期后自动申购+通知；MANUAL 模式到期后推荐等 CONFIRM。AUTO 遇到割肉防御/货架空/API 错误时自动降级为 MANUAL 等用户决定
9. **停止触发词**: "停"、"停止"、"暂停"、"退出"、"stop"、"不做了" → 输出策略总结（初始金额、当前金额、收益率、操作次数、胜率）并停止
10. **模式切换**: 用户说"切换自动"/"切换手动"/"改为自动"/"改为手动" → 即时切换 `REINVEST_MODE`
