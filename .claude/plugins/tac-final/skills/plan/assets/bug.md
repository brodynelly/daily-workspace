# Bug: <descriptive name>

## Metadata

- Type: bug
- Source: <issue #, link, or "request">
- Date: <YYYY-MM-DD>

## Bug Description

<What is wrong and who it affects.>

## Steps to Reproduce

1. <Step>
2. <Step>

- Expected: <behavior>
- Actual: <behavior, with the error message if any>

## Root Cause Analysis

<Why it happens, with file and line references. Distinguish evidence from hypothesis.>

## Solution Statement

<The fix, and why it addresses the root cause rather than the symptom.>

## Out of Scope

- <Related issues not fixed here>

## Relevant Files

- `path/to/file.ext` - <role in the bug / the fix>

## Step by Step Tasks

1. Write a failing test (or reproduction command) that captures the bug.
2. <Fix task with file references>
3. Confirm the test now passes.
4. Run the Validation Commands and fix any failures.

## Validation Commands

- `<command that reproduced the bug, now passing>`
- `<test command>`
- `<lint/build command>`

## Notes

<Regression risk, similar code that may share the bug.>
