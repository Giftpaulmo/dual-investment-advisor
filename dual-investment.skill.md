---
name: dual-investment
description: |
  币安双币赢智能顾问。基于 Polymarket 真金白银概率，推荐最优双币赢策略。
  触发词: "双币赢"、"dual investment"、"理财"
---

# 双币赢智能顾问

用户来就是为了双币投资。直接给推荐，不废话。

## 架构设计

```
用户提问 → Agent 加载 Skill → 并行获取数据 → 计算推荐 → 输出结果
                                    ↓
                         ┌─────────┼─────────┐
                         ↓         ↓         ↓
                   Polymarket  Deribit   Web Search
                   (概率)      (OI/DVOL)  (宏观日历)
                         ↓         ↓         ↓
                         └─────────┼─────────┘
                                   ↓
                            决策逻辑（在 Skill 内）
                                   ↓
                            推荐/备选/不建议
                                   ↓
                         用户确认 → 调币安 API 申购
```

## 推荐标准

| 档位 | 跌破/涨破概率 | 说明 |
|------|-------------|------|
| 推荐 | < 10% | 放心买 |
| 备选 | 10-20% | 收益更高，风险可接受 |
| 不建议 | > 20% | 风险太高 |

## 工作流程（严格按顺序执行）

### Step 1: 检查配置

- [ ] 1.1 读取配置文件

```bash
cat ~/dual-investment-advisor/config.json
```

预期输出：
```json
{
  "binance_api_key": "xxx",
  "binance_secret_key": "xxx",
  "default_duration": "3天",
  "default_amount": 1000
}
```

- [ ] 1.2 如果文件不存在或缺少 API Key

提示用户：
```
请提供 Binance API Key 和 Secret Key。
确保 API 权限只开启"读取"和"现货交易"，关闭提现权限。
```

收到后保存到 `~/dual-investment-advisor/config.json`。

---

### Step 2: 并行获取数据

- [ ] 2.1 获取当前价格（Deribit）

```bash
# BTC 价格
curl -s "https://www.deribit.com/api/v2/public/get_index_price?index_name=btc_usd" | jq '.result.index_price'

# ETH 价格
curl -s "https://www.deribit.com/api/v2/public/get_index_price?index_name=eth_usd" | jq '.result.index_price'
```

- [ ] 2.2 获取 DVOL（Deribit）

```bash
# BTC DVOL
curl -s "https://www.deribit.com/api/v2/public/get_volatility_index_data?currency=BTC&resolution=3600" | jq '.result.data[-1][4] // "N/A"'

# ETH DVOL
curl -s "https://www.deribit.com/api/v2/public/get_volatility_index_data?currency=ETH&resolution=3600" | jq '.result.data[-1][4] // "N/A"'
```

**异常处理**：如果返回 "N/A"，在输出中显示 "DVOL: N/A"，继续执行。

- [ ] 2.3 获取 PUT OI 分布（Deribit）

```bash
# BTC PUT OI Top 5
curl -s "https://www.deribit.com/api/v2/public/get_book_summary_by_currency?currency=BTC&kind=option" | \
  jq '[.result[] | select(.instrument_name | test("-P$")) | {strike: (.instrument_name | split("-")[2] | tonumber), oi: .open_interest}] | sort_by(-.oi) | .[0:5]'

# ETH PUT OI Top 5
curl -s "https://www.deribit.com/api/v2/public/get_book_summary_by_currency?currency=ETH&kind=option" | \
  jq '[.result[] | select(.instrument_name | test("-P$")) | {strike: (.instrument_name | split("-")[2] | tonumber), oi: .open_interest}] | sort_by(-.oi) | .[0:5]'
```

- [ ] 2.4 获取 Polymarket 概率

```bash
# 获取所有 BTC/ETH 价格预测事件
curl -s "https://gamma-api.polymarket.com/events?active=true&closed=false&tag_slug=crypto&limit=300" | \
  jq '[.[] | select(.slug | test("bitcoin-above-on|ethereum-above-on"))] | .[] | {id, slug, title}'
```

然后对每个相关事件获取详情：

```bash
# 示例：获取 BTC 某日价格预测
curl -s "https://gamma-api.polymarket.com/events/{event_id}" | \
  jq '[.markets[] | {strike: (.question | capture("\\$(?<p>[0-9,]+)") | .p | gsub(","; "") | tonumber), yes: (.outcomePrices | fromjson | .[0] | tonumber), volume: (.volume | tonumber)}] | map(select(.volume >= 100000)) | sort_by(.strike)'
```

**数据质量过滤**：Volume < $100K 的市场不采信。

