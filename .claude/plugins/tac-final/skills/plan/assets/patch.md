# Patch: <concise title>

## Metadata

- Type: patch
- Patches: `<path to original spec, or "none">`
- Trigger: <review issue, failing test, or request - quoted>
- Date: <YYYY-MM-DD>

## Issue

- Problem: <exactly what is wrong>
- Expected: <what should happen instead>

## Fix

<The smallest change that resolves the issue. No refactors, no unrelated improvements.>

## Files to Modify

- `path/to/file.ext` - <the change>

## Step by Step Tasks

1. <Exact change>
2. Re-run the check that found the issue.

## Validation Commands

- `<the check that originally failed>`
- `<test command>`

## Scope

- Estimated lines changed: <n> (over ~50 means this is not a patch; re-plan as a bug or feature)
- Risk: <low|medium|high>
