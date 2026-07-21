---
name: pp-edit
description: Change data in a running Portfolio Performance desktop app over its local REST API — rename an instrument/security, set or clear its ISIN, WKN, ticker symbol, note or currency, set or clear its custom attributes (TER, ratings, review dates, flags…), or delete an instrument. Uses JSON Merge Patch. Use when the task is to edit, update, correct, rename, set, clear, or delete a security/instrument or its custom attributes in Portfolio Performance. Requires a paired token (see pp-connect). Only instruments (their fields and custom attributes) are writable in v1; accounts, prices, transactions are read-only.
---

# pp-edit — update and delete instruments

Write access to instruments in an open Portfolio Performance file. **Prerequisite:** a paired token and the `PP_PORT`/`PP_TOKEN` convention — use **pp-connect** first if a call returns `401`. Read [pp-connect/reference.md](../pp-connect/reference.md) for the shared model and error table; the write-specific gotchas are below.

```bash
PP_PORT="${PP_PORT:-5712}"
BASE="http://127.0.0.1:$PP_PORT"
TOKEN="${PP_TOKEN:-$(cat ~/.config/portfolio-performance/rest-token 2>/dev/null)}"
auth=(-H "Authorization: Bearer $TOKEN")
```

## What's writable

Only **instruments**: the fields `name` (non-empty), `isin`, `wkn`, `tickerSymbol`, `note`, `currencyCode`, **plus its custom attributes** (a nested `attributes` object — see [Custom attributes](#custom-attributes) below). Everything else — prices, quote feeds, events, the retired flag — and **all** of cash/investment accounts is read-only in v1. There are **no create endpoints** (POST → 405); you can only edit instruments that already exist, and you cannot create new *attribute types* over the API (the user defines those in the app).

## ⚠️ Read this before your first write

- **Writes are not saved.** A `PATCH`/`DELETE` changes the *in-memory* file and marks it dirty, exactly like editing in the UI. **There is no save endpoint.** When the task needs the change on disk, tell the user to press **Save** in Portfolio Performance.
- **Confirm intent for destructive edits.** A `DELETE`, or clearing a field, is real data loss the moment the user saves. For anything beyond an obviously-requested change, confirm with the user first.

## PATCH = JSON Merge Patch (RFC 7386)

You send **only the fields you want to change**, not the full object:

- a field you **omit** is left untouched;
- a field set to a value **updates** it;
- a field set to **`null`** **clears** it (for the optional fields).

Content type is `application/merge-patch+json`. The updated instrument is returned.

```bash
# rename, and clear the note
curl -fsS "${auth[@]}" -X PATCH \
  -H "Content-Type: application/merge-patch+json" \
  -d '{"name": "Apple", "note": null}' \
  "$BASE/v1/files/main/instruments/8a1e0c4b-…"
```

### Field rules

- `name` — must be **non-empty**; it **cannot be cleared** (no `null`).
- `isin`, `wkn`, `tickerSymbol`, `note` — string to set, `null` to clear.
- `currencyCode` — a **known** ISO 4217 code, or `null` to clear it (which marks the instrument an index).
  - **Rejected while the instrument has any transactions** (`locked-by-transactions`) — *any* currency change, including clearing, matching the UI's own rule. There is no override; the currency of a traded instrument can't be changed via the API.
  - Clearing is rejected for an exchange rate (`exchange-rate-requires-currency`).

### Validation is all-or-nothing, and never silent

- An **unknown or non-writable field is a `422`**, never a quiet no-op — a typo must not look like success.
- **All** violations come back at once in the `errors` array, so you fix them in one round-trip. Nothing is applied unless everything validates.

```json
{"type":"…/problems/validation","title":"Validation failed","status":422,
 "errors":[{"field":"currencyCode","code":"unknown-currency","message":"XYZ is not a known currency"}]}
```

## Custom attributes

Custom attributes are patched through a **nested `attributes` object** on the same instrument PATCH — itself a merge patch, keyed by the attribute's opaque **id** (not its display name):

- an id you **omit** is left untouched;
- an id set to a **value** sets/replaces it;
- an id set to **`null`** clears it.

Address attributes by **id**, and encode each value **for its type** — a `percent` is a fraction (`0.007` = 0.7 %), a `number` is an unscaled decimal (`5` means five, not `0.05`), money/quote/shares are plain decimals, a date is an ISO-8601 string, a boolean is `true`/`false`. Discover the ids and their types first (names aren't unique, so you can't write by name):

```bash
curl -fsS "${auth[@]}" "$BASE/v1/files/main/instruments/attribute-types"
# → [{ "id":"ter","name":"TER","type":"percent","supported":true }, …]
```

Then set the TER to 0.7 % and clear the rating in one call:

```bash
curl -fsS "${auth[@]}" -X PATCH \
  -H "Content-Type: application/merge-patch+json" \
  -d '{"attributes":{"ter":0.007,"rating":null}}' \
  "$BASE/v1/files/main/instruments/8a1e0c4b-…"
```

You can mix attributes with top-level fields in the same patch (`{"note":"reviewed","attributes":{"ter":0.008}}`); it's all one all-or-nothing validation.

### Attribute-specific `422` codes

Each bad attribute is reported on field `attributes.<id>`:

- `unknown-attribute` — no attribute type with that id exists in the file.
- `attribute-not-applicable` — that attribute exists but doesn't apply to instruments.
- `unsupported-attribute-type` — a compound type (limit price / bookmark / image); not writable in v1 (it shows `"supported": false` in the attribute-types list).
- `invalid-value` — the value doesn't match the attribute's type (wrong JSON type, a non-ISO date, a number out of range). Numbers with more precision than the type holds are rounded, not rejected.

Clearing an attribute that isn't set is a no-op and does **not** mark the file dirty.

## DELETE an instrument

```bash
curl -fsS "${auth[@]}" -X DELETE "$BASE/v1/files/main/instruments/8a1e0c4b-…" -o /dev/null -w '%{http_code}\n'
# 204 → deleted
```

- **`204 No Content`** on success.
- **`409 delete-blocked`** if transactions or investment plans reference the instrument — deleting it in the app would cascade into transaction history, which the API refuses to do on your behalf. This is terminal: remove the transactions in the UI first, or leave it. Watchlist and taxonomy membership do **not** block a delete.

## `423 user-interaction` — expected, just retry

If the user has a modal dialog open or is editing a table cell, a write returns **`423`** with a `Retry-After` (seconds) rather than clobbering their edit. This is normal. Back off and retry:

```bash
# retry a PATCH a few times while the user has a dialog open
for i in 1 2 3 4 5; do
  code=$(curl -sS "${auth[@]}" -X PATCH \
    -H "Content-Type: application/merge-patch+json" \
    -d '{"note":"reviewed"}' \
    "$BASE/v1/files/main/instruments/8a1e…" \
    -o /tmp/pp.out -D /tmp/pp.hdr -w '%{http_code}')
  [ "$code" != "423" ] && break
  # honour the Retry-After header the 423 carries (fall back to 3s)
  wait=$(sed -n 's/^[Rr]etry-[Aa]fter:[[:space:]]*\([0-9]*\).*/\1/p' /tmp/pp.hdr)
  sleep "${wait:-3}"
done
cat /tmp/pp.out
```

(Reads are never blocked by `423` — only writes.)

## After you write

Confirm the returned object reflects your change, then **remind the user the change is unsaved** — it lives only in the running app until they save. If they close without saving, it's gone.
