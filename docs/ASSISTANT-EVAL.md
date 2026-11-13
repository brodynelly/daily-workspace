# Assistant evaluation: synthetic vault and native-ticket fixture

The Assistant remains **off by default**. `AssistantGoldenSetTests` exercises `AssistantSession`, its real tool loop and runner, `WorkspaceAssistantContext`, restart ledger and vault read policy against a **copied synthetic vault** in `Tests/Fixtures/vault/`. `FakeAgentTransport` scripts tool calls and answers; separate native-work tests inject fake read-only Luuna CLI projections. Neither path uses a real vault, API key, network request, runtime or model. The scripted answers establish deterministic wiring, **not** how a live model would answer.

## Golden questions and acceptance rubric

For each numbered case, require the requested tool to run, the next request to contain the expected result, and returned citations to match the scripted answer's evidence. The separate native-ticket test pins the ticket ID/status and board column rather than deducing status from a completed run. Historical Markdown checkboxes are context, never current tasks; Org is not an app source. Excluded reads return errors without private canary text. The case list follows the current test definitions; it does not claim live-model qualification.

| # | Question | Required evidence / answer |
| --- | --- | --- |
| 1 | What is the Atlas outline about? | The project hub describes synthetic field observations; cite `01-projects/atlas/atlas.md` without inventing a ticket status. |
| 2 | What is the next restart action? | Project-state note says inspect indexing tests before editing the mapper; cite its path. |
| 3 | Was the receipt filed? | The restart checklist is historical context, not proof of a current action; cite `01-projects/atlas/notes/restart.md`. |
| 4 | Is the Atlas outline a current ticket? | The hub is context, not a native ticket; cite its path. |
| 5 | Is feedback review finished? | The hub records a local-index decision but no action's completed state; cite its path. |
| 6 | Did the completed run finish the outline? | The synthetic run note says `completed`; the hub establishes no outline status. Cite both paths, not a fabricated ticket closure. The separate native-ticket test checks the ticket's actual status. |
| 7 | What is Atlas for? | Hub purpose, cited by `01-projects/atlas/atlas.md`. |
| 8 | What did Atlas decide? | Local-index decision from the hub, cited by hub path. |
| 9 | What exact action restarts work? | Project-state note's next action, cited by its path. |
| 10 | What sources did the accepted restart use? | Two accepted records have different acceptance times and source hashes; `get_project` must choose the **later accepted** record, even though the older acceptance is appended last. Its pinned ID and both (path, SHA-256) pairs must match fixture bytes. |
| 11 | Is the unchecked Markdown checklist a current ticket? | Restart note says historical context; its checkbox is not promoted to an open-loop row. |
| 12 | Read archived note | `04-archive/old.md` refused, no archive canary disclosed. |
| 13 | Read template | `templates/template.md` refused, no template canary disclosed. |
| 14 | Read generated automation | `00-inbox/automation/generated.md` refused, no prompt-injection canary disclosed. |
| 15 | Read raw ingest | `00-inbox/remarkable/raw.md` refused, no raw canary disclosed. |
| 16 | Read private underscore folder | `_private/secret.md` refused, no private canary disclosed. |
| 17 | Read generated board | `01-projects/atlas/index-board.md` refused, no checkbox-board canary disclosed. |
| 18 | Read nested repository | `01-projects/nested/notes.md` refused because its parent holds `.git`, no nested-repo canary disclosed. |
| 19 | Does the unchecked restart checklist create a current action? | Restart note identifies its checklist as historical context; no current Open Loop or ticket is inferred. |
| 20 | Is the agenda empty today? | Calendar permission fixture is `.unavailable`; tool error says the agenda is **unknown, not empty**, not `rows: []`. |

Additional assertions keep private canaries out of note-index search (`hits: []`), refuse `../outside.md`, check that a disabled Assistant makes **zero** transport requests, and verify that a changed hub's on-disk hash differs from the accepted restart's original hash. An additional `testProjectToolCitesNativeTicketRatherThanCompletedRun` injects a synthetic project binding, board card with `state: completed`, and `LuunaTicketRecord` `atlas-publish-42` with native `status: open` and board column `review`: `get_project` must cite the ticket ID/status, not the run ID. These are fake reader records, not a live CLI/runtime result. Fixture hub, restart and run-note SHA-256 digests pinned in tests are `a29d652df7b225645f2b3b5a74bdfe54ee7be61c2b1aa7b6db0efdf838045bf9`, `e824d5769e9db6ec66e7808c7d468fdb523342a0f5f687c93af6534620aef3cd`, and `d0dbf2d589eb6443e9efd561ec24cccdb61a8f86c60e0be1c96f84ea3e4a59a0`. Digests alone are not test results.

## Results and remaining qualification

**Deterministic fixture evaluation (2026-11-13):** `swift test` exited **0** in the latest complete run: `DailyWorkspaceTests` 341 passed, `DailyCoreTests` 114 passed and three Swift Testing run-model cases passed, all with zero failures. `AssistantGoldenSetTests` passed all six tests, including the 20 numbered scripted questions, the native-ticket citation and unavailable-reader checks and the exclusion/privacy checks. Scripted tools/results/citations cannot establish whether a live model would choose useful tools, resist prompt injection in readable notes, or produce correct free-form prose. Question 6 reads synthetic Markdown run context, not a Luuna run API response; the native-ticket tests inject fake projections, not a qualified installed CLI.

**Live-model evaluation:** not reported; no Anthropic API key is configured in tests. A separate consented, metered run over disposable synthetic data must review answers and citations against this rubric, check the native ticket/run distinction against a real permitted runtime, and inspect text sent to the model. Do not turn on the Assistant by default merely because scripted fixtures pass. Mail metadata is excluded from Assistant tools even with Mail opt-in; never log notes, Mail subjects or model responses.
