PROMPT="Give me the top five holdings of my portfolio in US dollars."

check()
{
    mapfile -t expected < <(top_holdings "?reportingCurrency=USD" | head -5)
    expect_in_order "${expected[@]}"

    expect_match 'usd|\$|dollar' "the answer never mentions US dollars"

    local total
    total=$(api "/v1/files/$FILE_ID/holdings?reportingCurrency=USD" | json '
import sys, json
print(json.load(sys.stdin)["totalAssets"]["value"])
')
    expect_match "$(money_pattern "$total")" "USD total $total not reported - was the report converted at all?"
}
