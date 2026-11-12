#!/usr/bin/env bash
# detect-project.sh - print what an agent needs to know to work in this repo.
#
# Usage: detect-project.sh [repo-dir]
# Output: "key: value" lines (one candidate per line; keys may repeat). Read-only, no network.
# Exit code is always 0 so callers can rely on the output even in unusual repos.

set -u
dir="${1:-.}"
cd "$dir" 2>/dev/null || { echo "error: cannot cd to $dir"; exit 0; }

say() { printf '%s: %s\n' "$1" "$2"; }
has() { [ -e "$1" ]; }
# safe_remote <url>: print only host/owner/repo. Strips scheme, userinfo (user:token@), port, and .git so
# credentials embedded in a remote URL are never echoed into a transcript.
safe_remote() {
  printf '%s\n' "$1" | sed -E \
    -e 's#^[A-Za-z][A-Za-z0-9+.-]*://##' \
    -e 's#[?\#].*$##' \
    -e 's#^[^/]*@##' \
    -e 's#^([^/:]+):([0-9]+)/#\1/#' \
    -e 's#^([^/:]+):#\1/#' \
    -e 's#/$##' -e 's#\.git$##'
}
has_script() { # $1 = npm script name
  has package.json && grep -Eq "\"$1\"[[:space:]]*:" package.json
}

# --- repository -------------------------------------------------------------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  say git yes
  say repo_root "$(git rev-parse --show-toplevel)"
  branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
  if [ -z "$branch" ]; then
    for b in main master trunk develop; do
      if git show-ref --verify --quiet "refs/heads/$b"; then branch="$b"; break; fi
    done
  fi
  [ -z "$branch" ] && branch="$(git branch --show-current 2>/dev/null)"
  say default_branch "${branch:-unknown}"
  say current_branch "$(git branch --show-current 2>/dev/null)"
  say tracked_files "$(git ls-files | wc -l | tr -d ' ')"
  if url="$(git remote get-url origin 2>/dev/null)"; then say remote "$(safe_remote "$url")"; fi
else
  say git no
fi
if command -v gh >/dev/null 2>&1; then say gh_cli yes; else say gh_cli no; fi

# --- existing agentic layer -----------------------------------------------
for f in CLAUDE.md .claude/CLAUDE.md AGENTS.md CLAUDE.local.md .cursorrules .github/copilot-instructions.md GEMINI.md; do
  has "$f" && say memory_file "$f"
done
for f in CLAUDE.md .claude/CLAUDE.md AGENTS.md; do
  if has "$f" && grep -q '^## Agentic layer (tac)' "$f"; then say tac_section "$f"; fi
done
for d in .claude/skills .claude/commands .claude/agents .cursor/rules; do
  has "$d" && say agent_dir "$d"
done
has .claude/settings.json && say claude_settings .claude/settings.json
has .mcp.json && say mcp_config .mcp.json
for d in specs docs/specs .specify .kiro/specs; do
  has "$d" && say specs_dir "$d"
done
for d in docs doc app_docs; do
  has "$d" && say docs_dir "$d"
done
has .claude/experts && say experts_dir .claude/experts
has .tac && say tac_dir .tac

# --- stack and validation candidates ---------------------------------------
if has package.json; then
  pm=npm
  has pnpm-lock.yaml && pm=pnpm
  has yarn.lock && pm=yarn
  { has bun.lockb || has bun.lock; } && pm=bun
  say stack node
  say package_manager "$pm"
  if command -v node >/dev/null 2>&1; then
    # Every npm script whose name looks like validation (lint, lint:md, test:unit, typecheck, build, ...).
    node -e 'const s=(require("./package.json").scripts)||{};
      for (const k of Object.keys(s))
        if (/^(lint|format:check|check|type-?check|test|e2e|build)(:|$)/.test(k) && !/fix|write|watch/.test(k)) console.log(k);' 2>/dev/null |
      while read -r s; do
        case "$s" in
          e2e*|test:e2e*) say e2e_candidate "$pm run $s" ;;
          *) say validate_candidate "$pm run $s" ;;
        esac
      done
  else
    for s in lint typecheck type-check check test build; do
      has_script "$s" && say validate_candidate "$pm run $s"
    done
  fi
  has tsconfig.json && ! has_script typecheck && ! has_script type-check && say validate_candidate "npx tsc --noEmit"
  { has playwright.config.ts || has playwright.config.js; } && say e2e_candidate "npx playwright test"
  { has cypress.config.ts || has cypress.config.js; } && say e2e_candidate "npx cypress run"
fi
if has pyproject.toml || has setup.py || has requirements.txt; then
  say stack python
  runner=""
  has uv.lock && runner="uv run "
  has poetry.lock && runner="poetry run "
  if has pyproject.toml; then
    grep -q '\[tool.ruff' pyproject.toml && say validate_candidate "${runner}ruff check ."
    grep -q '\[tool.mypy' pyproject.toml && say validate_candidate "${runner}mypy ."
  fi
  has ruff.toml && say validate_candidate "${runner}ruff check ."
  if has pytest.ini || has tests || has test || { has pyproject.toml && grep -q 'pytest' pyproject.toml; }; then
    say validate_candidate "${runner}pytest"
  fi
fi
has go.mod && { say stack go; say validate_candidate "go vet ./..."; say validate_candidate "go test ./..."; say validate_candidate "go build ./..."; }
has Cargo.toml && { say stack rust; say validate_candidate "cargo clippy --all-targets"; say validate_candidate "cargo test"; say validate_candidate "cargo build"; }
{ has pom.xml && say stack java-maven && say validate_candidate "mvn -q verify"; } || true
{ { has build.gradle || has build.gradle.kts; } && say stack java-gradle && say validate_candidate "./gradlew check"; } || true
# .sln at the root or project files up to two levels down (e.g. src/App/App.csproj); either one is enough.
if [ -n "$(find . -maxdepth 3 \( -name '*.sln' -o -name '*.slnx' -o -name '*.csproj' -o -name '*.fsproj' \) -not -path './.git/*' -print -quit 2>/dev/null)" ]; then
  say stack dotnet; say validate_candidate "dotnet build"; say validate_candidate "dotnet test"
fi
has Gemfile && { say stack ruby; has Rakefile && say validate_candidate "bundle exec rake"; }
has composer.json && { say stack php; say validate_candidate "composer test"; }
if has Makefile; then
  for t in lint check test build; do
    grep -Eq "^$t:" Makefile && say validate_candidate "make $t"
  done
fi
if has .markdownlint-cli2.jsonc || has .markdownlint.json || has .markdownlint-cli2.yaml; then
  say validate_candidate "npx markdownlint-cli2 \"**/*.md\""
fi
has .github/workflows && say ci .github/workflows
exit 0
