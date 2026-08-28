PROMPT="Which of my closed trades made the most money, and how much did it make?"

check()
{
    # the file's best *open* trade is a different instrument with a bigger
    # number, so an answer that ignores the open/closed split lands elsewhere
    local best amount
    best=$(top_trades "?status=closed" | head -1)
    amount=$(api "/v1/files/$FILE_ID/trades?status=closed" | json '
import sys, json
items = json.load(sys.stdin)["items"]
print(max(t["profitLoss"]["value"] for t in items))
')

    expect_match "$(printf '%s' "$best" | sed 's/[][\.*^$(){}?+|/]/\\&/g')" \
        "the best closed trade ($best) is not named"
    expect_match "$(amount_pattern "$amount")" "its profit ($amount) is not reported"
    expect_match 'closed|realized|realised' "the answer never says the trade is a closed one"
}
