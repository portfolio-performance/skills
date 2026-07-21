---
name: pp-connect
description: Connect to a running Portfolio Performance desktop app over its local REST API — obtain and store a bearer token by interactive pairing, and set up the PP_PORT/PP_TOKEN convention that the pp-inspect, pp-edit and pp-analyze skills rely on. Use this first, whenever a task involves reading or editing a Portfolio Performance file (instruments/securities, cash or investment accounts, holdings, performance) through the API, or when a call returns 401.
---

# pp-connect — pair with Portfolio Performance and hold a token

Portfolio Performance exposes a **local, loopback-only** HTTP/JSON API into the *running* desktop app. Every client holds its **own** bearer token, obtained by asking the user to approve a pairing request inside the app.

This skill gets you a token and stores it. The sibling skills use it:

- **pp-inspect** — read files, instruments, cash & investment accounts
- **pp-edit** — change or delete instruments
- **pp-analyze** — holdings valuation and performance/returns

Read [reference.md](reference.md) once — it holds the mental model, the error table, and the conventions all four skills assume. **For exact field-level detail, fetch the live spec** (see below); do not guess field names.

## The convention (used by every skill)

| Variable | Meaning | Default |
|---|---|---|
| `PP_PORT` | the port the API listens on | `5712` |
| `PP_TOKEN` | the bearer token | — |
| dotfile | `~/.config/portfolio-performance/rest-token` | token fallback when `PP_TOKEN` is unset |

Base URL is always `http://127.0.0.1:$PP_PORT`. Resolve the token **env-first, dotfile-fallback**:

```bash
PP_PORT="${PP_PORT:-5712}"
BASE="http://127.0.0.1:$PP_PORT"
TOKEN="${PP_TOKEN:-$(cat ~/.config/portfolio-performance/rest-token 2>/dev/null)}"
```

If `TOKEN` is empty, or any call returns **401**, you are not paired — run the pairing flow below.

## Step 0 — is the API even up?

The spec endpoint needs **no token**, so it is the cheapest liveness + discovery probe:

```bash
curl -fsS "$BASE/v1/openapi.yaml" | head -5
```

- Connection refused → the app is not running, or the API is off. Ask the user to open Portfolio Performance and tick **Preferences → REST API → Enable REST API (localhost only)** (and, per file, **enable** the files they want you to reach). Nothing you can do over the wire enables it.
- `403` → you are not addressing it as loopback, or you sent an `Origin` header. Use `127.0.0.1`, no `Origin`.
- `200` (YAML) → the API is up. Fetch the whole document any time you need the authoritative contract.

## Step 1 — file an access request

No token needed. `clientName` is what the user sees in the approval prompt — make it recognisable.

```bash
REQ=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"clientName": "Claude Code"}' \
  "$BASE/v1/auth/requests")
echo "$REQ"          # → {"id":"…","status":"pending"}
ID=$(printf '%s' "$REQ" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
```

Then **tell the user to look at Portfolio Performance and approve the request.** The prompt offers *Allow for this session* (token dies when the app quits), *Always allow* (persistent), and *Decline*.

- `429` on this call → another request is already pending, or a previous one was declined and a cool-down is active. Respect `Retry-After` (seconds) and try again; do not hammer it.

## Step 2 — poll until the user answers

Poll every 1–2 s. The request **expires after 2 minutes**. The terminal state is delivered **exactly once** — capture the token the moment it appears.

```bash
for i in $(seq 1 90); do
  S=$(curl -fsS "$BASE/v1/auth/requests/$ID")
  case "$S" in
    *'"status":"approved"'*) echo "$S"; break ;;
    *'"status":"denied"'*)   echo "user declined"; exit 1 ;;
    *'"status":"expired"'*)  echo "request expired — start over"; exit 1 ;;
  esac
  sleep 2
done
TOKEN=$(printf '%s' "$S" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
```

## Step 3 — store the token (so you don't re-pair every session)

The token cannot be retrieved again. Persist it for future sessions, owner-only:

```bash
mkdir -p ~/.config/portfolio-performance
umask 177 && printf '%s' "$TOKEN" > ~/.config/portfolio-performance/rest-token
```

(If the user prefers, they can instead `export PP_TOKEN=…` in their shell profile — env wins over the dotfile.)

## Step 4 — verify you're in

```bash
curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE/v1/files"
# → {"items":[{"id":"…","alias":"…","label":"…","path":"…"}]}
```

An empty `items` list means the app is running and you're authorized, but the user hasn't **enabled** any file for the API. Ask them to enable one in Preferences → REST API. From here, hand off to **pp-inspect / pp-edit / pp-analyze**.

## When a later call 401s again

The token was revoked (the user can revoke any client at any time in Preferences → REST API), or it was a session token and the app was restarted. Delete the stale dotfile and re-pair:

```bash
rm -f ~/.config/portfolio-performance/rest-token
```

## Headless / no one at the screen

If nobody can approve a prompt, the user mints a token manually in **Preferences → REST API → Add client** and hands it to you. Store it exactly as in Step 3; skip Steps 1–2.
