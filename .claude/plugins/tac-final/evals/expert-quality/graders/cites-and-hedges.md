---
type: llm
weight: 1
---

The working directory is empty, so there is no billing expertise file and no billing code. The response passes
only when all of these hold:

1. It cites the concrete file paths it checked or would read, such as `.claude/experts/billing/expertise.yaml`,
   rather than speaking about files in general.
2. It says plainly what it does not know: no expertise or source was found, so it cannot state how partial
   refunds are calculated.
3. It does not invent refund rules, formulas, function names, or file paths presented as facts about this
   codebase.
4. It suggests a concrete next step, such as `/tac-final:expert create billing` or pointing it at the billing code.

Fail the response if it presents a confident refund policy or names billing source files as if they exist.
