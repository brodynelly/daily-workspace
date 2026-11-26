# Assistant agent runtime

How the Assistant runs a question: the loop, its limits, how to configure them and how to extend it. Read with [SYSTEM-INVENTORY.md](SYSTEM-INVENTORY.md) §4–§10; the rules there (statuses from adapters, no logged content) are unchanged. Vault writes, memory, saved conversations and routines are described in [DURABLE-AGENT.md](DURABLE-AGENT.md).

## Shape

```
AssistantSession.send / draftRestartRecord        (profile: chat or draft; effort and schema)
  └─ runLoop                                      (AssistantSession+Loop.swift)
       ├─ sendRequest ─ RetryingAgentTransport ─ AnthropicClient | OpenRouterClient
       │                  (SDK backoff, only before anything streamed)
       ├─ checkStop     refusal · max_tokens · model_context_window_exceeded · empty
       └─ runTools ─── AssistantToolRunner         (concurrent, ordered results)
                          enabled tools only → ToolArguments check → AgentDeadline → result budget
  every step → AgentRunEvent → AgentRunTrace (summary) + observers + one public log line
```

The loop stays hand-written on purpose: Anthropic's guidance is to keep agents simple and transparent, and the app's constraints (thinking blocks replayed byte-for-byte, an append-only in-memory transcript, no write tools) are easier to guarantee without a framework. The transcript is never trimmed or summarised client-side: on Opus 5.5 that would invalidate later thinking blocks. Context is bounded where it enters instead, through tool result budgets.

## Configuration

`~/.config/daily-workspace/settings.json`, key `assistantRuntime`, also editable in **Settings → AI → Runtime**. Edit the file only while the app is closed (the app rewrites it). Missing or mistyped keys keep their defaults, and every value is clamped.

| Key | Default | Range | Effect |
| --- | --- | --- | --- |
| `maxToolRounds` | 8 | 1–20 | Tool rounds per question; the last round tells the model to answer from what it has. |
| `maxOutputTokens` | 16000 | 1024–64000 | `max_tokens` per request. |
| `chatEffort` / `draftEffort` | `low` / `medium` | `low` `medium` `high` `xhigh` `max` | `output_config.effort` for chat turns and restart drafts. |
| `maxRetries` | 2 | 0–5 | Retries of 408/409/429/5xx/529, timeouts and dropped connections. |
| `toolTimeoutSeconds` | 30 | 2–300 | A slower tool call is answered with "source unknown right now, not empty". |
| `maxToolResultBytes` | 100000 | 4096–400000 | Larger results are cut on a character boundary with a narrowing hint (about Claude Code's 25,000-token cap). |
| `disabledTools` | `[]` | tool names | Removes tools from the request and refuses calls to them. Changing it starts a new conversation, and chats from before the change reopen without their model context. |

```json
"assistantRuntime" : {
  "chatEffort" : "low",
  "disabledTools" : [ "get_agenda" ],
  "maxRetries" : 2,
  "maxToolRounds" : 10
}
```

Changes apply from the next question; a running answer keeps the limits it started with. Settings can only narrow what the app built in. There is no setting that adds a tool, a write or a command hook.

## Retries

`RetryingAgentTransport` wraps any `AgentTransport` and follows the official Anthropic SDKs: 2 retries, a wait of `min(0.5 × 2ⁿ, 8)` seconds shortened by up to 25 % at random, and the server's `retry-after-ms`, `retry-after` and `x-should-retry` headers. Two app-specific rules: a request is never retried once any text or tool call has streamed (so nothing the person saw is repeated), and a server wait longer than 60 s, or a 429 with no `retry-after` (a spent cap), fails at once with the server's message.

## Observability

`AgentRunEvent` (request started/finished, retrying, tool started/finished, finished) carries names, counts, stop reasons, token usage and durations, never questions, note text, tool arguments or answers, following OpenTelemetry GenAI's no-content default. `AssistantSession.addRunObserver` registers a hook; `lastRunSummary` and `conversationUsage` are published for the UI; one `Log.assistant` line per run records the summary. Each answer card shows its tokens: billed input (with the cached share), output, and how much of the context window the conversation now fills.

## Adding a tool

1. Add a case to `AssistantTool` with its `summary` (3–4 sentences: what, when, what it returns) and `parameters`.
2. Add its read to `AssistantContext` (and `WorkspaceAssistantContext`), applying the vault exclusion policy and source states first.
3. Add its branch to `AssistantToolRunner.execute`, returning cited paths or record IDs.
4. Add golden-set cases. Deadlines, result budgets, `disabledTools`, Settings toggles and run events apply automatically.

A read tool must be read-only. A vault write goes through `AgentWorkspace` and `VaultChanges` (see DURABLE-AGENT.md), never straight to `NoteVault`; writes to any other owner need the owner's approval first.

## Deliberately not adopted

User command hooks (the approval policy in DURABLE-AGENT.md gates writes), model-based tool routing (six tools), client-side history pruning or summarisation (breaks replayed thinking), dollar-cost estimates (prices change; tokens are shown instead), and server-side context editing or compaction (beta; revisit if long chats hit the context window). The research behind these choices is summarised in the PR that introduced this layer.
