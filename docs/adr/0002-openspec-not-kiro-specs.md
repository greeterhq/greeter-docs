# 2. OpenSpec, not Kiro Specs

## Status

Accepted (2026-11-21)

## Context

Every greeterHQ repo states its requirements as `### Requirement:` headings with
`#### Scenario:` headings below them, and tags its tests with the slugs of those
headings. greeter-docs needs one spec format it can read the same way in every
repo, and the agents that work on these repos need one place to look for
requirements.

## Decision

OpenSpec (`openspec/`) is the only spec system in greeterHQ. Changes are
proposed under `openspec/changes/` and archived into `openspec/specs/`. Kiro
Specs are not created.

greeter-docs reads requirements from the `openspec/specs/**/spec.md` headings on
`main` and slugs them with the shared rule: lowercase, each run of characters
other than a-z and 0-9 replaced by one `-`, and `-` trimmed from both ends. It
does not call the OpenSpec CLI, so CI needs no Node toolchain and the slugs
match each repo's trace check by construction.

## Consequences

- Requirements in un-archived changes are not shown and are not checked for
  coverage until they reach `main`.
- A change to the slug rule must land in every repo's trace check and in
  greeter-docs together.
