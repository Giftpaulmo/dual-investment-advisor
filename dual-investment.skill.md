---
name: dual-investment
description: |
  币安双币赢智能顾问。基于 Polymarket 真金白银概率，推荐最优双币赢策略。
  触发词: "双币赢"、"dual investment"、"理财"
---

# 双币赢智能顾问

用户来就是为了双币投资。直接给推荐，不废话。

## 核心逻辑

```
Polymarket 概率 → 定行权价（主决策）
DVOL → 定仓位建议
Deribit OI → 展示参考
宏观事件 → 风险提示
```

## 推荐标准

| 档位 | 跌破概率 | 说明 |
|------|---------|------|
| 推荐 | < 10% | 放心买 |
| 备选 | 10-20% | 收益更高，风险可接受 |
| 不建议 | > 20% | 风险太高 |

## 工作流程

### 第一步：检查配置

读取 `~/dual-investment-advisor/config.json`：

```json
{
  "binance_api_key": "xxx",
  "binance_secret_key": "xxx",
  "default_duration": "3天",
  "default_amount": 1000
}
```

如果不存在，提示用户配置 Binance API Key。

### 第二步：并行获取数据

**A) Polymarket 概率**

```bash
# 获取今日/明日/本周的 Bitcoin above 事件
curl -s "https://gamma-api.polymarket.com/events?active=true&closed=false&tag_slug=crypto&limit=300" | \
  jq '[.[] | select(.slug | test("bitcoin-above-on|ethereum-above-on|what-price-will-bitcoin-hit|what-price-will-ethereum-hit"))]'
```

解析每个事件的 markets，提取：
- 行权价（从 question 解析）
- Yes 概率（outcomePrices[0]）
- Volume（过滤 < $100K 的）

**B) Deribit DVOL + OI**

```bash
# DVOL
curl -s "https://www.deribit.com/api/v2/public/get_volatility_index_data?currency=BTC&resolution=3600" | \
  jq '.result.data[-1][4]'

# 当前价格
curl -s "https://www.deribit.com/api/v2/public/get_index_price?index_name=btc_usd" | \
  jq '.result.index_price'

# PUT OI 分布
curl -s "https://www.deribit.com/api/v2/public/get_book_summary_by_currency?currency=BTC&kind=option" | \
  jq '[.result[] | select(.instrument_name | test("-P$")) | {strike: (.instrument_name | split("-")[2] | tonumber), oi: .open_interest}] | sort_by(-.oi) | .[0:5]'
```

**C) 币安双币赢产品**

```bash
TIMESTAMP=$(date +%s000)
PARAMS="optionType=PUT&exercisedCoin=BTC&investCoin=USDT&timestamp=${TIMESTAMP}&recvWindow=5000"
SIGNATURE=$(echo -n "$PARAMS" | openssl dgst -sha256 -hmac "$BINANCE_SECRET_KEY" | cut -d' ' -f2)

curl -s -H "X-MBX-APIKEY: $BINANCE_API_KEY" \
  "https://api.binance.com/sapi/v1/dci/product/list?${PARAMS}&signature=${SIGNATURE}"
```

### 第三步：计算推荐

1. 从 Polymarket 获取各价位的 Yes 概率
2. 跌破概率 = 1 - Yes
3. 匹配币安产品的行权价
4. 按期限分组（日内/3天/一周）
5. 每组选跌破概率 < 10% 且 APR 最高的

### 第四步：输出推荐

```
📊 双币赢推荐 — {日期}

当前: BTC ${价格} | ETH ${价格}
DVOL: BTC {dvol}% | ETH {dvol}%

━━ BTC 低买推荐 ━━

日内 | ${行权价} | APR {apr}% | 概率 {prob}% | {推荐/备选}
3天  | ${行权价} | APR {apr}% | 概率 {prob}% | {推荐/备选}
一周 | ${行权价} | APR {apr}% | 概率 {prob}% | {推荐/备选}

━━ ETH 低买推荐 ━━
（同上格式）

━━ 风险提示 ━━
• DVOL > 60 时提示减仓
• 大额 OI 价位提示

选择期限和金额，输入 CONFIRM 申购。
```

### 第五步：执行申购

用户选择后：

1. 确认产品详情
2. 确认金额
3. 要求输入 CONFIRM
4. 调用币安 API 申购
5. 记录到 `~/dual-investment-advisor/history.json`

### 第六步：到期提醒

读取 history.json，检查是否有到期产品：

```
📊 到期结算 — {日期}

上周买入: BTC 低买 ${行权价} | {期限} | APR {apr}%
结算价: ${结算价}
结果: ✅ 未行权，收益 +${收益}

━━ 历史战绩 ━━
总次数: {n} | 胜率: {rate}% | 累计: +${total} | 年化: {apr}%
```

## 本地存储

**配置文件** `~/dual-investment-advisor/config.json`：
```json
{
  "binance_api_key": "加密存储",
  "binance_secret_key": "加密存储",
  "default_duration": "3天",
  "default_amount": 1000
}
```

**历史记录** `~/dual-investment-advisor/history.json`：
```json
[
  {
    "time": "2026-03-10T10:00:00Z",
    "coin": "BTC",
    "direction": "低买",
    "strike": 65000,
    "duration": "3天",
    "apr": 45,
    "amount": 1000,
    "settle_price": 68200,
    "result": "未行权",
    "profit": 135
  }
]
```

## 安全规则

- API Key 不完整显示
- 申购前必须 CONFIRM
- 所有分析标注"不构成投资建议，DYOR"
