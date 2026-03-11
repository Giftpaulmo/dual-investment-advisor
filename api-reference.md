# API 参考文档

## 币安双币赢 API（需要 Key）

Base URL: `https://api.binance.com`

所有 `/sapi/` 端点需要签名认证。

### 签名方法（HMAC-SHA256）

```bash
# 1. 构建 query string
TIMESTAMP=$(date +%s000)
PARAMS="optionType=PUT&exercisedCoin=BTC&investCoin=USDT&timestamp=${TIMESTAMP}&recvWindow=5000"

# 2. 用 Secret Key 签名
SIGNATURE=$(echo -n "$PARAMS" | openssl dgst -sha256 -hmac "$BINANCE_SECRET_KEY" | cut -d' ' -f2)

# 3. 发送请求
curl -s -H "X-MBX-APIKEY: $BINANCE_API_KEY" \
  "https://api.binance.com/sapi/v1/dci/product/list?${PARAMS}&signature=${SIGNATURE}"
```

### 获取双币赢产品列表

```
GET /sapi/v1/dci/product/list
```

参数：
| 参数 | 必须 | 说明 |
|------|------|------|
| optionType | 是 | "CALL" 或 "PUT" |
| exercisedCoin | 是 | "BTC" 或 "ETH" |
| investCoin | 是 | "USDT"(低买) 或 "BTC"/"ETH"(高卖) |
| timestamp | 是 | 毫秒时间戳 |
| signature | 是 | HMAC-SHA256 签名 |

返回字段：
| 字段 | 说明 |
|------|------|
| id | 产品 ID |
| investCoin | 投入币种 |
| exercisedCoin | 标的币种 |
| strikePrice | 行权价 |
| duration | 期限（天） |
| settleDate | 结算日期 (timestamp ms) |
| apr | 年化收益率 (小数，如 0.6076 = 60.76%) |
| orderId | 订单 ID（申购时用） |
| minAmount | 最小申购量 |
| maxAmount | 最大申购量 |
| canPurchase | 是否可申购 |
| optionType | PUT 或 CALL |

### 申购双币赢

```
POST /sapi/v1/dci/product/subscribe
```

参数：
| 参数 | 必须 | 说明 |
|------|------|------|
| id | 是 | 产品 ID |
| orderId | 是 | 从 product/list 获取 |
| depositAmount | 是 | 申购金额 |
| autoCompoundPlan | 否 | "STANDARD" 或 "ADVANCE"（自动复投） |
| timestamp | 是 | 毫秒时间戳 |
| signature | 是 | HMAC-SHA256 签名 |

**⚠️ 必须让用户输入 CONFIRM 后才能调用此端点。**

### 查询持仓

```
GET /sapi/v1/dci/product/positions
```

### 查询账户

```
GET /sapi/v1/dci/product/accounts
```

---

## Deribit 公开 API（不需要 Key）

Base URL: `https://www.deribit.com/api/v2`

### 指数价格
```
GET /public/get_index_price?index_name=btc_usd
```

### 期权 Book Summary（核心）
```
GET /public/get_book_summary_by_currency?currency=BTC&kind=option
```
返回所有活跃期权的 OI、mark_price、mark_iv、volume 等。

### DVOL 波动率指数
```
GET /public/get_volatility_index_data?currency=BTC&start_timestamp={ms}&end_timestamp={ms}&resolution=3600
```

### 所有活跃期权合约
```
GET /public/get_instruments?currency=BTC&kind=option&expired=false
```

### 特定期权 Ticker
```
GET /public/ticker?instrument_name=BTC-27MAR26-60000-P
```

Deribit 期权命名规则：`{币种}-{到期日}-{行权价}-{C或P}`
- C = Call（看涨）
- P = Put（看跌）
- 到期日格式：27MAR26 = 2026年3月27日

### 到期日规律
- 每周五 08:00 UTC：周度到期
- 每月最后一个周五：月度到期
- 3/6/9/12月最后周五：季度到期（量最大，重点关注）

---

## Polymarket Gamma API（不需要 Key）

Base URL: `https://gamma-api.polymarket.com`

### 获取活跃事件
```
GET /events?active=true&closed=false&tag_slug=crypto&limit=50
```

### 获取活跃市场
```
GET /markets?active=true&closed=false&limit=50
```

返回字段：
| 字段 | 说明 |
|------|------|
| question | 预测问题 |
| outcomePrices | Yes/No 价格（即概率） |
| volume | 交易量 |
| outcomes | 结果选项 |

### 关键市场类型
- **Above/Below** — "Will BTC be above $X by date?" → 直接概率
- **Price Range** — "What price will BTC hit in March?" → 各区间概率
- **Hit Price** — "Will BTC hit $X?" → 触达概率

Polymarket crypto 页面：https://polymarket.com/crypto
可以直接浏览当前所有 BTC/ETH 价格预测市场。
