PROMPT="Looking at my trades: how much profit have I actually realized, and how much is still unrealized in the trades that are still open?"

check()
{
    # closed trades are a small net gain, open ones a large net loss - an
    # answer that lumps them together reports neither figure
    local realized unrealized
    realized=$(api "/v1/files/$FILE_ID/trades?status=closed" | json '
import sys, json
print(sum(t["profitLoss"]["value"] for t in json.load(sys.stdin)["items"]))
')
    unrealized=$(api "/v1/files/$FILE_ID/trades?status=open" | json '
import sys, json
print(sum(t["profitLoss"]["value"] for t in json.load(sys.stdin)["items"]))
')

    expect_match "$(amount_pattern "$realized")" "realized total ($realized) not reported"
    expect_match "$(amount_pattern "$unrealized")" "unrealized total ($unrealized) not reported"
    expect_match 'unrealiz|unrealis|not.{0,15}realiz|still open|on paper' \
        "the answer never marks the open side as unrealized"
}
