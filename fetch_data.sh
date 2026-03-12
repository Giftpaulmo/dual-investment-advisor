#!/usr/bin/env bash
# dual-investment-advisor: 数据拉取脚本 v3.0
#
# 核心逻辑：
# 1. Polymarket 概率决定"安全区" — 触达概率 < 15% 的行权价是安全的
# 2. 在安全区里选 APR 最高的产品
# 3. Deribit OI 作为预警层，宏观事件作为风控层

set -euo pipefail

# ===== API 配置 =====
DERIBIT_URL="https://www.deribit.com/api/v2"
POLYMARKET_CLI="${POLYMARKET_CLI:-polymarket}"  # 可通过环境变量指定路径

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ===== 通用请求函数（带重试）=====
safe_curl() {
    local url=$1
    local max_retries=${2:-2}
    local timeout=${3:-8}

    for i in $(seq 1 $max_retries); do
        local response=$(curl -s --connect-timeout $timeout --max-time 15 "$url" 2>/dev/null)
        if [ -n "$response" ] && [ "$response" != "null" ] && [ "$response" != "[]" ]; then
            echo "$response"
            return 0
        fi
        sleep 1
    done
    return 1
}

# ===== 格式化数字（兼容 macOS）=====
format_number() {
    local num=$1
    # macOS printf 不支持 %'d，用 awk 代替
    echo "$num" | awk '{printf "%\047.0f", $1}' 2>/dev/null || printf "%.0f" "$num"
}

# ===== Deribit: 获取当前价格 =====
get_current_price() {
    local currency=$1
    local index_name=$(echo "${currency}" | tr '[:upper:]' '[:lower:]')_usd
    safe_curl "${DERIBIT_URL}/public/get_index_price?index_name=${index_name}" | jq -r '.result.index_price // empty'
}

# ===== Deribit: DVOL 波动率指数 =====
fetch_dvol() {
    echo -e "${CYAN}━━ 波动率指数 (DVOL) ━━${NC}"
    for cur in BTC ETH; do
        local dvol=$(safe_curl "${DERIBIT_URL}/public/get_volatility_index_data?currency=${cur}&resolution=3600" | jq -r '.result.data[-1][4] // "N/A"')
        if [ "$dvol" != "N/A" ]; then
            dvol=$(printf "%.1f" "$dvol")
        fi
        printf "  %s: %s%%\n" "$cur" "$dvol"
    done
    echo ""
}

