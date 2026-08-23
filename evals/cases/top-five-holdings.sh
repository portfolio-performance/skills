PROMPT="Give me the top five holdings of my portfolio."

check()
{
    mapfile -t expected < <(top_holdings | head -5)
    expect_in_order "${expected[@]}"

    local total
    total=$(api "/v1/files/$FILE_ID/holdings" | json '
import sys, json
print(json.load(sys.stdin)["totalAssets"]["value"])
')
    expect_match "$(money_pattern "$total")" "total assets $total not reported"
}
