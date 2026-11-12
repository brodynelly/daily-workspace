# Feature: <descriptive name>

## Metadata

- Type: feature
- Source: <issue #, link, or "request">
- Date: <YYYY-MM-DD>

## Feature Description

<What the feature does and the value it delivers, in 2-4 sentences.>

## User Story

As a <role>, I want <capability> so that <benefit>.

## Solution Statement

<The approach in a few sentences, and why it fits the existing architecture.>

## Out of Scope

- <What this plan deliberately does not do>

## Relevant Files

- `path/to/existing.ext` - <why it matters / what changes>
- `path/to/new.ext` (new) - <purpose>

## Implementation Plan

### Foundation

<Setup, types, interfaces, configuration.>

### Core

<The main logic.>
### Integration
<Wiring, entry points, UI or API exposure.>

## Step by Step Tasks

1. <Task with file references>
2. <Task>
3. Add or update tests for the new behavior.
4. Run the Validation Commands and fix any failures.

## Testing Strategy

- Unit: <what to test>
- Integration / E2E: <what to test, or "none - reason">
- Edge cases: <boundaries, errors, empty states>

## Acceptance Criteria

- [ ] WHEN <condition> THE SYSTEM SHALL <observable behavior>
- [ ] <Criterion a reviewer can verify from the diff or by running a command>

## Validation Commands

- `<lint command>`
- `<test command>` - includes the new tests
- `<build command>`
- `<command that demonstrates the feature end to end>`

## Notes

<Risks, follow-ups, open questions.>