# ===== Deribit: 期权 OI 防线分析 =====
fetch_deribit_oi() {
    local currency=$1
    local current_price=$2

    echo -e "${CYAN}━━ Deribit ${currency} PUT OI 防线 ━━${NC}"
    printf "  当前价格: \$%.0f\n" "$current_price"

    local options_data=$(safe_curl "${DERIBIT_URL}/public/get_book_summary_by_currency?currency=${currency}&kind=option")

    if [ -z "$options_data" ]; then
        echo -e "  ${RED}⚠️ 无法获取期权数据${NC}"
        return 1
    fi

    echo -e "  ${YELLOW}高 OI 行权价（大资金防线）:${NC}"
    echo "$options_data" | jq -r --argjson spot "$current_price" '
        .result
        | map(select(.instrument_name | test("-P$")))
        | map({
            name: .instrument_name,
            strike: (.instrument_name | split("-")[2] | tonumber),
            oi: (.open_interest // 0)
        })
        | map(select(.strike < $spot))  # 只看低于现价的 PUT
        | sort_by(-.oi)
        | .[0:6]
        | .[]
        | .distance = ((($spot - .strike) / $spot) * 100)
        | "    $\(.strike) | OI: \(.oi) | Distance: \(.distance | . * 10 | round / 10)%"
    ' 2>/dev/null || echo "    解析失败"
    echo ""
}

# ===== Polymarket: 使用官方 CLI 获取价格预测 =====
fetch_polymarket() {
    local coin=$1      # bitcoin 或 ethereum
    local symbol=$2    # BTC 或 ETH

    echo -e "${CYAN}━━ Polymarket ${symbol} 价格预测 ━━${NC}"

    # 检查 CLI 是否可用
    if ! command -v "$POLYMARKET_CLI" &> /dev/null; then
        echo -e "  ${RED}❌ polymarket CLI 未安装${NC}"
        echo "  安装方法: brew install polymarket"
        echo "  或: curl -sSL https://raw.githubusercontent.com/Polymarket/polymarket-cli/main/install.sh | sh"
        return 1
    fi

    # 搜索当前活跃的价格预测市场
    local markets_json=$("$POLYMARKET_CLI" markets search "${coin} above" -o json 2>/dev/null)

    if [ -z "$markets_json" ] || [ "$markets_json" == "[]" ]; then
        echo -e "  ${RED}❌ 未找到相关市场${NC}"
        return 1
    fi

    # 创建临时 jq 脚本（避免 shell 转义问题）
    local jq_script=$(mktemp)
    cat > "$jq_script" << 'EOF'
[.[] | select(.active == true and .closed == false and .outcomePrices != null and .outcomePrices != "")]
| map(select(.question | test("above \\$[0-9]"; "i")))
| map({
    strike: (.question | capture("\\$(?<p>[0-9,]+)") | .p | gsub(","; "") | tonumber),
    yes: (try ((.outcomePrices | fromjson)[0] | tonumber * 100) catch 0),
    volume: (try (.volume | tonumber) catch 0)
})
| group_by(.strike)
| map(max_by(.volume))
| sort_by(.strike)
| .[]
| "\(.strike)|\(.yes | round)|\(.volume / 1000 | floor)"
EOF

    # 解析并输出
    echo "$markets_json" | jq -rf "$jq_script" 2>/dev/null | while IFS='|' read -r strike yes vol; do
        # 根据概率添加安全标记
        local safety=""
        if [ "$yes" -ge 85 ]; then
            safety="${GREEN}⭐⭐⭐⭐⭐${NC}"
        elif [ "$yes" -ge 70 ]; then
            safety="${GREEN}⭐⭐⭐⭐${NC}"
        elif [ "$yes" -ge 50 ]; then
            safety="${YELLOW}⭐⭐⭐${NC}"
        else
            safety="${RED}⭐⭐${NC}"
        fi
        echo -e "    \$${strike} → Yes: ${yes}% (会涨到) | Vol: \$${vol}K | ${safety}"
    done

    rm -f "$jq_script"

    echo ""
}

# ===== 安全评级说明 =====
print_safety_guide() {
    echo -e "${CYAN}━━ 安全评级标准（基于 Polymarket 触达概率）━━${NC}"
    echo ""
    echo -e "  ${GREEN}⭐⭐⭐⭐⭐ 极安全${NC} — Yes(触达) < 15%  → 放心买，在安全区选 APR 最高的"
    echo -e "  ${GREEN}⭐⭐⭐⭐${NC}   安全   — Yes(触达) 15-30% → 可以买，注意仓位"
    echo -e "  ${YELLOW}⭐⭐⭐${NC}     中等   — Yes(触达) 30-50% → 谨慎，降低行权价或等待"
    echo -e "  ${RED}⭐⭐${NC}       高风险 — Yes(触达) > 50%  → 不建议，风险太高"
    echo ""
}

# ===== 决策逻辑说明 =====
print_decision_logic() {
    echo -e "${CYAN}━━ 决策逻辑 ━━${NC}"
    echo -e "  ${BOLD}目标: 在安全范围内，选 APR 最高的产品${NC}"
    echo ""
    echo "  Step 1: 看 Polymarket 概率，确定\"安全区\""
    echo "          → 触达概率(Yes) < 15% 的行权价 = 安全"
    echo ""
    echo "  Step 2: 在安全区里，选 APR 最高的"
    echo "          → 同样安全，当然选收益高的"
    echo ""
    echo "  Step 3: 检查本周风险事件"
    echo "          → 有 CPI/FOMC → 安全阈值收紧到 Yes < 10%"
    echo "          → 无重大事件 → 正常 Yes < 15% 阈值"
    echo ""
    echo -e "  ${YELLOW}APR 计算公式:${NC}"
    echo "    真实 APR = 单期收益率 × (365 / 投资天数)"
    echo "    示例: 3天期单期 0.5% → 年化 = 0.5% × (365/3) = 60.8%"
    echo ""
}

# ===== 主函数 =====
main() {
    echo -e "${GREEN}══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   双币赢智能顾问 v3.0  $(date '+%Y-%m-%d %H:%M')${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════${NC}"
    echo ""

    # 获取当前价格
    local btc_price=$(get_current_price "BTC")
    local eth_price=$(get_current_price "ETH")

    if [ -z "$btc_price" ]; then
        echo -e "${RED}⚠️ 无法获取 BTC 价格，请检查网络${NC}"
        btc_price="0"
    fi
    if [ -z "$eth_price" ]; then
        echo -e "${RED}⚠️ 无法获取 ETH 价格，请检查网络${NC}"
        eth_price="0"
    fi

    echo -e "${BOLD}当前价格:${NC} BTC \$$(printf '%.0f' "$btc_price") | ETH \$$(printf '%.0f' "$eth_price")"
    echo ""

    # 获取数据
    fetch_dvol
    fetch_deribit_oi "BTC" "$btc_price"
    fetch_polymarket "Bitcoin" "BTC"
    fetch_deribit_oi "ETH" "$eth_price"
    fetch_polymarket "Ethereum" "ETH"

    # 输出决策指南
    print_safety_guide
    print_decision_logic

    echo -e "${GREEN}══════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}下一步:${NC}"
    echo "  1. 根据 Polymarket 概率，确定安全行权价（Yes < 15%）"
    echo "  2. 查看币安双币赢，在安全区选 APR 最高的产品"
    echo "  3. Web 搜索本周宏观事件（CPI/NFP/FOMC）"
    echo "  4. 确认后申购"
    echo ""
}

main "$@"
