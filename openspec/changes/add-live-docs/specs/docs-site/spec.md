# Spec Delta

## Purpose

Defines the pages of the greeterHQ live documentation site, what each page
shows, and the guarantees every page keeps: sourced text is HTML-escaped and
every internal link resolves.

## ADDED Requirements

### Requirement: The index summarises repos and coverage
`index.html` SHALL list each repo with a link to its page, show the coverage
summary (requirements covered, uncovered, and not yet recorded), and show when
the site was last updated (UTC, ISO 8601).

#### Scenario: Index lists repos and coverage
- **WHEN** the site is published from a model with five repos, 40 covered requirements and 5 not yet recorded
- **THEN** `index.html` links to `repos/<repo>.html` for each of the five repos, shows 40 covered, 0 uncovered and 5 not yet recorded, and shows the build time

### Requirement: Each repo has a page of requirements and results
`repos/<repo>.html` SHALL show one row per requirement on main, grouped by
capability, with its scenarios and the latest result per scenario. When the
trace has a `run_id`, the page SHALL link to
`https://github.com/greeterhq/<repo>/actions/runs/<run_id>`. When `run_id` is
null or not all digits, the page SHALL show no run link.

#### Scenario: A repo page shows its requirement rows
- **WHEN** the site is published from the fixture model for greeter-core
- **THEN** `repos/greeter-core.html` has one row per greeter-core requirement, each listing its scenarios with status `passed` and a link to `https://github.com/greeterhq/greeter-core/actions/runs/44297674561`

#### Scenario: A null run ID gives no run link
- **WHEN** a repo's trace has `run_id` `null`
- **THEN** its page shows the results and contains no link to `/actions/runs/`

### Requirement: A scenario verified only by the prod smoke trace links to its run
When a scenario's only `passed` result comes from the repo's prod smoke trace,
the repo page SHALL show it as `passed`, labelled as verified by the prod smoke
run, with a link to that `smoke-prod.yml` run at
`https://github.com/greeterhq/<repo>/actions/runs/<run_id>`. The digits-only
rule for run IDs applies.

#### Scenario: A prod-smoke-only pass links to the smoke-prod run
- **WHEN** greeter-http's CI trace (run 44622828436) has `smoke-check-on-a-deployed-stage` only `skipped` and its prod smoke trace (run `<smoke-run-id>`) has it `passed`
- **THEN** `repos/greeter-http.html` shows that scenario with `data-status="passed"`, labels it as verified by the prod smoke run, and links to `https://github.com/greeterhq/greeter-http/actions/runs/<smoke-run-id>`

### Requirement: The traceability grid shows requirement by channel
`traceability.html` SHALL show, for each ledger environment, a grid with one
row per ledger requirement key, labelled with the tag-mapped requirement, and
one column per channel. A cell SHALL show the channel's status. A channel
absent from a key's entry, or marked `not_applicable`, SHALL show `n/a`. Each
column SHALL show the channel's verification state and version.

#### Scenario: The prod grid renders from the real ledger
- **WHEN** the site is published with the fixture prod ledger
- **THEN** the prod grid has rows `greeting-count`, `greeting-happy`, `greeting-idempotent`, `greeting-invalid` and `greeting-returning`, with `greeting-count` showing `n/a` for `cli` and `passed` for `http`, and the `cli` and `http` columns showing `verified`

#### Scenario: A missing ledger shows not yet recorded
- **WHEN** the stage ledger is not yet recorded
- **THEN** the stage section of `traceability.html` says "not yet recorded" and contains no grid

### Requirement: The API page renders the OpenAPI description
`api.html` SHALL be rendered when the site is built, with no client-side script,
from greeter-http's `openapi.yaml`. It SHALL show the title, version and
description, and for each operation (path and method) its summary, parameters,
request body, responses and response headers, resolving local `$ref`s. The site
SHALL include an unmodified copy at `openapi.yaml`, and `api.html` SHALL link to
it.

