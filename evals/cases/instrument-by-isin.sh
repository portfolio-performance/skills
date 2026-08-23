PROMPT="I have an instrument with ISIN IE00B1YZSC51. What is its name, its ticker symbol and the currency it is quoted in?"

check()
{
    local instrument
    instrument=$(api "/v1/files/$FILE_ID/instruments" | json '
import sys, json
for item in json.load(sys.stdin)["items"]:
    if item.get("isin") == "IE00B1YZSC51":
        print(item["name"])
        print(item.get("tickerSymbol") or "")
        print(item.get("currencyCode") or "")
        break
else:
    raise SystemExit("IE00B1YZSC51 is not in this file")
') || { fail "cannot establish ground truth: $instrument"; return; }

    local name ticker currency
    { read -r name; read -r ticker; read -r currency; } <<< "$instrument"

    expect_match "$(printf '%s' "$name" | sed 's/[][\.*^$(){}?+|/]/\\&/g')" "name '$name' not reported"
    [[ -n "$ticker" ]] && expect_match "$ticker" "ticker '$ticker' not reported"
    [[ -n "$currency" ]] && expect_match "$currency" "currency '$currency' not reported"
    return 0
}
