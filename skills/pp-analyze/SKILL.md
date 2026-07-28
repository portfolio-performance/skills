---
name: pp-analyze
description: Compute portfolio valuations and returns from a running Portfolio Performance desktop app over its local REST API — the statement of assets (holdings valued at a date, with weights) and performance over an interval (time-weighted return TTWROR, money-weighted return IRR, and a signed value-change breakdown). Use when the task asks for portfolio value, asset allocation, holdings/positions valued at a date, total assets, returns, performance, gains, or how a portfolio changed over a period. Requires a paired token (see pp-connect).
---

# pp-analyze — holdings valuation and performance

The two **computed** endpoints of the Portfolio Performance REST API. **Prerequisite:** a paired token and the `PP_PORT`/`PP_TOKEN` convention — use **pp-connect** first on a `401`. The shared model, money-as-object and fractions-not-percentages conventions, and the error table are in [pp-connect/reference.md](../pp-connect/reference.md).

```bash
PP_PORT="${PP_PORT:-5712}"
BASE="http://127.0.0.1:$PP_PORT"
TOKEN="${PP_TOKEN:-$(cat ~/.config/portfolio-performance/rest-token 2>/dev/null)}"
auth=(-H "Authorization: Bearer $TOKEN")
```

Both endpoints value everything in a **reporting currency** (default: the file's base currency; override with `?currency=`) and echo it back as `reportingCurrency` on the response envelope. A currency pair with no exchange-rate series converts **1:1** — the same silent fallback the app itself uses, so a nonsense currency won't error, it'll just be wrong. Money is always `{"value":…,"currency":…}`; weights and returns are **fractions, not percentages**.

Three currency fields, three meanings — don't conflate them: **`reportingCurrency`** is what a whole report was converted into, **`currency`** inside a money object is what that one amount is in, and **`currencyCode`** on an instrument or cash account is the entity's own declared currency.

## Holdings — the statement of assets at a date

```bash
curl -fsS "${auth[@]}" "$BASE/v1/files/main/holdings?date=2026-07-20"
```

```json
{"date":"2026-07-20","reportingCurrency":"EUR","totalAssets":{"value":1600,"currency":"EUR"},
 "items":[
   {"type":"instrument","uuid":"8a1e…","name":"Apple Inc.","shares":10,
    "price":{"value":110.5,"currency":"USD","date":"2026-07-17"},
    "valuation":{"value":1100,"currency":"EUR"},
    "localValuation":{"value":1105,"currency":"USD"},"weight":0.6875},
   {"type":"cash-account","uuid":"c4b2…","name":"Broker Cash",
    "valuation":{"value":500,"currency":"EUR"},"weight":0.3125}]}
```

- **`date`** (optional, default today) is the valuation date. Future dates are allowed and value at the last known prices.
- **Every line is a holding** — instrument positions and cash-account balances, uniformly. `type` is `instrument` or `cash-account`.
- **Instrument positions with zero shares at the date are omitted; cash accounts always appear**, even at a zero balance.
- **`weight`** is the fraction (0–1) of `totalAssets` — `0.6875` = 68.75 %. Weights across items sum to ~1.
- **`price.date` reveals staleness.** Each instrument is valued at the latest price **on or before** the date — which may be well earlier (a stale quote, or a fallback to the last transaction's price). If `price.date` is far from your valuation date, the valuation is old; surface that rather than presenting it as current.
- **`localValuation`** (instrument's own currency, pre-conversion) appears only when it differs from the reporting currency.
- Join a line back to master data via its `uuid` + `type`: `instruments/{uuid}` or `cash-accounts/{uuid}` (that's **pp-inspect**).

## Performance — returns and value change over an interval

```bash
curl -fsS "${auth[@]}" \
  "$BASE/v1/files/main/performance?openingDate=2024-01-01&closingDate=2024-12-31"
# optional: &currency=EUR &costMethod=fifo|moving-average
```

```json
{"openingDate":"2024-01-01","closingDate":"2024-12-31",
 "reportingCurrency":"EUR","costMethod":"fifo",
 "ttwror":0.0723,"irr":0.0685,
 "breakdown":{
   "openingValue":{"value":100000,"currency":"EUR"},
   "unrealizedCapitalGains":{"value":4200,"currency":"EUR"},
   "realizedCapitalGains":{"value":1500,"currency":"EUR"},
   "income":{"value":900,"currency":"EUR"},
   "fees":{"value":-120,"currency":"EUR"},
   "taxes":{"value":-300,"currency":"EUR"},
   "currencyGains":{"value":210,"currency":"EUR"},
   "netDeposits":{"value":5000,"currency":"EUR"},
   "closingValue":{"value":111390,"currency":"EUR"}}}
```

### The two returns — different questions

- **`ttwror`** — true **time-weighted** return: the return of the strategy, stripping out the timing and size of deposits/withdrawals. Use to compare against a benchmark or another portfolio.
- **`irr`** — internal **money-weighted** return (IRR): the return the *investor* actually earned, weighting periods by how much money was in play. Use for "what did I make."
- Both are **fractions** (`0.0723` = 7.23 %) and both can be **`null`** when the model can't define them for the interval — handle null.

### The breakdown reconciles opening → closing exactly

It's a **signed decomposition**; the money fields **add up to the closing value**:

```
openingValue + unrealizedCapitalGains + realizedCapitalGains + income
             + fees + taxes + currencyGains + netDeposits = closingValue
```

- **`fees` and `taxes` are negative** (positive only on a net refund).
- **`netDeposits`** is the external capital flow (deposits + inbound deliveries − removals − outbound deliveries). It is **not** part of the performance-driven change — it's there to make the reconciliation balance. Don't add it into "gains."
- **`costMethod`** (`fifo` default, or `moving-average`) only changes how gains split between `realizedCapitalGains` and `unrealizedCapitalGains` — it does **not** change their sum, nor the returns. The response echoes the method it used, so a stored payload stays interpretable.

### Dates are valuation snapshots, not a record range

- `openingValue` equals `holdings?date=openingDate`'s `totalAssets`; `closingValue` equals `holdings?date=closingDate`'s. The two endpoints reconcile.
- The opening balance is measured **as of the end of `openingDate`**: activity dated exactly on `openingDate` belongs to the opening balance, not the period's flows; activity on `closingDate` is inside the period.
- `closingDate` (optional, default today) must be **strictly after** `openingDate` — an empty or inverted range is `400 invalid-range`.

## Worked examples

**Asset allocation today (name → weight %):**

```bash
curl -fsS "${auth[@]}" "$BASE/v1/files/main/holdings" \
| jq -r '.items[] | "\(.name)\t\((.weight*100*100|round)/100) %"'
```

**Year-to-date return, as a percentage:**

```bash
curl -fsS "${auth[@]}" \
  "$BASE/v1/files/main/performance?openingDate=2026-01-01" \
| jq -r 'if .ttwror==null then "n/a" else "\((.ttwror*100*100|round)/100) % TTWROR" end'
```

(No `jq`? The payloads are small, flat JSON — parse them directly.)

## Notes

- These are **reads** — no `423`, and no save concern; they never mutate the file.
- They compute on the live in-memory file; a concurrent user edit can, rarely, yield a transient inconsistency or `500` — retrying is cheap.
- For the exact, current field list, fetch `"$BASE/v1/openapi.yaml"`.
