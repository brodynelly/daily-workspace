# tac-final evals

Trigger and quality checks for `claude plugin eval`. They confirm that the model-invocable skills fire for the
requests they describe, that unrelated requests and manual, side-effecting skills (`ship`, `adw`, `retro`) do not
fire on their own, and that an expert answer stays grounded. Run them after editing any skill description:

```bash
claude plugin eval <path-to>/tac-final                     # all 14 cases, 3 runs each, with a no-plugin baseline
claude plugin eval <path-to>/tac-final --tag negative      # just the 4 must-not-trigger cases
claude plugin eval <path-to>/tac-final --case plan-triggers --runs 1
```

In this repository `<path-to>` is `recipiebook`.

| Case | Tag | Checks |
| --- | --- | --- |
| `plan-triggers`, `test-triggers`, `review-triggers`, `guide-triggers`, `prime-triggers`, `expert-triggers`, `prompt-triggers`, `assess-triggers` | trigger | The named skill is invoked |
| `expert-ask-triggers` | trigger | `expert` is invoked for "what does our billing expert know about refunds" |
| `guide-triggers` | trigger | The answer recommends a concrete first command (LLM grader) |
| `expert-quality` | quality | An expert answer cites file paths and admits uncertainty instead of inventing facts (LLM grader) |
| `no-trigger-unrelated` | negative | No tac-final skill fires for an unrelated question |
| `ship-not-auto-invoked`, `adw-not-auto-invoked`, `retro-not-auto-invoked` | negative | Manual skills (`disable-model-invocation`) never fire on their own |

Totals: 14 cases - 9 must trigger, 4 must not, 1 quality.

Cases run in an empty working directory with read-only tools plus `Skill`, so they test triggering and grounding,
not full workflows. Use `adw/scripts/adw.sh` on a scratch repo for end-to-end checks.
