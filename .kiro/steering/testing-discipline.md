---
inclusion: always
---
# Testing discipline (greeter-docs)

This file replaces the global testing-discipline rule for greeter-docs.
greeter-docs has no channel behaviour, so it has no Cucumber suite.

- TDD: write the failing RSpec example before the implementation. Show it red,
  for the right reason (NameError / expectation failure, not a syntax error).
- NEVER edit a file under spec/ to make it pass. If a test looks wrong, stop and
  say so.
- Every OpenSpec scenario is verified by exactly one RSpec example tagged with
  `requirement: '<requirement-slug>'` and `scenario: '<scenario-slug>'` (shared
  slug rule). Shared examples are included with `it_behaves_like` inside a
  tagged context. Test data that looks like a tag uses string keys or lives in
  `spec/fixtures/`.
- OpenSpec (openspec/) is the only spec system. Do not create Kiro Specs.
