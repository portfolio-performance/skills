# Portfolio Performance REST API — shared reference

The mental model, vocabulary, error semantics and conventions that **pp-connect, pp-inspect, pp-edit and pp-analyze** all assume. The **authoritative, exact contract is the live spec** — fetch it from the running server and trust it over anything written here:

```bash
curl -fsS "http://127.0.0.1:${PP_PORT:-5712}/v1/openapi.yaml"
```

That document describes the *running* server, so it can never drift from what is actually served. This file is the orientation; the spec is the truth.

## What this API is

A **local** HTTP/JSON API into the *running* Portfolio Performance desktop app, so scripts and agents can read and edit the data of **open** portfolio files. It is:

- **Loopback only** — `http://127.0.0.1:PORT` (`[::1]`, `localhost` too). Off by default; the user enables it in Preferences → REST API.
- **Per-client token** — every client pairs for its own bearer token (see pp-connect).
- **A window onto the live app**, not a database. It serves only files that are **open and individually enabled**. Close the app and the API is gone.

Base URL: `http://127.0.0.1:$PP_PORT` (default port `5712`). Everything is under `/v1`.

## Vocabulary (API term vs. what you might call it)

The API is deliberately more general than the app's English UI, because these accounts can be broker or crypto-exchange accounts, not just bank Depots.

| API resource | Path segment | UI/model term | Holds |
|---|---|---|---|
| instrument | `instruments` | Security | a stock, fund, bond, crypto, index… |
| cash account | `cash-accounts` | Account | cash, in one currency |
| investment account | `investment-accounts` | Portfolio | positions in instruments only |

An **investment account holds only instrument positions**; its cash side is a *separate* cash account, named by its `referenceCashAccount` field.

## Addressing a file

`GET /v1/files` lists the files you may address. In every `/v1/files/{file}/…` path, `{file}` is either the file's `id` **or** its `alias`.

- Identity is **keyed by path on disk** — a different file copied over an enabled path inherits that path's access. Check `path` if it matters which file you write to.
- An `alias` that matches several files → `409 ambiguous-alias`; use the `id`.

## Money and numbers on the wire

- **Money is an object**: `{"value": 1100, "currency": "EUR"}`. `value` is a plain decimal number, never scientific notation.
- **Fractions, not percentages.** A `weight` of `0.6875` is 68.75 %. A `ttwror` of `0.0723` is 7.23 %. Multiply by 100 yourself for display.
- **Returns and some computed fields can be `null`** when the model cannot define them for the interval — handle null, don't assume a number.

## Custom attributes

Instruments carry **user-defined custom attributes** (a TER, a rating, a review date, a yes/no flag…). They're defined per file and addressed by an opaque **`id`**, *not* by their display name — names aren't unique, the id is the stable key. Discover what a file defines:

```bash
curl -fsS "${auth[@]}" "$BASE/v1/files/main/instruments/attribute-types"
# {"items":[{"id":"ter","name":"TER","columnLabel":"TER","type":"percent","supported":true}, …]}
```

Resolve a human name (`"TER"`) to its `id` (`"ter"`) here; then read it on the instrument (pp-inspect) or write it (pp-edit) **by id**. Values are **typed JSON keyed by id**, encoded from the stored value (never locale-formatted):

| `type` | wire value |
|---|---|
| `string` | a string |
| `boolean` | `true` / `false` |
| `date` | ISO-8601 string, `"2026-07-22"` |
| `amount`, `quote`, `shares` | a plain decimal number |
| `percent` | a **fraction** — `0.007` is 0.7 % (as everywhere in this API) |
| `number` | an unscaled decimal — **not** a fraction. Where the desktop reads such an attribute as a percentage (the expected-dividends column), `5` means 5 %. |
| `limit-price`, `bookmark`, `image` | **`supported: false`** — not exposed and not writable in v1 |

Only attributes that are **set**, and only supported (scalar) ones, appear on an instrument.

## Writes are not saved — this surprises everyone

A `PATCH` or `DELETE` mutates the **in-memory** file and marks it dirty, exactly as if the user edited it in the UI. The change is visible immediately, **but there is no save endpoint.** Only the user saves the file (or discards the change by closing without saving). If a task needs the change on disk, **tell the user to press save.**

## The error model (RFC 9457 problem+json)

Errors come back as `application/problem+json` with a stable `type` URI, a `title`, the `status`, sometimes a `detail`, and — for validation/conflict/bad-query — an `errors` array of `{field, code, message}`. Match on `type` (the last path segment shown below) and `status`, not on prose.

| Status | type (short) | Meaning & what to do |
|---|---|---|
| 400 | `invalid-request` | Body isn't a JSON object, or a query param is invalid (`errors` itemizes it). Fix and resend. |
| 401 | `unauthorized` | No/!valid token. Body's `pairing_endpoint` says where to pair → run **pp-connect**. |
| 403 | `forbidden-host` | Not addressed as loopback. Use `127.0.0.1`. |
| 403 | `browser-origin-forbidden` | You sent an `Origin` header. Don't. |
| 404 | `not-found` | Unknown file, **file not enabled**, or unknown entity. See note ▼. |
| 405 | `method-not-allowed` | That path doesn't serve that method. v1 has **no create (POST) endpoints** for portfolio data. |
| 409 | `file-not-open` | File is enabled but not currently open — **a human must open it** in the app. |
| 409 | `ambiguous-alias` | Alias matches several files — retry with the `id`. |
| 409 | `delete-blocked` | Instrument is referenced by transactions/plans — give up, it can't be deleted via the API. |
| 422 | `validation` | One or more fields rejected; every violation is in `errors`. Fix all, resend. |
| 423 | `user-interaction` | A modal dialog is open / a cell is being edited. **Normal and temporary** — respect `Retry-After`, retry. Reads are unaffected. |
| 429 | `pairing-pending` / `pairing-cooldown` | Pairing back-pressure — respect `Retry-After`. |
| 500 | `internal-error` | Unexpected. Retry once; if it persists, report it. |

**Two that regularly trip clients up:**

- **404 does not mean "does not exist."** A file that exists but is not enabled answers *identically* to one that never existed — by design, so the token can't enumerate files the user didn't share. If you expected a file, ask the user to enable it; don't conclude it's gone.
- **423 is expected, not an error in your logic.** While the user has a dialog open, writes are refused rather than silently clobbered. Back off per `Retry-After` and try again.

## curl habits that keep you out of trouble

- Always send `Authorization: Bearer $TOKEN` (except `/v1/openapi.yaml` and the pairing endpoints).
- **Never** send an `Origin` header; always talk to `127.0.0.1`.
- Use `-fsS` so curl fails loudly on HTTP errors but stays quiet otherwise; drop `-f` when you need to read a problem+json body.
- On `423` and `429`, read `Retry-After` and sleep before retrying — don't spin.
