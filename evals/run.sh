#!/usr/bin/env bash
# Runs eval cases as headless agent sessions and grades the answers.
#
#   ./run.sh                        # every case
#   ./run.sh top-five-holdings      # one case, by file name
#   ./run.sh --model opus --keep    # pick the model, keep the transcripts
set -uo pipefail

if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    echo "bash 4 or newer required (found $BASH_VERSION)" >&2
    exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS="$(cd "$HERE/.." && pwd)/skills"

PP_PORT="${PP_PORT:-5712}"
PP_TOKEN="${PP_TOKEN:-devtoken}"
BASE="http://127.0.0.1:$PP_PORT"
MODEL="${PP_EVAL_MODEL:-sonnet}"
KEEP=0
SELECTED=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model) MODEL="$2"; shift 2 ;;
        --keep) KEEP=1; shift ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*) echo "unknown option $1" >&2; exit 2 ;;
        *) SELECTED+=("$1"); shift ;;
    esac
done

if [[ ${#SELECTED[@]} -gt 0 ]]; then
    for want in "${SELECTED[@]}"; do
        if [[ ! -f "$HERE/cases/$want.sh" ]]; then
            echo "unknown eval case: $want" >&2
            echo "available cases:" >&2
            for path in "$HERE"/cases/*.sh; do
                echo "  $(basename "$path" .sh)" >&2
            done
            exit 2
        fi
    done
fi

api()
{
    curl -fsS -H "Authorization: Bearer $PP_TOKEN" "$BASE$1"
}

json()
{
    python3 -c "$1"
}

top_holdings()
{
    api "/v1/files/$FILE_ID/holdings${1:-}" | python3 -c '
import sys, json
items = json.load(sys.stdin)["items"]
for item in sorted(items, key=lambda i: -i["weight"]):
    print(item["name"])
'
}

if ! curl -fsS "$BASE/v1/openapi.yaml" >/dev/null 2>&1; then
    echo "no API on $BASE - start one first:" >&2
    echo "  <portfolio repo>/name.abuchen.portfolio.rest.tests/dev-server.sh" >&2
    exit 1
fi

FILES=$(api /v1/files) || { echo "GET /v1/files failed - is PP_TOKEN right?" >&2; exit 1; }
FILE_ID=$(printf '%s' "$FILES" | python3 -c '
import sys, json
items = json.load(sys.stdin)["items"]
if not items:
    raise SystemExit("no file is enabled for the API")
print(items[0].get("alias") or items[0]["id"])
') || exit 1

echo "API   $BASE"
echo "file  $FILE_ID"
echo "model $MODEL"
echo

WORK=$(mktemp -d "${TMPDIR:-/tmp}/pp-evals.XXXXXX")
trap '[[ $KEEP -eq 1 ]] && echo "transcripts in $WORK" || rm -rf "$WORK"' EXIT

mkdir -p "$WORK/session/.claude/skills"
for skill in "$SKILLS"/pp-*; do
    ln -s "$skill" "$WORK/session/.claude/skills/$(basename "$skill")"
done

fail()
{
    FAILURES+=("$*")
}

expect_in_order()
{
    local previous=-1 position
    for needle in "$@"; do
        position=$(python3 -c '
import sys
answer, needle = open(sys.argv[1]).read().lower(), sys.argv[2].lower()
print(answer.find(needle))
' "$ANSWER" "$needle")
        if [[ "$position" -lt 0 ]]; then
            fail "missing: $needle"
        elif [[ "$position" -lt "$previous" ]]; then
            fail "out of order: $needle"
        else
            previous=$position
        fi
    done
}

money_pattern()
{
    python3 -c '
import sys
integer, _, fraction = sys.argv[1].partition(".")
groups = []
while len(integer) > 3:
    groups.insert(0, integer[-3:])
    integer = integer[:-3]
groups.insert(0, integer)
pattern = "[.,\u2009 ]?".join(groups)
if fraction:
    pattern += "[.,]" + fraction
print(pattern)
' "$1"
}

percent_pattern()
{
    python3 -c '
import sys
value = float(sys.argv[1]) * 100
seen, alternatives = set(), []
for digits in (2, 1, 0):
    text = f"{round(value, digits):.{digits}f}"
    if text not in seen:
        seen.add(text)
        alternatives.append(text.replace(".", "[.,]"))
print("(" + "|".join(alternatives) + ")\\s*%")
' "$1"
}

expect_match()
{
    grep -qiE "$1" "$ANSWER" || fail "${2:-no match for /$1/}"
}

expect_no_match()
{
    grep -qiE "$1" "$ANSWER" && fail "${2:-unexpected match for /$1/}"
    return 0
}

run_case()
{
    local path="$1" name
    name=$(basename "$path" .sh)

    PROMPT=""
    check() { :; }
    # shellcheck disable=SC1090
    source "$path"

    printf '%-28s ' "$name"

    local raw="$WORK/$name.json"
    (
        cd "$WORK/session" &&
        PP_PORT="$PP_PORT" PP_TOKEN="$PP_TOKEN" \
        claude -p "$PROMPT" --output-format json --model "$MODEL" \
            --setting-sources project \
            --allowedTools Bash Read Grep Glob \
            > "$raw" 2>"$WORK/$name.err"
    )

    if [[ ! -s "$raw" ]]; then
        echo "ERROR (agent produced no output; see $WORK/$name.err)"
        KEEP=1
        return 1
    fi

    ANSWER="$WORK/$name.md"
    local cost turns
    python3 -c '
import sys, json
d = json.load(open(sys.argv[1]))
open(sys.argv[2], "w").write(d.get("result") or "")
print(round(d.get("total_cost_usd") or 0, 4), d.get("num_turns"))
' "$raw" "$ANSWER" > "$WORK/$name.meta" || { echo "ERROR (unparseable agent output)"; KEEP=1; return 1; }
    read -r cost turns < "$WORK/$name.meta"
    TOTAL_COST=$(python3 -c "print(round($TOTAL_COST + $cost, 4))")

    FAILURES=()
    check

    if [[ ${#FAILURES[@]} -eq 0 ]]; then
        echo "PASS  (${turns} turns, \$$cost)"
        return 0
    fi

    echo "FAIL  (${turns} turns, \$$cost)"
    printf '    %s\n' "${FAILURES[@]}"
    KEEP=1
    return 1
}

TOTAL_COST=0
passed=0
failed=0

for path in "$HERE"/cases/*.sh; do
    if [[ ${#SELECTED[@]} -gt 0 ]]; then
        wanted=0
        for want in "${SELECTED[@]}"; do
            [[ "$(basename "$path" .sh)" == "$want" ]] && wanted=1
        done
        [[ $wanted -eq 1 ]] || continue
    fi

    if run_case "$path"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
done

echo
echo "$passed passed, $failed failed, \$$TOTAL_COST"
[[ $failed -eq 0 ]]