- [ ] 2.5 获取币安双币赢产品

从 config.json 读取 API Key：

```bash
# 低买（PUT）- BTC
TIMESTAMP=$(date +%s000)
PARAMS="optionType=PUT&exercisedCoin=BTC&investCoin=USDT&timestamp=${TIMESTAMP}&recvWindow=5000"
SIGNATURE=$(echo -n "$PARAMS" | openssl dgst -sha256 -hmac "$BINANCE_SECRET_KEY" | cut -d' ' -f2)
curl -s -H "X-MBX-APIKEY: $BINANCE_API_KEY" \
  "https://api.binance.com/sapi/v1/dci/product/list?${PARAMS}&signature=${SIGNATURE}" | \
  jq '[.list[] | {strikePrice: (.strikePrice | tonumber), duration, apr: (.apr | tonumber)}] | group_by(.duration) | .[] | {duration: .[0].duration, products: (sort_by(-.apr) | .[0:3])}'

# 低买（PUT）- ETH
PARAMS="optionType=PUT&exercisedCoin=ETH&investCoin=USDT&timestamp=${TIMESTAMP}&recvWindow=5000"
SIGNATURE=$(echo -n "$PARAMS" | openssl dgst -sha256 -hmac "$BINANCE_SECRET_KEY" | cut -d' ' -f2)
curl -s -H "X-MBX-APIKEY: $BINANCE_API_KEY" \
  "https://api.binance.com/sapi/v1/dci/product/list?${PARAMS}&signature=${SIGNATURE}" | \
  jq '[.list[] | {strikePrice: (.strikePrice | tonumber), duration, apr: (.apr | tonumber)}] | group_by(.duration) | .[] | {duration: .[0].duration, products: (sort_by(-.apr) | .[0:3])}'

# 高卖（CALL）- BTC
PARAMS="optionType=CALL&exercisedCoin=BTC&investCoin=BTC&timestamp=${TIMESTAMP}&recvWindow=5000"
SIGNATURE=$(echo -n "$PARAMS" | openssl dgst -sha256 -hmac "$BINANCE_SECRET_KEY" | cut -d' ' -f2)
curl -s -H "X-MBX-APIKEY: $BINANCE_API_KEY" \
  "https://api.binance.com/sapi/v1/dci/product/list?${PARAMS}&signature=${SIGNATURE}" | \
  jq '[.list[] | {strikePrice: (.strikePrice | tonumber), duration, apr: (.apr | tonumber)}] | group_by(.duration) | .[] | {duration: .[0].duration, products: (sort_by(-.apr) | .[0:3])}'

# 高卖（CALL）- ETH
PARAMS="optionType=CALL&exercisedCoin=ETH&investCoin=ETH&timestamp=${TIMESTAMP}&recvWindow=5000"
SIGNATURE=$(echo -n "$PARAMS" | openssl dgst -sha256 -hmac "$BINANCE_SECRET_KEY" | cut -d' ' -f2)
curl -s -H "X-MBX-APIKEY: $BINANCE_API_KEY" \
  "https://api.binance.com/sapi/v1/dci/product/list?${PARAMS}&signature=${SIGNATURE}" | \
  jq '[.list[] | {strikePrice: (.strikePrice | tonumber), duration, apr: (.apr | tonumber)}] | group_by(.duration) | .[] | {duration: .[0].duration, products: (sort_by(-.apr) | .[0:3])}'
```

- [ ] 2.6 获取宏观事件（Web Search）

搜索词：
```
US economic calendar this week CPI NFP FOMC {当前月份年份}
```

提取：
- 🔴 高影响: CPI/PPI、非农(NFP)、FOMC
- 🟡 中影响: 大型期权到期
- 🟢 低影响: 初请失业金

---

### Step 3: 计算推荐

- [ ] 3.1 低买推荐计算

对于每个币安 PUT 产品：
1. 找到对应行权价的 Polymarket Yes 概率
2. 跌破概率 = 1 - Yes
3. 按推荐标准分类：
   - < 10% → 推荐
   - 10-20% → 备选
   - > 20% → 不建议
4. 每个期限选跌破概率 < 20% 且 APR 最高的

- [ ] 3.2 高卖推荐计算

对于每个币安 CALL 产品：
1. 找到对应行权价的 Polymarket Yes 概率
2. 涨破概率 = Yes（Polymarket 问的是"会涨到 $X"）
3. 按推荐标准分类：
   - < 10% → 推荐
   - 10-20% → 备选
   - > 20% → 不建议
4. 每个期限选涨破概率 < 20% 且 APR 最高的

---

