PROMPT="What were my portfolio's time-weighted (TTWROR) and money-weighted (IRR) returns from the start of 2019 to the end of 2020?"

check()
{
    local performance ttwror irr
    performance=$(api "/v1/files/$FILE_ID/performance?openingDate=2018-12-31&closingDate=2020-12-31")
    ttwror=$(printf '%s' "$performance" | json 'import sys, json; print(json.load(sys.stdin)["ttwror"])')
    irr=$(printf '%s' "$performance" | json 'import sys, json; print(json.load(sys.stdin)["irr"])')

    expect_match "$(percent_pattern "$ttwror")" "TTWROR ($ttwror) not reported"
    expect_match "$(percent_pattern "$irr")" "IRR ($irr) not reported"
    expect_match 'ttwror|time.weighted' "TTWROR is never named"
    expect_match 'irr|money.weighted|internal rate' "IRR is never named"
}
