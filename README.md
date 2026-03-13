# 🎯 Dual Investment Advisor — 双币赢智能顾问 v3.0

> 在尽可能安全的情况下，帮你多赚钱。

结合 Polymarket 预测概率 + Deribit 期权预警 + 宏观事件风控，为币安双币赢用户提供数据驱动的策略建议。

**核心逻辑：用 Polymarket 概率确定"安全区"，在安全区里选 APR 最高的产品。**

---

## 这个工具解决什么问题

你在币安买双币赢的时候，面对一堆行权价和 APR，怎么选？

大多数人靠感觉：APR 高的看着爽就买了。但 APR 高 = 被行权风险高，极容易反复穿仓被"频繁收割"。

这个工具帮你做三件事：

1. **量化"安全"到底有多安全** — 用 Polymarket 真金白银投票的概率告诉你，BTC/ETH 跌到某个价位的概率到底是多少
2. **提前预警波动风险** — Deribit 大型期权到期、CPI/非农/FOMC 等宏观事件
3. **直接给出推荐** — 不用你自己对比，告诉你"买哪个行权价、为什么"

---

## 核心逻辑

```
Polymarket 概率（主决策）
  "BTC 在 $68,000 以上的概率是 98%"
  → 真人用真钱投票，比任何模型都真实
         +
Deribit 期权数据（预警层）
  "$60,000 有 8,874 BTC 的 PUT OI"
  → 市场在哪里设了防线
         +
宏观事件（风控层）
  "周三有 CPI 数据，安全阈值收紧"
  → web search 自动获取
         ↓
确定安全区（Polymarket Yes > 85%）→ 选 APR 最高的 → 推荐
```

### 安全评级标准

| Polymarket Yes 概率 | 安全评级 | 操作建议 |
|---------------------|---------|---------|
| > 85% | ⭐⭐⭐⭐⭐ 极安全 | 放心买，选这个区间 APR 最高的 |
| 70-85% | ⭐⭐⭐⭐ 安全 | 可以买，注意仓位 |
| 50-70% | ⭐⭐⭐ 中等 | 谨慎，降低行权价或等待 |
| < 50% | ⭐⭐ 高风险 | 不建议 |

---

## 快速开始

### 1. 安装依赖

```bash
# Mac
brew install curl jq

# 安装 Polymarket CLI
brew tap Polymarket/polymarket-cli https://github.com/Polymarket/polymarket-cli
brew install polymarket

# 或者手动安装 Polymarket CLI
mkdir -p ~/.local/bin
curl -sL "https://github.com/Polymarket/polymarket-cli/releases/download/v0.1.5/polymarket-v0.1.5-aarch64-apple-darwin.tar.gz" -o /tmp/polymarket.tar.gz
tar -xzf /tmp/polymarket.tar.gz -C /tmp
mv /tmp/polymarket ~/.local/bin/
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Intel Mac 用这个链接
# curl -sL "https://github.com/Polymarket/polymarket-cli/releases/download/v0.1.5/polymarket-v0.1.5-x86_64-apple-darwin.tar.gz" -o /tmp/polymarket.tar.gz
```

### 2. 克隆仓库

```bash
git clone https://github.com/Giftpaulmo/dual-investment-advisor.git
cd dual-investment-advisor
chmod +x fetch_data.sh
```

### 3. 运行

```bash
./fetch_data.sh
```

### 输出示例

```
══════════════════════════════════════════════
   双币赢智能顾问 v3.0  2026-03-12 18:37
══════════════════════════════════════════════

当前价格: BTC $70,365 | ETH $2,071

━━ Deribit BTC PUT OI 防线 ━━
  当前价格: $70365
  高 OI 行权价（大资金防线）:
    $60000 | OI: 8874.9 | Distance: 14.7%
    $55000 | OI: 5120.6 | Distance: 21.8%

━━ Polymarket BTC 价格预测 ━━
    $66000 → Yes: 99% (会涨到) | Vol: $268K | ⭐⭐⭐⭐⭐
    $68000 → Yes: 98% (会涨到) | Vol: $276K | ⭐⭐⭐⭐⭐
    $70000 → Yes: 64% (会涨到) | Vol: $325K | ⭐⭐⭐
    $72000 → Yes: 7% (会涨到) | Vol: $271K | ⭐⭐

━━ Polymarket ETH 价格预测 ━━
    $1900 → Yes: 99% (会涨到) | Vol: $53K | ⭐⭐⭐⭐⭐
    $2000 → Yes: 96% (会涨到) | Vol: $82K | ⭐⭐⭐⭐⭐
    $2100 → Yes: 20% (会涨到) | Vol: $63K | ⭐⭐
```

**解读**：
- BTC $68,000 行权价：Polymarket 98% 概率会涨到，⭐⭐⭐⭐⭐ 极安全 → 去币安选这个行权价 APR 最高的
- ETH $2,000 行权价：Polymarket 96% 概率会涨到，⭐⭐⭐⭐⭐ 极安全 → 推荐

---

## 两种使用方式

### 方式一：CLI 脚本（手动）

运行 `./fetch_data.sh` 获取数据，然后去币安手动申购。

### 方式二：AI Agent Skill（对话式）

在 Claude Code / Cursor 等支持 Skill 的 Agent 中使用，可以：
- 自动拉取数据并给出推荐
- 直接调用币安 API 申购
- 记录历史战绩和到期提醒

使用方法：
1. 配置 Binance API Key
2. 加载 `dual-investment.skill.md`
3. 对话即可

---

## 文件结构

```
dual-investment-advisor/
├── fetch_data.sh              ← CLI 数据拉取脚本
├── dual-investment.skill.md   ← AI Agent Skill（对话式）
├── SKILL.md                   ← Agent 决策逻辑参考
├── README.md                  ← 你正在看的这个
└── LICENSE                    ← MIT
```

---

## 数据源

| 数据源 | 需要 Key？ | 用途 |
|--------|-----------|------|
| Polymarket CLI | ❌ 不需要 | BTC/ETH 各价位的触达概率 |
| Deribit Public API | ❌ 不需要 | 期权 OI 分布、DVOL |
| Web Search | ❌ 不需要 | 宏观经济日历 |
| Binance API | ✅ 用户自己的 Key | 双币赢产品列表 + 申购（可选） |

---

## 为什么用 Polymarket？

币安双币赢的 APR 底层是期权定价，Deribit 的 PUT 价格也是期权定价。两者同源，对比没意义。

但 Polymarket 是完全不同的市场——预测市场的参与者和期权市场的参与者不一样。真金白银投票的概率，比任何模型都真实。

---

## 安全说明

- 所有数据来自公开 API，不需要你的任何密钥
- 如果要用币安 API 自动申购，**永远关闭提现权限**
- 所有分析不构成投资建议，DYOR

---

## License

MIT
