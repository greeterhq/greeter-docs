# 1. Record architecture decisions

## Status

Accepted (2026-11-21)

## Context

greeter-docs publishes what five repos promise and prove. Decisions about how
it reads those repos, and what it refuses to publish, need to be findable later
by people who were not part of the conversation.

## Decision

We record architecture decisions as short Markdown files in `docs/adr/`,
numbered in order, each with Status, Context, Decision and Consequences. An ADR
is never rewritten once accepted; a later ADR supersedes it.

The live site renders every ADR in `docs/adr/` of greeter-docs and greeter-http
on its ADR pages.

## Consequences

- A decision has one place to live, next to the code it affects.
- ADR text is rendered with HTML escaped and only `http`, `https` and relative
  links kept, so an ADR cannot add script to the site.
