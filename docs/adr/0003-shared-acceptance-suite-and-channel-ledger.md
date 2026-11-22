# 3. Shared acceptance suite and channel ledger

## Status

Accepted (2026-11-21)

## Context

greeter-cli and greeter-http are two channels for the same greeting behaviour,
and they release independently. Each repo's own tests show that the repo is
internally consistent, but not that a deployed channel behaves as the shared
greeting requirements say.

## Decision

greeter-acceptance owns the channel behaviour requirements (`greeting`) and one
suite that runs them against every channel through a driver per channel. When a
channel is released, or a new suite version is published, record mode runs the
suite against the deployed version and publishes the result per requirement and
channel to a ledger branch per environment: `ledger-prod` and `ledger-stage`,
each holding `ledger.json` in schema `greeterhq.ledger.v2`.

greeter-docs reads both ledgers. A `greeting` requirement is covered when at
least one channel passed it in the prod ledger; `not_applicable` alone is not a
pass. Stage is shown on the traceability page but never counts. While the prod
ledger is missing, those requirements are shown as not yet recorded and do not
fail the build.

## Consequences

- A channel that has not been released against the current suite shows its last
  recorded result, with its verification state.
- `openspec/requirement-tags.yml` in greeter-acceptance maps each greeting
  heading slug to its ledger key, and those keys are never renamed.
