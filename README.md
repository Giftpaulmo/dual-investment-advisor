# 🎯 Dual Investment Advisor — 双币赢智能顾问

> 结合 Polymarket 预测概率 + Deribit 期权预警 + 宏观事件风控，为币安双币赢用户提供数据驱动的策略建议。

**一句话说明：** 不是展示数据的仪表盘，而是直接告诉你"买哪个行权价、为什么、现在安不安全"。

---

## 这个 Skill 解决什么问题

你在币安买双币赢的时候，面对一堆行权价和 APR，怎么选？

大多数人靠感觉：APR 高的看着爽就买了。但 APR 高 = 被行权风险高，你可能不知道自己在赌什么。

这个 Skill 帮你做三件事：

1. **量化"安全"到底有多安全** — 用 Polymarket 真金白银投票的概率告诉你，BTC 跌到某个价位的概率到底是多少
2. **提前预警波动风险** — Deribit 大型期权到期、CPI/非农/FOMC 等宏观事件，自动搜索并提醒
3. **直接推荐+一键申购** — 不用你自己对比三个平台，给出"推荐/观望/不建议"的明确结论，确认后直接下单

---

## 核心逻辑

```
Polymarket 概率（主决策）
  "BTC 3月底跌到 $60K 的概率是 32%"
  → 真人用真钱投票，比任何模型都真实
         +
Deribit 期权数据（预警层）
  "3/27 季度大到期，$55K 有 3,103 BTC 的 PUT OI"
  → 市场在哪里设了防线，到期日前后要注意
         +
宏观事件（风控层）
  "周三有 CPI 数据，建议等公布后再续期"
  → web search 自动获取，不需要额外 API
         ↓
匹配币安双币赢 → 推荐具体产品 → CONFIRM → 申购
```

### 为什么需要 Polymarket？

币安双币赢的 APR 底层是期权定价（Black-Scholes），Deribit 的 PUT 价格也是期权定价。两者同源，对比没意义。

但 Polymarket 是完全不同的市场——预测市场的参与者和期权市场的参与者不一样。当两个独立市场给出一致的判断时，信号更可靠。当它们出现分歧时，就是机会或风险。

---

## 数据源

| 数据源 | 需要 Key？ | 用途 |
|--------|-----------|------|
| Polymarket Gamma API | ❌ 不需要 | BTC/ETH 各价位的触达概率 |
| Deribit Public API | ❌ 不需要 | 期权 OI 分布、到期规模、DVOL |
| Web Search | ❌ 不需要 | 宏观经济日历、财报日历 |
| Binance API | ✅ 用户自己的 Key | 双币赢产品列表 + 申购 |

**用户只需要一个币安 API Key，其他全部免费公开。**

---

## 文件结构

```
dual-investment-advisor/
├── SKILL.md                      ← 核心：agent 的决策逻辑
├── scripts/
│   └── fetch_data.sh             ← 一键拉取 Deribit + Polymarket 数据
├── references/
│   └── api-reference.md          ← API 端点和签名方法参考
├── README.md                     ← 你正在看的这个
└── LICENSE                       ← MIT
```

---

## 快速开始

### 1. 安装依赖

```bash
# Mac
brew install curl jq

# Ubuntu/Linux
sudo apt install curl jq
```

### 2. 安装 Skill

```bash
mkdir -p ~/.openclaw/skills/dual-investment-advisor
cd ~/.openclaw/skills/dual-investment-advisor
git clone https://github.com/Giftpaulmo/dual-investment-advisor.git .
chmod +x scripts/fetch_data.sh
```

### 3. 配置币安 API Key

在 `openclaw.json` 或 `~/.openclaw/config.json` 中添加：

```json
{
  "skills": {
    "entries": {
      "dual-investment-advisor": {
        "enabled": true,
        "env": {
          "BINANCE_API_KEY": "你的 API Key",
          "BINANCE_SECRET_KEY": "你的 Secret Key"
        }
      }
    }
  }
}
```

> ⚠️ 创建 API Key 时：✅ 开启读取 + 现货交易权限，❌ **关闭提现权限**（安全底线）

### 4. 测试

```bash
# 测试数据脚本
bash scripts/fetch_data.sh

# 跟 agent 对话
# "帮我看看这周 BTC 双币赢买什么好"
```

---

## 使用示例

| 你说 | agent 做什么 |
|------|-------------|
| "帮我看看这周双币赢" | 完整周报：概率 + 事件 + 推荐 |
| "BTC 6万的低买值得买吗" | 针对性分析该行权价的安全度 |
| "这周有什么风险事件" | 搜索 CPI/非农/FOMC/财报 |
| "上一期到期了要续吗" | 重新分析市场变化，给续期建议 |
| "帮我买 $55000 的 BTC 低买" | 展示详情 → 确认风险 → CONFIRM → 申购 |

### 输出示例

```
📊 双币赢周报 — 2026年3月第2周

━━ 本周风险日历 ━━
  周三 3/12 — CPI 数据公布 🔴 高影响
  3/27 — Q1季度期权大到期 ⚠️ 提前关注

━━ Polymarket 概率 (BTC 3月底) ━━
  ↓$65,000 → 48% | ↓$60,000 → 32% | ↓$55,000 → 14%

━━ BTC 双币赢推荐 ━━

🟢 推荐 | 低买 $55,000 | 3天 | APR 8.2%
  Polymarket 仅 14% 触达 | Deribit 最大 OI 防线
  ⭐⭐⭐⭐⭐ 极安全
  → 保守首选

🟡 观望 | 低买 $62,000 | 3天 | APR 35.2%
  Polymarket 38% 触达 | 本周有 CPI
  ⭐⭐⭐ 中等
  → 等 CPI 公布后再考虑
```

---

## 安全说明

- API Key 只存在你本地，不上传任何服务器
- 申购操作必须用户输入 `CONFIRM` 才执行
- 建议创建 API Key 时 **永远关闭提现权限**
- 所有分析不构成投资建议，DYOR

---

## 参与币安 Skills Hub

本项目是为 [Binance Skills Hub](https://github.com/binance/binance-skills-hub) 活动开发的独立 Skill。

如果你觉得有用，欢迎 Star ⭐ 或提 Issue 反馈。

---

## License

MIT
