---
name: pp-inspect
description: Read data from a running Portfolio Performance desktop app over its local REST API — list the accessible portfolio files and read their instruments (securities) including custom attributes, cash accounts and investment accounts, by list or by UUID. Use when the task is to look up, list, find, or report on securities/instruments, their custom attributes (TER, ratings, flags…), or accounts in Portfolio Performance without changing anything. Requires a paired token (see pp-connect). For valuations/returns use pp-analyze; to change data use pp-edit.
---

# pp-inspect — read instruments and accounts

Read-only access to the master data of an open Portfolio Performance file. **Prerequisite:** a paired token and the `PP_PORT`/`PP_TOKEN` convention — if you don't have one, or any call returns `401`, use **pp-connect** first. The shared mental model, vocabulary and error table live in [pp-connect/reference.md](../pp-connect/reference.md); read it if you haven't.

Setup in every session:

```bash
PP_PORT="${PP_PORT:-5712}"
BASE="http://127.0.0.1:$PP_PORT"
TOKEN="${PP_TOKEN:-$(cat ~/.config/portfolio-performance/rest-token 2>/dev/null)}"
auth=(-H "Authorization: Bearer $TOKEN")
```

All list responses are an **envelope** — `{"items": [...]}`, never a bare array (so pagination can be added later without breaking you). Reach into `.items`.

## Pick a file

```bash
curl -fsS "${auth[@]}" "$BASE/v1/files"
# {"items":[{"id":"5f3c…","alias":"main","label":"portfolio.xml","path":"/Users/me/portfolio.xml"}]}
```

Use either the `id` or the `alias` as `{file}` below. Empty `items` → the app is up and you're authorized, but no file is **enabled** for the API; ask the user to enable one (Preferences → REST API). See the 404/409 notes in the reference before concluding a file is "missing".

## Instruments (securities)

```bash
# list
curl -fsS "${auth[@]}" "$BASE/v1/files/main/instruments"
# one, by uuid
curl -fsS "${auth[@]}" "$BASE/v1/files/main/instruments/8a1e0c4b-…"
```

```json
{"uuid":"8a1e…","name":"Apple Inc.","currencyCode":"USD",
 "isin":"US0378331005","wkn":"865985","tickerSymbol":"AAPL","note":"Core holding",
 "attributes":{"ter":0.007,"rating":"A"}}
```

- `uuid`, `name`, `currencyCode` are always present. `currencyCode` may be **`null`** for a currency-less instrument (an index, a CPI series) — the key is there, the value can be null.
- `isin`, `wkn`, `tickerSymbol`, `note` are **omitted entirely when not set** — test for presence, don't assume the key exists.
- `attributes` — the instrument's **set** custom attributes, keyed by attribute id, values typed per the attribute's type (`ter` above is a `percent`, so `0.007` = 0.7 %). The key is **omitted entirely when none are set**. See [Custom attributes](#custom-attributes) below.
- Prices, quote feeds and events are **not** exposed in v1.

## Custom attributes

The `attributes` object on an instrument is keyed by opaque attribute **id**. To learn what an id means — its display name and value type — list the definitions the file has (see [reference › Custom attributes](../pp-connect/reference.md#custom-attributes) for the value encoding):

```bash
curl -fsS "${auth[@]}" "$BASE/v1/files/main/instruments/attribute-types"
# {"items":[{"id":"ter","name":"TER","columnLabel":"TER","type":"percent","supported":true},
#           {"id":"rating","name":"Analyst rating","type":"string","supported":true}, …]}
```

Then join by id. To report the TER of every instrument that has one:

```bash
curl -fsS "${auth[@]}" "$BASE/v1/files/main/instruments" \
| jq -r '.items[] | select(.attributes.ter != null) | "\(.name)  \(.attributes.ter * 100)%"'
```

- Values are **fractions for `percent`** (`0.007` = 0.7 %), plain decimals for money/quote/shares and for `number` (unscaled: `5` means five, not `0.05` — see reference.md), ISO dates for dates, `true`/`false` for booleans — resolve which via the `type` from the attribute-types list.
- A definition with `"supported": false` (a limit price, bookmark or image) is **not** carried in the `attributes` map in v1.

## Cash accounts

```bash
curl -fsS "${auth[@]}" "$BASE/v1/files/main/cash-accounts"
curl -fsS "${auth[@]}" "$BASE/v1/files/main/cash-accounts/c4b2…"
```

```json
{"uuid":"c4b2…","name":"Cash Account","currencyCode":"EUR","note":"Settlement account"}
```

Holds cash in a single currency. `note` omitted when unset.

## Investment accounts

```bash
curl -fsS "${auth[@]}" "$BASE/v1/files/main/investment-accounts"
curl -fsS "${auth[@]}" "$BASE/v1/files/main/investment-accounts/d9f0…"
```

```json
{"uuid":"d9f0…","name":"Broker","referenceCashAccount":"c4b2…","note":"Main brokerage"}
```

Holds **instrument positions only**. Its cash side is the separate cash account named by `referenceCashAccount` (a cash-account `uuid`; omitted when not set). To see *positions and balances*, you want holdings — that's **pp-analyze**, not a field here.

## Worked example — find an instrument by ticker and report its ISIN

```bash
curl -fsS "${auth[@]}" "$BASE/v1/files/main/instruments" \
| jq -r '.items[] | select(.tickerSymbol=="AAPL") | "\(.name)  \(.isin // "no ISIN")  \(.uuid)"'
```

(If `jq` isn't available, parse the JSON directly — it's a flat envelope of flat objects.)

## Notes

- These are reads: no `423` (that's writes only), and the response reflects the live in-memory file.
- To join a holding back to its master data: a holding's `uuid` + `type` tells you whether to look it up under `instruments/{uuid}` or `cash-accounts/{uuid}`.
- Need a field this skill doesn't mention? Fetch `"$BASE/v1/openapi.yaml"` — it's the exact, current contract.