### Step 4: 输出推荐

严格使用以下格式：

```
📊 双币赢推荐 — {YYYY-MM-DD}

当前: BTC ${价格} | ETH ${价格}
DVOL: BTC {dvol}% | ETH {dvol}%

━━ BTC 低买推荐 ━━

{期限} | ${行权价} | APR {apr}% | 跌破概率 {prob}% | {推荐/备选/不建议}
...

━━ ETH 低买推荐 ━━

{期限} | ${行权价} | APR {apr}% | 跌破概率 {prob}% | {推荐/备选/不建议}
...

━━ BTC 高卖推荐 ━━

{期限} | ${行权价} | APR {apr}% | 涨破概率 {prob}% | {推荐/备选/不建议}
...

━━ ETH 高卖推荐 ━━

{期限} | ${行权价} | APR {apr}% | 涨破概率 {prob}% | {推荐/备选/不建议}
...

━━ Deribit OI 参考 ━━
• BTC ${价位} 有 {oi} OI 防线
• ETH ${价位} 有 {oi} OI 防线

━━ 本周宏观事件 ━━
• {日期} {事件} {影响级别}
...

━━ 风险提示 ━━
• DVOL > 60 时建议减仓
• DVOL > 80 时建议观望
• {其他风险提示}

不构成投资建议，DYOR。

选择产品后输入：{币种} {方向} {期限} {金额}
示例：ETH 低买 3天 1000
```

---

### Step 5: 执行申购

- [ ] 5.1 用户选择产品

用户输入格式：`{币种} {方向} {期限} {金额}`
示例：`ETH 低买 3天 1000`

- [ ] 5.2 确认产品详情

显示：
```
确认申购：
币种: ETH
方向: 低买（PUT）
行权价: $2,100
期限: 3天
APR: 124%
金额: 1000 USDT
跌破概率: 10%

⚠️ 如果到期时 ETH 低于 $2,100：
你的 1000 USDT 会按 $2,100 买入 ETH。

输入 CONFIRM 确认申购：
```

- [ ] 5.3 执行申购

用户输入 CONFIRM 后：

```bash
TIMESTAMP=$(date +%s000)
PARAMS="id={product_id}&orderId={order_id}&depositAmount={amount}&timestamp=${TIMESTAMP}&recvWindow=5000"
SIGNATURE=$(echo -n "$PARAMS" | openssl dgst -sha256 -hmac "$BINANCE_SECRET_KEY" | cut -d' ' -f2)
curl -s -X POST -H "X-MBX-APIKEY: $BINANCE_API_KEY" \
  "https://api.binance.com/sapi/v1/dci/product/subscribe?${PARAMS}&signature=${SIGNATURE}"
```

- [ ] 5.4 记录到历史

追加到 `~/dual-investment-advisor/history.json`：

```json
{
  "time": "{ISO时间}",
  "coin": "{币种}",
  "direction": "{低买/高卖}",
  "strike": {行权价},
  "duration": "{期限}",
  "apr": {apr},
  "amount": {金额},
  "product_id": "{product_id}",
  "settle_date": "{结算日期}",
  "settle_price": null,
  "result": null,
  "profit": null
}
```

---

### Step 6: 到期提醒

- [ ] 6.1 检查到期产品

读取 `~/dual-investment-advisor/history.json`，找出 settle_date <= 今天且 result 为 null 的记录。

- [ ] 6.2 查询结算结果

调用币安 API 查询持仓/历史订单，获取结算价和结果。

- [ ] 6.3 更新历史记录

更新 history.json 中的 settle_price、result、profit。

- [ ] 6.4 输出结算报告

```
📊 到期结算 — {日期}

{上次买入}: {币种} {方向} ${行权价} | {期限} | APR {apr}%
结算价: ${结算价}
结果: {✅ 未行权 / ❌ 已行权}，收益 {+/-}${收益}

━━ 历史战绩 ━━
总次数: {n} | 胜率: {rate}% | 累计: {+/-}${total} | 年化: {apr}%
```

---

## 本地存储

**配置文件** `~/dual-investment-advisor/config.json`：
```json
{
  "binance_api_key": "xxx",
  "binance_secret_key": "xxx",
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
    "product_id": "xxx",
    "settle_date": "2026-03-13",
    "settle_price": 68200,
    "result": "未行权",
    "profit": 135
  }
]
```

---

## 安全规则

- API Key 不完整显示（只显示前4位和后4位）
- 申购前必须用户输入 CONFIRM
- 所有分析标注"不构成投资建议，DYOR"
- API 失败时明确说哪一步失败了，不编造数据
