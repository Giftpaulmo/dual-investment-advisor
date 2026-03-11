#!/usr/bin/env bash
# dual-investment-advisor: 数据拉取脚本
# 从 Deribit (公开) 和 Polymarket (公开) 获取实时数据
# 不需要任何 API Key

set -euo pipefail

DERIBIT_URL="https://www.deribit.com/api/v2"
POLYMARKET_URL="https://gamma-api.polymarket.com"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ===== Deribit: 期权 OI 数据 =====
fetch_deribit_oi() {
    local currency=$1  # BTC 或 ETH
    echo -e "${CYAN}━━ Deribit ${currency} 期权数据 ━━${NC}"

    # 获取当前指数价格
    local index_name=$(echo "${currency}" | tr '[:upper:]' '[:lower:]')_usd
    local price_data=$(curl -s "${DERIBIT_URL}/public/get_index_price?index_name=${index_name}" 2>/dev/null)
    local current_price=$(echo "$price_data" | jq -r '.result.index_price // empty' 2>/dev/null)

    if [ -n "$current_price" ]; then
        printf "  当前价格: \$%s\n" "$(printf '%.0f' "$current_price")"
    else
        echo "  ⚠️ 无法获取价格"
        return 1
    fi

    # 获取所有活跃期权的 book summary
    local options_data=$(curl -s "${DERIBIT_URL}/public/get_book_summary_by_currency?currency=${currency}&kind=option" 2>/dev/null)

    if [ -z "$options_data" ] || [ "$(echo "$options_data" | jq -r '.result // empty')" = "" ]; then
        echo "  ⚠️ 无法获取期权数据"
        return 1
    fi

    # 提取 PUT 期权，按到期日分组，计算每个行权价的 OI
    echo ""
    echo "  📊 PUT OI 分布 (Top 10):"

    # 解析所有 PUT，按 OI 排序取前 10
    echo "$options_data" | jq -r '
        .result
        | map(select(.instrument_name | test("-P$")))
        | map({
            name: .instrument_name,
            oi: (.open_interest // 0),
            mark: (.mark_price // 0),
            iv: (.mark_iv // 0)
        })
        | sort_by(-.oi)
        | .[0:10]
        | .[]
        | "    \(.name) | OI: \(.oi) | Mark: \(.mark) | IV: \(.iv)%"
    ' 2>/dev/null

    # 按到期日统计 OI 总量
    echo ""
    echo "  📅 到期日 OI 汇总:"

    echo "$options_data" | jq -r '
        .result
        | map(select(.instrument_name | test("-P$")))
        | group_by(.instrument_name | split("-")[1])
        | map({
            expiry: .[0].instrument_name | split("-")[1],
            total_oi: (map(.open_interest // 0) | add),
            count: length
        })
        | sort_by(-.total_oi)
        | .[0:5]
        | .[]
        | "    \(.expiry) | 总 PUT OI: \(.total_oi) \(if .total_oi > 1000 then "⚠️ 大量持仓" else "" end)"
    ' 2>/dev/null

    # CALL OI top 5 (简要)
    echo ""
    echo "  📊 CALL OI 分布 (Top 5):"

    echo "$options_data" | jq -r '
        .result
        | map(select(.instrument_name | test("-C$")))
        | map({
            name: .instrument_name,
            oi: (.open_interest // 0)
        })
        | sort_by(-.oi)
        | .[0:5]
        | .[]
        | "    \(.name) | OI: \(.oi)"
    ' 2>/dev/null

    echo ""
}

# ===== Polymarket: BTC/ETH 价格预测 =====
fetch_polymarket() {
    echo -e "${CYAN}━━ Polymarket 加密货币价格预测 ━━${NC}"

    # 搜索 crypto 相关的活跃市场
    local markets_data=$(curl -s "${POLYMARKET_URL}/events?active=true&closed=false&limit=100&tag_slug=crypto" 2>/dev/null)

    if [ -z "$markets_data" ] || [ "$markets_data" = "[]" ]; then
        # 备选：直接搜索 markets
        markets_data=$(curl -s "${POLYMARKET_URL}/markets?active=true&closed=false&limit=100" 2>/dev/null)
    fi

    if [ -z "$markets_data" ]; then
        echo "  ⚠️ 无法获取 Polymarket 数据"
        return 1
    fi

    # 提取 BTC 相关市场
    echo ""
    echo "  🔮 BTC 价格预测市场:"

    echo "$markets_data" | jq -r '
        if type == "array" then
            [.[] |
                if .markets then
                    .markets[] | select(
                        (.question // "" | test("(?i)bitcoin|btc")) and
                        (.question // "" | test("(?i)price|above|below|hit|reach"))
                    )
                else
                    select(
                        (.question // "" | test("(?i)bitcoin|btc")) and
                        (.question // "" | test("(?i)price|above|below|hit|reach"))
                    )
                end
            ] |
            sort_by(-.volume) |
            .[0:10] |
            .[] |
            "    \(.question // "N/A")\n      Yes: \(.outcomePrices // "N/A") | Vol: $\(.volume // "0")"
        else
            "    无数据"
        end
    ' 2>/dev/null || echo "    解析失败，请手动查看 polymarket.com/crypto"

    # 提取 ETH 相关市场
    echo ""
    echo "  🔮 ETH 价格预测市场:"

    echo "$markets_data" | jq -r '
        if type == "array" then
            [.[] |
                if .markets then
                    .markets[] | select(
                        (.question // "" | test("(?i)ethereum|eth")) and
                        (.question // "" | test("(?i)price|above|below|hit|reach"))
                    )
                else
                    select(
                        (.question // "" | test("(?i)ethereum|eth")) and
                        (.question // "" | test("(?i)price|above|below|hit|reach"))
                    )
                end
            ] |
            sort_by(-.volume) |
            .[0:10] |
            .[] |
            "    \(.question // "N/A")\n      Yes: \(.outcomePrices // "N/A") | Vol: $\(.volume // "0")"
        else
            "    无数据"
        end
    ' 2>/dev/null || echo "    解析失败，请手动查看 polymarket.com/crypto"

    echo ""
}

# ===== Deribit: DVOL 波动率指数 =====
fetch_dvol() {
    echo -e "${CYAN}━━ Deribit DVOL (30天隐含波动率) ━━${NC}"

    for currency in BTC ETH; do
        local end_ts=$(date +%s)000
        local start_ts=$(( $(date +%s) - 86400 ))000  # 24小时前

        local dvol_data=$(curl -s "${DERIBIT_URL}/public/get_volatility_index_data?currency=${currency}&start_timestamp=${start_ts}&end_timestamp=${end_ts}&resolution=3600" 2>/dev/null)

        local latest_dvol=$(echo "$dvol_data" | jq -r '.result.data[-1][4] // empty' 2>/dev/null)

        if [ -n "$latest_dvol" ]; then
            printf "  %s DVOL: %.1f%%\n" "$currency" "$latest_dvol"
        else
            echo "  $currency DVOL: 获取失败"
        fi
    done
    echo ""
}

# ===== 主执行 =====
main() {
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   双币赢智能顾问 - 数据拉取         ║${NC}"
    echo -e "${GREEN}║   $(date '+%Y-%m-%d %H:%M UTC')             ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""

    fetch_dvol
    fetch_deribit_oi "BTC"
    fetch_deribit_oi "ETH"
    fetch_polymarket

    echo -e "${YELLOW}━━ 数据拉取完成，请结合 web search 结果进行分析 ━━${NC}"
}

main "$@"
