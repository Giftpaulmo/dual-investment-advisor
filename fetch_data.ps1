# dual-investment-advisor: Windows PowerShell v3.0
# Usage: powershell -ExecutionPolicy Bypass -File fetch_data.ps1

Write-Host "===============================================" -ForegroundColor Green
Write-Host "   Dual Investment Advisor v3.0  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""

# Get current prices
try {
    $btc_price = [math]::Round((Invoke-RestMethod "https://www.deribit.com/api/v2/public/get_index_price?index_name=btc_usd").result.index_price)
    $eth_price = [math]::Round((Invoke-RestMethod "https://www.deribit.com/api/v2/public/get_index_price?index_name=eth_usd").result.index_price)
    Write-Host "Current Price: BTC $btc_price | ETH $eth_price" -ForegroundColor White
} catch {
    Write-Host "Cannot get price, check network" -ForegroundColor Red
    exit 1
}
Write-Host ""

# ===== Deribit PUT OI =====
function Get-DeribitOI {
    param([string]$currency, [int]$spot_price)

    Write-Host "== Deribit $currency PUT OI ==" -ForegroundColor Cyan
    Write-Host "  Current: $spot_price"

    try {
        $url = "https://www.deribit.com/api/v2/public/get_book_summary_by_currency?currency=" + $currency + "&kind=option"
        $options = (Invoke-RestMethod $url).result

        $puts = @()
        foreach ($opt in $options) {
            if ($opt.instrument_name -match "-P$") {
                $parts = $opt.instrument_name -split "-"
                $strike = [int]$parts[2]
                if ($strike -lt $spot_price) {
                    $distance = [math]::Round((($spot_price - $strike) / $spot_price) * 100, 1)
                    $puts += [PSCustomObject]@{
                        Strike = $strike
                        OI = $opt.open_interest
                        Distance = $distance
                    }
                }
            }
        }

        $puts = $puts | Sort-Object -Property OI -Descending | Select-Object -First 6

        Write-Host "  High OI Strikes:" -ForegroundColor Yellow
        foreach ($p in $puts) {
            Write-Host "    $($p.Strike) | OI: $($p.OI) | Distance: $($p.Distance)%"
        }
    } catch {
        Write-Host "  Cannot get options data" -ForegroundColor Red
    }
    Write-Host ""
}

# ===== Polymarket =====
function Get-PolymarketData {
    param([string]$coin, [string]$symbol)

    Write-Host "== Polymarket $symbol ==" -ForegroundColor Cyan

    try {
        $url = "https://gamma-api.polymarket.com/markets?active=true&closed=false&limit=200"
        $markets = Invoke-RestMethod $url

        $results = @{}
        foreach ($m in $markets) {
            if ($m.question -match "$coin.*above" -and $m.active -eq $true -and $m.closed -eq $false -and $m.outcomePrices -ne $null) {
                if ($m.question -match '\$(\d[\d,]*)') {
                    $strike = [int]($matches[1] -replace ',', '')
                    $prices = $m.outcomePrices | ConvertFrom-Json
                    $yes = [math]::Round($prices[0] * 100)
                    $vol = [math]::Round($m.volume / 1000)

                    if (-not $results.ContainsKey($strike) -or $results[$strike].Vol -lt $vol) {
                        $results[$strike] = @{ Yes = $yes; Vol = $vol }
                    }
                }
            }
        }

        $sorted = $results.GetEnumerator() | Sort-Object { [int]$_.Key }
        foreach ($r in $sorted) {
            $strike = $r.Key
            $yes = $r.Value.Yes
            $vol = $r.Value.Vol

            if ($yes -ge 85) {
                $safety = "[SAFE]"
                $color = "Green"
            } elseif ($yes -ge 70) {
                $safety = "[OK]"
                $color = "Green"
            } elseif ($yes -ge 50) {
                $safety = "[MEDIUM]"
                $color = "Yellow"
            } else {
                $safety = "[RISKY]"
                $color = "Red"
            }

            Write-Host "    $strike -> Yes: $yes% | Vol: ${vol}K | $safety" -ForegroundColor $color
        }
    } catch {
        Write-Host "  Cannot get Polymarket data" -ForegroundColor Red
        Write-Host "  Visit: https://polymarket.com/crypto/weekly" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ===== Run =====
Get-DeribitOI -currency "BTC" -spot_price $btc_price
Get-PolymarketData -coin "Bitcoin" -symbol "BTC"

Get-DeribitOI -currency "ETH" -spot_price $eth_price
Get-PolymarketData -coin "Ethereum" -symbol "ETH"

# ===== Guide =====
Write-Host "== Safety Rating ==" -ForegroundColor Cyan
Write-Host "  [SAFE]   Yes > 85% -> Buy it, pick highest APR" -ForegroundColor Green
Write-Host "  [OK]     Yes 70-85% -> Can buy, watch position" -ForegroundColor Green
Write-Host "  [MEDIUM] Yes 50-70% -> Careful, lower strike" -ForegroundColor Yellow
Write-Host "  [RISKY]  Yes < 50% -> Not recommended" -ForegroundColor Red
Write-Host ""

Write-Host "== Next Steps ==" -ForegroundColor Cyan
Write-Host "  1. Find highest strike in SAFE zone (Yes > 85%)"
Write-Host "  2. Go to Binance Dual Investment, pick highest APR at that strike"
Write-Host "  3. Buy"
Write-Host ""
