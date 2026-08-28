---
name: pp-analyze
description: Compute portfolio valuations and returns from a running Portfolio Performance desktop app over its local REST API — the statement of assets (holdings valued at a date, with weights), performance over an interval (time-weighted return TTWROR, money-weighted return IRR, and a signed value-change breakdown), the same interval broken down per instrument (valuation, capital gains, dividends, fees, IRR, TTWROR, volatility and drawdown), and matched trades (buy/sell pairs with profit and loss, holding period and IRR, open or closed). Use when the task asks for portfolio value, asset allocation, holdings/positions valued at a date, total assets, returns, performance, gains, cost basis, dividends, fees, risk or volatility, best and worst positions, trades or round trips, realized or unrealized profit and loss per trade, winning and losing trades, holding periods, open positions, or how a portfolio or a single instrument changed over a period. Requires a paired token (see pp-connect).
---

# pp-analyze — holdings valuation, performance and trades

The **computed** endpoints of the Portfolio Performance REST API. **Prerequisite:** a paired token and the `PP_PORT`/`PP_TOKEN` convention — use **pp-connect** first on a `401`. The shared model, money-as-object and fractions-not-percentages conventions, and the error table are in [pp-connect/reference.md](../pp-connect/reference.md).

```bash
PP_PORT="${PP_PORT:-5712}"
BASE="http://127.0.0.1:$PP_PORT"
TOKEN="${PP_TOKEN:-$(cat ~/.config/portfolio-performance/rest-token 2>/dev/null)}"
auth=(-H "Authorization: Bearer $TOKEN")
```

