---
name: install-app
description: Install, update or relaunch Daily Workspace in /Applications on this Mac — runs the baseline recipes, builds a release bundle, backs up the old copy, installs, links the daily CLI, launches and enables Start at Login. Use when asked to "install the app", "update the app", "spin up the app", "redeploy", or after pulling new changes.
---

# Install / update Daily Workspace

1. Run `git status`. If another agent's work is in progress, say so before you build.
2. Run `just run` (or `scripts/install_app.sh`) from the repo root; `just quick` skips checks. Pass `--skip-checks` only if the user asks for a fast reinstall, and `--no-launch` to install without starting the app. Report the script's real exit status.
3. If it fails:
   - At baseline: fix the root cause, up to 3 attempts, and don't commit. Or report the failure.
   - "App is still open": ask the user to resolve the unsaved note, then rerun.
   - At `install_daily_cli.sh` "Refusing…": show where `~/.local/bin/daily` points and ask the user before changing it.
4. If `daily login status` says `requiresApproval`, ask the user to approve it in System Settings → General → Login Items.
5. Tell the user the Calendar permission may reset, because the app is ad-hoc signed. They re-grant it in the app when asked.
6. Summarize in a few lines: the checks run, the install and backup paths, `daily status` and `daily login status`.

Boundaries, from AGENTS.md: don't edit the vault, dotfiles or skhd, don't do Luuna or Org writes, don't touch `tasks.json`, and don't delete backups or QAP/QAM rollback bundles. Commit only when asked.
