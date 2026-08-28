PROMPT="Have I ever traded Daimler Truck Holding AG? If so, how did those trades go?"

check()
{
    # the instrument exists but was never traded: the API answers 200 with an
    # empty list, not a 404 - and the file holds a *similarly named*
    # instrument that was traded, so the two must not be conflated
    local uuid count
    uuid=$(api "/v1/files/$FILE_ID/instruments" | json '
import sys, json
for item in json.load(sys.stdin)["items"]:
    if item["name"].startswith("Daimler Truck"):
        print(item["uuid"])
        break
else:
    raise SystemExit("no Daimler Truck instrument in this file")
') || { fail "cannot establish ground truth: $uuid"; return; }

    count=$(api "/v1/files/$FILE_ID/instruments/$uuid/trades" | json '
import sys, json
print(len(json.load(sys.stdin)["items"]))
')
    [[ "$count" == "0" ]] || { fail "ground truth moved: Daimler Truck now has $count trades"; return; }

    expect_match 'daimler truck' "the instrument is never named"
    expect_match 'no trade|never traded|not traded|zero trades' \
        "the answer never says there are no trades"
    expect_no_match '(instrument|security|it)[^.]{0,30}(not found|does not exist|doesn.t exist|is unknown)' \
        "the answer reports the instrument as missing rather than as untraded"
}