#### Scenario: The API page shows the greetings operation
- **WHEN** the site is published with the fixture API description
- **THEN** `api.html` contains `POST` `/greetings` with its summary, each of its parameters, its request body schema, a row for each documented response status, and each documented response header, and contains no `<script>` element

#### Scenario: The API page links to a copy of the description
- **WHEN** the site is published with the fixture API description
- **THEN** `_site/openapi.yaml` is byte-identical to the fixture and `api.html` links to `openapi.yaml`

### Requirement: ADRs have an index and one page each
`adr/index.html` SHALL list every ADR with its repo and title, linking to
`adr/<repo>/<file-name-without-.md>.html`, which SHALL show the ADR's body
rendered from Markdown with raw HTML escaped. greeter-docs SHALL ship ADRs
`0001-record-architecture-decisions`, `0002-openspec-not-kiro-specs` and
`0003-shared-acceptance-suite-and-channel-ledger`.

#### Scenario: ADR pages are published for both repos
- **WHEN** the site is published from the real greeter-docs ADRs and fixture greeter-http ADRs
- **THEN** `adr/index.html` links to `adr/greeter-docs/0001-record-architecture-decisions.html`, `adr/greeter-docs/0002-openspec-not-kiro-specs.html`, `adr/greeter-docs/0003-shared-acceptance-suite-and-channel-ledger.html` and each greeter-http ADR page, and each linked page exists

### Requirement: The architecture page renders the C4 diagrams
`architecture.html` SHALL include each diagram's Mermaid text, escaped, inside a
`pre class="mermaid"` element. It SHALL load Mermaid only as an ES module from
one pinned, exact-version jsdelivr URL. greeter-docs SHALL ship
`docs/diagrams/c4-context.mmd` (`C4Context`) and `c4-container.mmd`
(`C4Container`). Between them they SHALL show greeter-core, greeter-cli,
greeter-http, greeter-acceptance, greeter-docs, the `ledger-prod` and
`ledger-stage` branches, and GitHub Pages.

#### Scenario: The architecture page loads one pinned Mermaid module
- **WHEN** the site is published from the real diagrams
- **THEN** `architecture.html` has two `pre class="mermaid"` elements, one starting `C4Context` and one `C4Container`, and exactly one `<script type="module">` whose import URL is `https://cdn.jsdelivr.net/npm/mermaid@<x.y.z>/dist/mermaid.esm.min.mjs` with an exact version

#### Scenario: The diagrams name every system
- **WHEN** the two diagram files are read
- **THEN** together they mention greeter-core, greeter-cli, greeter-http, greeter-acceptance, greeter-docs, `ledger-prod`, `ledger-stage` and GitHub Pages

### Requirement: Contracts and SLO pages are placeholders
`contracts.html` and `slo.html` SHALL exist and say "not yet available".

#### Scenario: Placeholder pages say not yet available
- **WHEN** the site is published with the null contract and SLO sources
- **THEN** `contracts.html` and `slo.html` each contain "not yet available"

### Requirement: No page renders unescaped sourced text
Every value that comes from a source (heading text, slugs, statuses, ADR and
diagram text, OpenAPI fields, ledger values) SHALL be HTML-escaped on every
page, including inside attributes.

#### Scenario: A script heading is escaped
- **WHEN** a fixture requirement heading, an ADR body, a diagram, an OpenAPI summary and a ledger channel name each contain `<script>alert(1)</script>`
- **THEN** no published page contains `<script>alert(1)</script>`, and the pages that show those values contain `&lt;script&gt;alert(1)&lt;/script&gt;`

### Requirement: A broken internal link fails the build
The build SHALL check every internal link in `_site/` offline and SHALL fail,
naming the page and the link, when any of them does not resolve.

#### Scenario: A broken internal link fails the build
- **WHEN** the link check runs on a site where `index.html` links to `repos/missing.html`
- **THEN** it exits non-zero and its output names `index.html` and `repos/missing.html`

#### Scenario: The published site has no broken internal links
- **WHEN** the link check runs on the site built from the fixture sources
- **THEN** it exits zero
