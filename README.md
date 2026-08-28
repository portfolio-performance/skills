# Portfolio Performance agent skills

Skills that let an AI agent drive the **[Portfolio Performance](https://www.portfolio-performance.info/) desktop app** through its local REST API — read instruments (with their custom attributes) and accounts, edit securities and their attributes, and compute holdings, performance and matched trades.

They are [Claude Code skills](https://docs.claude.com/en/docs/claude-code/skills) (`SKILL.md` with `name`/`description` frontmatter), model-invoked by matching the task to each skill's description.

## The set

| Skill | Use it to |
|---|---|
| **`pp-connect`** | Pair with the app and hold a bearer token — **start here.** Carries the shared [`reference.md`](skills/pp-connect/reference.md): mental model, vocabulary, error table, conventions. |
| **`pp-inspect`** | Read files, instruments (securities) with their custom attributes, cash accounts, investment accounts. |
| **`pp-edit`** | Rename / update / clear an instrument's fields and custom attributes, or delete one (JSON Merge Patch). |
| **`pp-analyze`** | Statement of assets (holdings valued at a date), performance (TTWROR, IRR, signed value-change breakdown), and matched trades (profit and loss, holding period, IRR; open or closed). |

`pp-connect` is the hub; the other three link back to it for setup and shared knowledge.

## How they talk to the app

Raw `curl` over loopback, using a small convention:

- `PP_PORT` (default `5712`) and `PP_TOKEN`, base URL `http://127.0.0.1:$PP_PORT`.
- Token resolved **env-first, dotfile-fallback** (`~/.config/portfolio-performance/rest-token`, mode 600).

The API is **loopback-only, off by default**, and serves only files the user has **opened and enabled** in Preferences → REST API. The running server describes itself at `GET /v1/openapi.yaml` (unauthenticated), so the skills point agents at that live spec for the exact, drift-free contract — the prose here is orientation, the served spec is the truth.

## Install

Drop these into a skills directory the agent loads (e.g. symlink or copy `skills/pp-*` into `~/.claude/skills/`).

## Prerequisites

- Portfolio Performance running, with the REST API enabled and at least one file enabled.
- `curl`; `jq` is nice-to-have for the worked examples but not required.
