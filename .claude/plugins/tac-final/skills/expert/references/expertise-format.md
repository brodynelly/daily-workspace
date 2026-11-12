# Expertise File Format

## Rules

- **Location**: `.claude/experts/<domain>/expertise.yaml` (required) and `.claude/experts/<domain>/evals.yaml`
  (optional), committed so the team and every agent share them. This is the only store agents read. A declared
  adapter (see [luuna-suite-ownership.md](luuna-suite-ownership.md)) mirrors it; it never replaces it.
- **Structured**: YAML so agents can scan sections; start from
  [../assets/expertise-template.yaml](../assets/expertise-template.yaml).
- **A map, not truth**: readers verify every path and claim they rely on against the code before acting on it.
- **Verifiable**: every `path` and symbol must exist. `improve` checks each one and fixes or removes what fails.
- **Bounded**: `line_limit` keeps the model a summary. Over the limit, compress or split into sub-domains
  (for example `billing-invoices`, `billing-payments`). `evals.yaml` does not count toward it.
- **Pinned**: `source_revision` is the commit SHA of the last full validation; `improve` diffs from it.
  `last_validated` (UTC date) is the fallback when the SHA is unknown to git (rebased, shallow clone).
- **Matchable**: only `core_files` entries use the `- path:` key. The Learn hook selects a domain when a changed
  path equals a `core_files` path, or starts with one that ends in `/`.

## Fields

| Field | Required | Set by | Purpose |
| --- | --- | --- | --- |
| `domain` | Yes | seed | Kebab-case name, equals the directory name |
| `source_revision` | Yes | seed, improve | `git rev-parse HEAD` at validation; diff base for `improve` |
| `last_validated` | Yes | seed, improve | UTC date; fallback diff base (`git log --since`) |
| `line_limit` | Yes | seed | Size budget (table below) |
| `evals` | No | seed | Path to the question set, relative to this file |
| `last_eval` | No | eval, improve | `date`, `revision`, `score` (`<pass>/<total>`) of the last eval |
| `core_files` ... `known_issues` | Yes (fill what applies) | seed, improve | The model itself |

## Line limits

| Domain size | Limit |
| --- | --- |
| One module | 200-300 |
| A subsystem | 400-600 |
| Never exceed | 1000 (split instead) |

## What to keep when space runs out (in priority order)

1. `core_files` - navigation is the biggest time saver, and the Learn hook matches on it
2. `key_operations` - how the important things actually happen
3. `data_model` invariants and `known_issues` - prevent expensive mistakes
4. `conventions`
5. `integration_points`, `testing`

## Evals

`evals.yaml` holds 5-10 items, each `id`, `question`, `answer`, `evidence` (repo path), and `check`
(`grep: <regex>` against the evidence file, or `cmd: <read-only command>` that must exit 0). Template:
[../assets/expert-evals-template.yaml](../assets/expert-evals-template.yaml).

| Result | Meaning | Action |
| --- | --- | --- |
| `pass` | Model answer matches and check passes | None |
| `fail` | Model answer wrong or missing | `improve` the model |
| `stale` | Check fails; the expected answer is no longer true | A human fixes the eval |

A score under 80% after `improve` means the model needs a human look before agents rely on it.

## Validation checklist (used by `improve`)

- [ ] Changes since `source_revision` in this domain are reflected (`git diff --name-only <source_revision>..HEAD`,
      or `git log --since=<last_validated> --name-only` when the SHA is unknown)
- [ ] Every `path` exists (`git ls-files <path>`)
- [ ] Every `key_symbols` / `entry` symbol is found by Grep in its file
- [ ] Flows still match the code (read the entry points)
- [ ] Nothing describes code that no longer exists
- [ ] Under `line_limit`; `source_revision` and `last_validated` updated
- [ ] Evals re-run and `last_eval` updated

## When to create an expert

- The domain is high value or high risk (money, auth, data integrity, public contracts).
- Changes ripple across files, and agents keep re-discovering the same structure.
- You want higher confidence by running several experts in parallel and comparing answers.

Do not create experts for small or stable areas; priming is cheaper.
