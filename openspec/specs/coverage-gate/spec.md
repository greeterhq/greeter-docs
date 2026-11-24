# coverage-gate Specification

## Purpose

Decides which requirements on `main` across greeterHQ lack a passing scenario,
and fails the docs build with a message naming each one, so an uncovered
requirement can never be published as if it were verified.

## Requirements

### Requirement: Headings become slugs by the shared rule
A requirement or scenario heading SHALL become a slug as follows: lowercase the
text, replace each run of characters other than `a-z` and `0-9` with one `-`,
and trim `-` from both ends. The rule SHALL NOT split camel case.

#### Scenario: Slug rule turns headings into slugs
- **WHEN** the slug rule is given `A channel greets a valid guest`, `Clock#now raises NotImplementedError`, `Equal names agree across ==, eql?, hash, and uniq` and `"  --Leading and trailing!!  "`
- **THEN** it returns `a-channel-greets-a-valid-guest`, `clock-now-raises-notimplementederror`, `equal-names-agree-across-eql-hash-and-uniq` and `leading-and-trailing`

### Requirement: A requirement passes when a trace result for it passed
For a requirement with no entry in its repo's requirement-tag map, the coverage
rule SHALL treat it as covered only when that repo's CI trace or prod smoke
trace has at least one result with that requirement slug and status `passed`. Results with status
`failed`, `skipped` or `pending` SHALL NOT count. The rule SHALL be evaluated on
an in-memory docs model with no I/O.

#### Scenario: A passed result covers the requirement
- **WHEN** an in-memory model has repo `greeter-core` with requirement `greet-a-guest` and a trace result for it with status `passed`
- **THEN** the coverage rule returns no violation for `greet-a-guest`

#### Scenario: Only skipped or failed results do not cover the requirement
- **WHEN** an in-memory model has a requirement whose only trace results have statuses `skipped` and `failed`
- **THEN** the coverage rule returns a violation for that requirement

#### Scenario: A repo with no trace leaves its requirements uncovered
- **WHEN** an in-memory model has repo `greeter-cli` with two requirements and no trace
- **THEN** the coverage rule returns a violation for each of the two requirements

### Requirement: Tag-mapped requirements are covered by the prod ledger
For a requirement whose slug is a key in its repo's
`openspec/requirement-tags.yml`, the coverage rule SHALL ignore the repo trace.
It SHALL treat the requirement as covered when the prod ledger's `requirements`
entry for the mapped key has at least one channel with status `passed`. Stage
ledger results SHALL NOT count.

#### Scenario: A passed channel in the prod ledger covers a mapped requirement
- **WHEN** greeter-acceptance's tag map maps `a-channel-greets-a-valid-guest` to `greeting-happy` and the prod ledger has `greeting-happy` with `cli` `passed` and `http` `passed`
- **THEN** the coverage rule returns no violation for `a-channel-greets-a-valid-guest`

#### Scenario: Not-applicable alone does not cover a mapped requirement
- **WHEN** the prod ledger has a mapped key whose channels are all `not_applicable`, or has no entry for the mapped key
- **THEN** the coverage rule returns a violation for that requirement

#### Scenario: Stage results do not cover a mapped requirement
- **WHEN** the prod ledger has a mapped key with every channel `failed` and the stage ledger has the same key with `cli` `passed`
- **THEN** the coverage rule returns a violation for that requirement

#### Scenario: A missing prod ledger leaves mapped requirements unjudged
- **WHEN** the prod ledger is not yet recorded and greeter-acceptance has five tag-mapped requirements
- **THEN** the coverage rule returns no violation for any of the five, and each is reported as "not yet recorded"

### Requirement: Only requirements on main are checked
The coverage rule SHALL check the requirements in each repo's main specs
(`openspec/specs/**/spec.md` on `main`). It SHALL NOT check requirements that
appear only in `openspec/changes/`.

#### Scenario: A requirement only in a change is not checked
- **WHEN** a repo has a requirement in `openspec/changes/x/specs/cap/spec.md` that is absent from its main specs and has no trace result
- **THEN** the coverage rule returns no violation for it

### Requirement: The build fails and names every uncovered requirement
When the coverage rule returns any violation, the build SHALL exit non-zero,
publish nothing, and print one line per violation naming the repo, the
capability, the requirement slug and the spec file path.

#### Scenario: An uncovered requirement fails the build and is named
- **WHEN** the build runs with fixture sources where greeter-http's `version-headers` requirement `deployed-stage-exposes-version-headers` has only a `skipped` result
- **THEN** the build exits non-zero, `_site/` is not written, and the output contains `greeter-http`, `version-headers`, `deployed-stage-exposes-version-headers` and `openspec/specs/version-headers/spec.md`

#### Scenario: Every violation is listed, not just the first
- **WHEN** the build runs with fixture sources that have uncovered requirements in two repos
- **THEN** the output names both requirements with their repos, capabilities and spec files

#### Scenario: Full coverage passes the build
- **WHEN** the build runs with fixture sources where every requirement on main is covered
- **THEN** the build exits zero and writes `_site/index.html`
