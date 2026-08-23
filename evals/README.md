# evals — do the skills still produce the right answer?

Each case is a **real headless agent session** with these skills loaded, asked
a question in plain language. The answer is then graded against ground truth
read back from the API, so a case keeps grading correctly as the underlying
portfolio file changes.

This catches what a contract test cannot: the skills are prose, and prose can
stay accurate while ceasing to steer. A renamed field breaks a `curl`; an
ambiguous sentence changes the answer.

## Running

```bash
# 1. serve the API — the dev server ships with the desktop app's source
<portfolio repo>/name.abuchen.portfolio.rest.tests/dev-server.sh

# 2. run the evals
./run.sh                          # every case
./run.sh top-five-holdings        # one case
./run.sh --model opus --keep      # pick the model, keep the transcripts
```

`PP_PORT` (default `5712`) and `PP_TOKEN` (default `devtoken`, the dev
server's) point the run at an API. The real desktop app works too — export a
paired token and the cases are unchanged.

Each case is one agent session of roughly 5–10 turns; budget a few cents per
case. Failures keep their transcripts and print the path.

## Why the dev server

The cases need a portfolio file that does not move. The dev server serves the
bundled *kommer* sample and **never writes to disk**, so a run cannot disturb
anything and a restart restores the data — which also makes it safe to add
cases that edit (`pp-edit`), something you would not want to point at a real
file.

## Writing a case

A case is a shell file in `cases/` that sets `PROMPT` and defines `check`:

```bash
PROMPT="Give me the top five holdings of my portfolio."

check()
{
    mapfile -t expected < <(top_holdings | head -5)
    expect_in_order "${expected[@]}"
}
```

`check` grades the agent's answer, which is in the file `$ANSWER`. Available:

| | |
|---|---|
| `api <path>` | GET against the API, authenticated — **this is where ground truth comes from** |
| `top_holdings [query]` | holding names, richest first |
| `FILE_ID` | the first API-enabled file |
| `expect_in_order <needle>…` | each needle appears, in this order |
| `expect_match <regex> [message]` | the answer matches |
| `expect_no_match <regex> [message]` | the answer does not match |
| `money_pattern <number>` | regex tolerating any thousands separator |
| `percent_pattern <fraction>` | regex tolerating any rounding |
| `fail <message>` | record a failure directly |

Grade **the substance of the answer**, not its wording — names, figures,
ordering, whether the right distinction was drawn. Agents phrase things
differently every run; a case that pins the prose will flap.

## Scope

The agent runs in a scratch project carrying only these skills, with
`Bash`, `Read`, `Grep` and `Glob` — enough for the `curl` flows the skills
teach, without `Write` or `Edit`. `Bash` is not a sandbox: keep the cases to
questions you would be happy to have answered on your own machine.
