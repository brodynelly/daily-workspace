# Durable Assistant

What lets the Assistant keep working across questions, quits and days: vault writes with review and undo, long-term memory, saved conversations and routines. Approved by the owner on 2026-11-26 (AGENTS.md decisions log). The loop itself is in [AGENT-RUNTIME.md](AGENT-RUNTIME.md).

## Files

All under `~/.config/daily-workspace/agent/` (folders 0700, files 0600, written atomically):

| Path | Holds | Text? |
| --- | --- | --- |
| `vault-changes.json` | Pending changes and the newest 300 finished ones, with before/after text | Yes, so review and undo work |
| `vault-journal.jsonl` | One line per event: proposed, updated, applied, rejected, undone, failed; actor, path, hashes | No: paths and SHA-256 only |
| `memories/` | The `memory` tool's Markdown files (16 KB each, 256 KB and 200 files in all) | Yes |
| `conversations/<uuid>.chat` | One AES-GCM sealed conversation each; key in the Keychain (`app.dailyworkspace.agent-history`) | Sealed |
| `routines.json` | The user's routines and each one's last run | Prompts only |

## Vault writes

`create_note`, `edit_note` (one exact `old_text` → `new_text`) and `append_to_note` call `AgentWorkspace.propose`, implemented by `VaultChanges`:

1. The path must pass `VaultReadPolicy` (scope exclusions, no symlinks or nested repos), end in `.md` and sit in an existing folder that is not the vault root.
2. A note open in Notes with unsaved edits is refused. A second change to a note already waiting (in the same vault) is folded into the same pending change, so review shows one before/after per note, and it stays in review whatever the policy; a waiting change whose note changed on disk is marked failed.
3. The change is computed against the text on disk (CRLF kept) and size-checked (`maxNoteBytes`). Its journal line and the queue with its before/after text are written first; if either fails, nothing reaches the vault. Then it is applied or queued by the policy below.
4. Apply re-reads the note and writes only if it still equals the stored `before` (an open, clean editor applies it instead, so the two never race). Undo writes `before` back only if the note still equals `after`. A change records the vault root it was proposed in and is applied or undone only while that vault is selected. A created note cannot be undone: that would delete a vault file (CONTRIBUTING invariant 3).

The tool result says `applied` or `awaiting_review`; the prompt tells the model never to call a queued change saved. If a later request in the same answer fails, the completed rounds are kept (turn, tool calls and transcript, closed by a short note), so neither the card nor the model forgets a change that already happened.

### Approval policy (Settings → AI → Agent)

| `writeApproval` | Applied at once | Always reviewed |
| --- | --- | --- |
| `review` | nothing | everything |
| `auto-folders` (default, folder `00-inbox`) | new notes and appends inside `autoApplyFolders` | edits; anything outside the folders |
| `auto-all` | new notes and appends anywhere | edits |

In every mode these wait for review: edits to existing text; a change that adds a link or embed (wikilinks and `![[embeds]]`, `[text](target)`, reference links, any `scheme://` or `mailto:`/`data:`/`obsidian:` URL, and HTML tags that load or link something); and any change past `maxAutoWritesPerRun` (default 10). Model-written links are an exfiltration path when rendered, embeds pull other notes in, and the cap bounds a runaway loop. Conflict checks compare UTF-8 bytes, so a note re-saved in another Unicode normalization counts as changed. Review lives behind **Changes** on the Assistant page.

## Memory

The `memory` tool follows Anthropic's memory-tool commands (`view`, `create`, `str_replace`, `insert`, `delete`, `rename`) over `/memories/…` paths, resolved inside the app folder only (no `..`, hidden names, symlinks or other extensions). Each question carries a `<memory_index>` of paths and sizes, never contents; the model views what it needs. Settings → AI → Agent → Show files opens the folder.

## Saved conversations

Every question is saved twice: before it runs (with `interruptedQuestion` set) and after it finishes or fails. A conversation is reopened from the Quick Panel's chat list; after a crash, the interrupted question returns as the draft. The transcript replays byte-for-byte only when the provider, model and `contextFingerprint` (vault identity, system prompt and tool definitions) match; otherwise its answers show and follow-ups start fresh context. Retention (default 180 days) runs at launch; Delete all history removes the files and the key, starts a new open conversation, and drops copies the Quick Panel holds, so a deleted conversation is never reopened or saved again. Turning saving off writes nothing new and deletes nothing.

## Routines

`RoutineScheduler` checks once a minute while the app runs, starts at most one due routine at a time in a sibling session (same limits, tools and workspace, so the open chat is untouched), and records `lastRunAt` before the run so a failing routine cannot retry every minute. Turning the Assistant off or switching vaults stops a running routine's request at once. A routine's saved conversation appears in the Quick Panel's CHATS the next time the AI page opens. Missed slots collapse into one catch-up run. The prompt is framed as unattended; a routine follows the same approval policy, and its edits always wait for review. Routines do not run while the Mac sleeps or the app is closed; there is no background agent.

## Not adopted

A SQLite journal (JSON plus an fsynced JSONL journal covers one user and one process), deleting or moving vault files, writes to Org, Luuna, Calendar or Reminders, a launchd background agent, and client-side transcript trimming (breaks replayed thinking).
