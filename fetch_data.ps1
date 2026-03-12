# dual-investment-advisor: Windows PowerShell 版本 v3.0
# 用法: powershell -ExecutionPolicy Bypass -File fetch_data.ps1

Write-Host "===============================================" -ForegroundColor Green
Write-Host "   双币赢智能顾问 v3.0  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""

# 获取当前价格
try {
    $btc_price = [math]::Round((Invoke-RestMethod "https://www.deribit.com/api/v2/public/get_index_price?index_name=btc_usd").result.index_price)
    $eth_price = [math]::Round((Invoke-RestMethod "https://www.deribit.com/api/v2/public/get_index_price?index_name=eth_usd").result.index_price)
    Write-Host "当前价格: BTC `$$btc_price | ETH `$$eth_price" -ForegroundColor White
} catch {
    Write-Host "无法获取价格，请检查网络" -ForegroundColor Red
    exit 1
}
Write-Host ""

# ===== Deribit PUT OI 防线 =====
function Get-DeribitOI {
    param($currency, $spot_price)

    Write-Host "━━ Deribit $currency PUT OI 防线 ━━" -ForegroundColor Cyan
    Write-Host "  当前价格: `$$spot_price"

    try {
        $options = (Invoke-RestMethod "https://www.deribit.com/api/v2/public/get_book_summary_by_currency?currency=$currency&kind=option").result

        # 过滤 PUT 期权，计算 OI 和 Distance
        $puts = $options | Where-Object { $_.instrument_name -match "-P$" } | ForEach-Object {
            $strike = [int]($_.instrument_name -split "-")[2]
            $distance = [math]::Round((($spot_price - $strike) / $spot_price) * 100, 1)
            [PSCustomObject]@{
                Strike = $strike
                OI = $_.open_interest
                Distance = $distance
            }
        } | Where-Object { $_.Strike -lt $spot_price } | Sort-Object -Property OI -Descending | Select-Object -First 6

        Write-Host "  高 OI 行权价（大资金防线）:" -ForegroundColor Yellow
        foreach ($p in $puts) {
            Write-Host "    `$$($p.Strike) | OI: $($p.OI) | Distance: $($p.Distance)%"
        }
    } catch {
        Write-Host "  无法获取期权数据" -ForegroundColor Red
    }
    Write-Host ""
}

# ===== Polymarket 价格预测 =====
function Get-PolymarketData {
    param($coin, $symbol)

    Write-Host "━━ Polymarket $symbol 价格预测 ━━" -ForegroundColor Cyan

    try {
        $markets = Invoke-RestMethod "https://gamma-api.polymarket.com/markets?active=true&closed=false&limit=200"

        # 过滤相关市场
        $filtered = $markets | Where-Object {
            $_.question -match "$coin.*above" -and
            $_.active -eq $true -and
            $_.closed -eq $false -and
            $_.outcomePrices -ne $null
        }

        # 解析并按行权价分组
        $results = @{}
        foreach ($m in $filtered) {
            if ($m.question -match '\$([0-9,]+)') {
                $strike = [int]($matches[1] -replace ',', '')
                $prices = $m.outcomePrices | ConvertFrom-Json
                $yes = [math]::Round($prices[0] * 100)
                $vol = [math]::Round($m.volume / 1000)

                # 只保留成交量最大的
                if (-not $results.ContainsKey($strike) -or $results[$strike].Vol -lt $vol) {
                    $results[$strike] = @{ Yes = $yes; Vol = $vol }
                }
            }
        }

        # 按行权价排序输出
        $sorted = $results.GetEnumerator() | Sort-Object { [int]$_.Key }
        foreach ($r in $sorted) {
            $strike = $r.Key
            $yes = $r.Value.Yes
            $vol = $r.Value.Vol

            # 安全评级
            if ($yes -ge 85) {
                $safety = "[极安全]"
                $color = "Green"
            } elseif ($yes -ge 70) {
                $safety = "[安全]"
                $color = "Green"
            } elseif ($yes -ge 50) {
                $safety = "[中等]"
                $color = "Yellow"
            } else {
                $safety = "[高风险]"
                $color = "Red"
            }

            Write-Host "    `$$strike -> Yes: $yes% | Vol: `$${vol}K | $safety" -ForegroundColor $color
        }
    } catch {
        Write-Host "  无法获取 Polymarket 数据" -ForegroundColor Red
        Write-Host "  请手动访问: https://polymarket.com/crypto/weekly" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ===== 执行 =====
Get-DeribitOI -currency "BTC" -spot_price $btc_price
Get-PolymarketData -coin "Bitcoin" -symbol "BTC"

Get-DeribitOI -currency "ETH" -spot_price $eth_price
Get-PolymarketData -coin "Ethereum" -symbol "ETH"

# ===== 决策指南 =====
Write-Host "━━ 安全评级标准 ━━" -ForegroundColor Cyan
Write-Host "  [极安全] Yes > 85% -> 放心买，选 APR 最高的" -ForegroundColor Green
Write-Host "  [安全]   Yes 70-85% -> 可以买，注意仓位" -ForegroundColor Green
Write-Host "  [中等]   Yes 50-70% -> 谨慎，降低行权价" -ForegroundColor Yellow
Write-Host "  [高风险] Yes < 50% -> 不建议" -ForegroundColor Red
Write-Host ""

Write-Host "━━ 下一步 ━━" -ForegroundColor Cyan
Write-Host "  1. 找到安全区（Yes > 85%）里行权价最高的"
Write-Host "  2. 去币安双币赢，选这个行权价 APR 最高的产品"
Write-Host "  3. 买入"
Write-Host ""
