# Spec Delta

## Purpose

Defines how the docs build reads its inputs (spec headings, repo traces,
ledgers, the API description, ADRs, diagrams, contracts and SLOs) and how it
reports an input that is invalid or not yet available.

## ADDED Requirements

### Requirement: Requirements and scenarios are read from main spec headings
The build SHALL read every `openspec/specs/**/spec.md` in the shallow clones of
greeter-core, greeter-cli, greeter-http and greeter-acceptance, and in the
greeter-docs checkout being built. The capability is the directory path relative to
`openspec/specs/`. Each `### Requirement:` heading is a requirement, and each
`#### Scenario:` heading is a scenario of the requirement above it. Both are
slugged by the shared rule.

#### Scenario: Headings in a nested capability are read
- **WHEN** a fixture clone of greeter-cli has `openspec/specs/tooling/live-docs-traceability/spec.md` with two `### Requirement:` headings, each followed by `#### Scenario:` headings
- **THEN** the source returns capability `tooling/live-docs-traceability`, both requirement slugs in file order, each with its own scenario slugs, and the spec file path

#### Scenario: Other heading levels are not requirements
- **WHEN** a fixture `spec.md` has `## Requirements`, `##### Note` and a fenced code block containing `### Requirement: Fake`
- **THEN** none of them is returned as a requirement or scenario

### Requirement: Repo traces are validated before use
The build SHALL read `tmp/traces/<repo>/repo-trace.json` for each repo. A trace
whose `schema` is not `greeterhq.repo-trace.v1`, whose `repo` differs from
`<repo>`, or that is not valid JSON SHALL fail the build with a message naming
the file and the reason. A missing trace file is not an error.

#### Scenario: A real trace is read
- **WHEN** the source reads the fixture trace downloaded from greeter-http's `ci.yml` run
- **THEN** it returns every result with its requirement, scenario, status, source and location, plus the trace's `sha`, `run_id` and `recorded_at`

#### Scenario: A trace with the wrong schema fails the build and is named
- **WHEN** `tmp/traces/greeter-core/repo-trace.json` has `schema` `greeterhq.traceability.v1`
- **THEN** the build exits non-zero with a message containing `tmp/traces/greeter-core/repo-trace.json` and `schema`

#### Scenario: A trace for another repo fails the build and is named
- **WHEN** `tmp/traces/greeter-cli/repo-trace.json` has `repo` `greeter-http`
- **THEN** the build exits non-zero with a message containing `tmp/traces/greeter-cli/repo-trace.json`, `greeter-cli` and `greeter-http`

#### Scenario: Malformed JSON fails the build and is named
- **WHEN** a trace file is not valid JSON
- **THEN** the build exits non-zero with a message naming the file

### Requirement: Ledgers are read for prod and stage
The build SHALL fetch `ledger.json` for `prod` and `stage` from
`https://raw.githubusercontent.com/greeterhq/greeter-acceptance/ledger-<env>/ledger.json`.
A ledger SHALL be used only if its `schema` is `greeterhq.ledger.v2` and its
`environment` equals `<env>`. Otherwise the build SHALL fail and name the
environment and the reason.

#### Scenario: The real prod ledger is read
- **WHEN** the fetcher returns the fixture `ledger.json` taken from `ledger-prod`
- **THEN** the source returns channels `cli` and `http` with their verification and run IDs, and the requirement keys `greeting-count`, `greeting-happy`, `greeting-idempotent`, `greeting-invalid` and `greeting-returning` with per-channel statuses

#### Scenario: A ledger with the wrong schema fails the build and is named
- **WHEN** the fetcher returns a stage ledger with `schema` `greeterhq.ledger.v1`
- **THEN** the build exits non-zero with a message containing `stage` and `schema`

### Requirement: A missing ledger is not yet recorded
When the fetcher reports that a ledger does not exist (HTTP 404), the source
SHALL return that environment as "not yet recorded" and the build SHALL
continue. Any other fetch failure SHALL fail the build and name the
environment.

#### Scenario: A missing ledger renders not yet recorded and the build passes
- **WHEN** the fetcher returns 404 for `stage` and every requirement is otherwise covered
- **THEN** the build exits zero and the traceability page's stage section says "not yet recorded"

#### Scenario: A server error is not treated as missing
- **WHEN** the fetcher returns HTTP 500 for `prod`
- **THEN** the build exits non-zero with a message containing `prod`

### Requirement: The API description is read from greeter-http
The build SHALL read `tmp/repos/greeter-http/openapi.yaml` as plain YAML data
(no aliases, tags or object loading). A missing or unparsable file SHALL fail
the build and name the file.

#### Scenario: The real API description is read
- **WHEN** the source reads a fixture copy of greeter-http's `openapi.yaml`
- **THEN** it returns the title `greeter-http`, the version, and the `POST /greetings` operation with its summary, parameters and responses

#### Scenario: A YAML file using a custom tag is refused and named
- **WHEN** the API description contains a `!ruby/object` tag
- **THEN** the build exits non-zero with a message naming `openapi.yaml`, and no object is created

### Requirement: ADRs and diagrams are read from docs folders
The build SHALL read ADRs from `docs/adr/*.md` in greeter-docs and in the
greeter-http clone, taking each title from the file's first `# ` heading. It
SHALL read diagrams from greeter-docs' `docs/diagrams/*.mmd`. ADRs and diagrams
are ordered by file name.

#### Scenario: ADRs from both repos are returned with their titles
- **WHEN** the source reads fixture folders with two ADRs for greeter-docs and two for greeter-http
- **THEN** it returns four ADRs, each with its repo, file name, title and body, ordered by repo and file name

#### Scenario: Diagrams are returned in file-name order
- **WHEN** the source reads a fixture folder with `c4-container.mmd` and `c4-context.mmd`
- **THEN** it returns two diagrams, `c4-container` first, each with its Mermaid text

### Requirement: Contracts and SLOs are not yet available
Until real contract and SLO sources exist, those sources SHALL return "not yet
available" and SHALL NOT fail the build.

#### Scenario: Null sources return not yet available
- **WHEN** the contract source and the SLO source are asked for data
- **THEN** each returns the "not yet available" state