Every endpoint here values everything in a **reporting currency** (default: the file's base currency; override with `?reportingCurrency=`) and echo it back under that same name on the response envelope — request and response agree, so you can send back what you read. A currency pair with no exchange-rate series converts **1:1** — the same silent fallback the app itself uses, so a nonsense currency won't error, it'll just be wrong. Money is always `{"value":…,"currency":…}`; weights and returns are **fractions, not percentages**.

Three currency fields, three meanings — don't conflate them: **`reportingCurrency`** is what a whole report was converted into (and the query parameter that sets it), **`currency`** inside a money object is what that one amount is in, and **`currencyCode`** on an instrument or cash account is the entity's own declared currency.

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
- **So "my biggest holdings" ranks both.** Rank on `weight` across all `items` and quote `totalAssets` as the denominator. A cash account can outweigh every security — dropping it silently doesn't just omit a line, it shifts every rank below it. If you do restrict the ranking to securities, say so in the answer.
- **Instrument positions with zero shares at the date are omitted; cash accounts always appear**, even at a zero balance.
- **`weight`** is the fraction (0–1) of `totalAssets` — `0.6875` = 68.75 %. Weights across items sum to ~1.
- **`price.date` reveals staleness.** Each instrument is valued at the latest price **on or before** the date — which may be well earlier (a stale quote, or a fallback to the last transaction's price). If `price.date` is far from your valuation date, the valuation is old; surface that rather than presenting it as current.
- **`localValuation`** (instrument's own currency, pre-conversion) appears only when it differs from the reporting currency.
- Join a line back to master data via its `uuid` + `type`: `instruments/{uuid}` or `cash-accounts/{uuid}` (that's **pp-inspect**).

## Performance — returns and value change over an interval

```bash
curl -fsS "${auth[@]}" \
  "$BASE/v1/files/main/performance?openingDate=2024-01-01&closingDate=2024-12-31"
# optional: &reportingCurrency=EUR &costMethod=fifo|moving-average
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

## Per-instrument performance — the same report, broken down

```bash
curl -fsS "${auth[@]}" \
  "$BASE/v1/files/main/performance/instruments?openingDate=2025-01-01&closingDate=2025-12-31&metrics=valuation,gains"
# one instrument: .../performance/instruments/{uuid}
# optional: &reportingCurrency= &costMethod=fifo|moving-average &taxesAndFees=included|excluded &metrics=
```

```json
{"openingDate":"2025-01-01","closingDate":"2025-12-31","reportingCurrency":"EUR",
 "costMethod":"fifo","taxesAndFees":"included","metrics":["valuation","gains"],
 "items":[
   {"uuid":"5c1a…","name":"iShares Core MSCI World","currencyCode":"USD",
    "valuation":{"shares":152.5,
      "openingValue":{"value":15200,"currency":"EUR"},
      "closingValue":{"value":18432.1,"currency":"EUR"},
      "periodCostBasis":{"value":16218.9,"currency":"EUR"}},
    "gains":{"realizedCapitalGains":{"value":0,"currency":"EUR"},
      "realizedCurrencyComponent":{"value":0,"currency":"EUR"},
      "unrealizedCapitalGains":{"value":2213.2,"currency":"EUR"},
      "unrealizedCurrencyComponent":{"value":410,"currency":"EUR"}}}]}
```

Same interval semantics and same six echoes as the aggregate. The item route returns one element's fields merged into that context, without `items`.

### `?metrics=` is the cost lever — use it

Seven groups: `valuation gains income expenses moneyWeighted timeWeighted risk`. **Default is all seven.** `timeWeighted` and `risk` are backed by a *full daily valuation series per instrument*; the other five are cheap linear passes. On a large file with a long interval, the default request is slow and there is no pagination.

**So: ask for what you need.** `?metrics=valuation,gains` for "what am I holding and what has it made"; add `timeWeighted` only when you actually want TTWROR per position. Requesting `timeWeighted` and `risk` together costs no more than either alone — they share one series. An unselected group is an **absent key**, not a null; an unknown name is `400 invalid-value`.

### Reading the fields

- **`fees` and `taxes` here are positive magnitudes** — the opposite of the aggregate breakdown's signed `-120`. That breakdown has to add up by addition; this resource publishes no such sum, so it reports the charges as charged.
- **`periodCostBasis` is period-relative, not what you paid.** A lot held since before `openingDate` enters at its *valuation on that date*. Shares bought in 2020 for €5,000 and worth €14,000 on 2025-01-01 show €14,000 here — the lifetime gain is **not** derivable from this endpoint. Don't present it as purchase price.
- **`*CurrencyComponent` is contained in the adjacent gains figure, not additional to it.** `unrealizedCurrencyComponent` is the FX share *of* `unrealizedCapitalGains`. **Never add the two** — that double-counts. (This is the opposite arithmetic from the aggregate's `currencyGains`, which *is* a separate additive term.)
- **`closingValue − periodCostBasis = unrealizedCapitalGains`** holds exactly, under either `taxesAndFees` setting. `included` (default) puts the fees and taxes embedded in a purchase into the basis; `excluded` leaves them out. It moves the basis and the gains together, and never touches `expenses` or the returns.
- **`risk.maxDrawdown` is a positive fraction** (`0.231` = a 23.1 % drawdown). **`longestDrawdownDays` is the longest stretch below a previous peak — not the duration of the deepest drawdown.**
- **`currencyCode` is the instrument's own currency; `reportingCurrency` is what every amount was converted into.** On the item route they sit side by side.
- A position **sold during the period is still listed**, with `shares: 0` and zero `closingValue` but real `realizedCapitalGains`, dividends and fees. Don't filter it out — it is part of the period's performance. Instruments never held and never traded don't appear at all.
- The item route has **two 404s**: `not-found` (no such instrument — fix the id) and `no-activity-in-period` (it exists, but nothing was held or traded in the interval — report that, don't retry).

## Trades — matched buy/sell pairs

```bash
curl -fsS "${auth[@]}" "$BASE/v1/files/main/trades?status=closed"
# one instrument: .../instruments/{uuid}/trades
# optional: &grouping=combined|per-lot &costMethod= &taxesAndFees= &reportingCurrency=
```

```json
{"reportingCurrency":"EUR","costMethod":"fifo","taxesAndFees":"included",
 "grouping":"combined","valuationDate":"2026-08-27","status":["closed"],
 "warnings":[],
 "items":[
   {"status":"closed","direction":"long",
    "instrument":{"uuid":"8a1e…","name":"Apple Inc.","currencyCode":"USD"},
    "portfolio":{"uuid":"1d3f…","name":"Broker Depot"},
    "start":"2024-03-04T00:00:00","end":"2025-11-18T00:00:00",
    "shares":10,"transactionCount":2,
    "entryValue":{"value":1010.5,"currency":"EUR"},
    "exitValue":{"value":1320,"currency":"EUR"},
    "profitLoss":{"value":309.5,"currency":"EUR"},
    "holdingPeriodDays":624,"irr":0.1782,"return":0.3063,"note":"rebalancing"}]}
```

A trade is a set of purchases matched against the sales that closed them, within one securities account. It is **computed, not stored** — no `uuid`, no `/trades/{id}`, no writes; to change a trade, change the transactions behind it (see [reference › Computed collections](../pp-connect/reference.md#computed-collections)). Sorted by instrument name, and within one instrument in the order the lots were matched, which is chronological.

### Never skip `warnings`

A security whose transactions don't reconcile — a sale covering more shares than were held, a transfer of shares that aren't there — contributes **no trades** and is listed in `warnings` instead. The request still succeeds with `200`, because one unreconcilable security must not make the resource unreadable for the other four hundred. A non-empty `warnings` therefore means **the list you got is incomplete**: name the affected instruments in your answer rather than reporting a total as if it covered everything.

A sale into an account holding nothing is *not* such a case — it opens a short position, reported as an open trade with `direction: "short"`.

### An open trade is a valuation, not a result

`status` is `open` or `closed`; `?status=` filters it (comma-separated, both by default) and the response echoes the selection.

- A **closed** trade's `exitValue`, `profitLoss` and `return` are what actually happened.
- An **open** trade has `end: null`, and those same three fields are a **valuation at the market price of `valuationDate`** (echoed on the envelope). Its `holdingPeriodDays` runs to that date as well — so the same open trade legitimately reports different numbers tomorrow.

Don't add the two kinds into a single "profit" figure without saying which part is realized. For "what have I actually made", ask for `?status=closed`.

### `direction` cannot be inferred from the numbers

`shares` is positive either way, so read the field:

- `long` — opened with a purchase; `profitLoss = exitValue − entryValue`.
- `short` — opened with a sale; `profitLoss = entryValue − exitValue`, the reverse.

### The three knobs, and what each does *not* touch

- **`grouping`** (`combined` default, or `per-lot`) — how matched lots are gathered into trades: `combined` makes one trade of the acquisitions that a sale closed, `per-lot` reports each acquisition as its own trade. It is **not** a matching strategy. Matching is always **FIFO**; there is no way to ask this API for LIFO.
- **`costMethod`** (`fifo` default, or `moving-average`) — moves `entryValue`, `profitLoss` and `return` onto the moving average cost of the shares. It does **not** move `irr`, which comes from the actual cash flows and has no moving-average counterpart, nor `exitValue`, which is what the shares realized or are worth. A `moving-average` request thus returns a deliberately mixed-basis item.
- **`taxesAndFees`** (`included` default, or `excluded`) — moves `entryValue`, `exitValue` and `profitLoss` **together**, so the subtraction above keeps holding. It leaves `irr` and `return` alone, and has no effect on an open trade's exit side: a valuation has incurred no charges.

**The `null`s come as a set.** `entryValue`, `profitLoss` and `return` are `null` **together** wherever the moving average cost is undefined — always for a `short` trade, which was never acquired. `exitValue` and `irr` stay defined. `irr` and `return` are both fractions (`0.1782` = 17.82 %), but `irr` is **annualized** and `return` is not — don't compare them across trades of different lengths. Either can be `null` on its own when the model can't define it.

### Fields worth reading carefully

- **`holdingPeriodDays` is a share-weighted average**, not `end − start` — they diverge as soon as a position was accumulated or partly sold.
- **`transactionCount`** — 2 for a clean buy and sell, more for an accumulated or partially sold position.
- **`start` / `end` are local, offset-less date-times** (`"2024-03-04T00:00:00"`); don't read them as UTC.
- **`instrument` and `portfolio` are references** — join by `uuid` to `instruments/{uuid}` and `investment-accounts/{uuid}` (that's **pp-inspect**). `instrument.currencyCode` is the instrument's own currency, not what the amounts were converted into.
- **`note`** is the note on the trade's *last* transaction — the closing one for a closed trade, the most recent one for an open trade. Omitted when there is none.

### The instrument route answers with an empty list, not a 404

`…/instruments/{uuid}/trades` on an instrument that exists but was never traded is `200` with `items: []`. That is deliberately unlike `…/performance/instruments/{uuid}`, which 404s `no-activity-in-period`: there the uuid names the single item the response consists of, here it names the collection's owner. A `404` from the trades route means the **instrument** is unknown — fix the id, don't report "no trades".

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

**Best and worst positions this year, without paying for a daily series:**

```bash
curl -fsS "${auth[@]}" \
  "$BASE/v1/files/main/performance/instruments?openingDate=2026-01-01&metrics=valuation,gains" \
| jq -r '.items[] | "\(.gains.unrealizedCapitalGains.value + .gains.realizedCapitalGains.value)\t\(.name)"' \
| sort -rn
```

**Biggest realized winners and losers — checking `warnings` first:**

```bash
T=$(curl -fsS "${auth[@]}" "$BASE/v1/files/main/trades?status=closed")
printf '%s' "$T" | jq -r '.warnings[] | "SKIPPED \(.instrument.name): \(.message)"'
printf '%s' "$T" \
| jq -r '.items[] | "\(.profitLoss.value)\t\(.instrument.name)\t\(.holdingPeriodDays)d"' \
| sort -rn
```

(No `jq`? The payloads are small, flat JSON — parse them directly.)

## Notes

- These are **reads** — no `423`, and no save concern; they never mutate the file.
- They compute on the live in-memory file; a concurrent user edit can, rarely, yield a transient inconsistency or `500` — retrying is cheap.
- For the exact, current field list, fetch `"$BASE/v1/openapi.yaml"`.
