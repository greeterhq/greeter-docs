# Proposal

## Why

greeterHQ's requirements, test results and channel ledgers live in four repos
and two ledger branches, and nothing shows them together or catches a
requirement on `main` that no passing test covers. The producers already
publish what a docs site needs: greeter-core, greeter-cli, greeter-http and
greeter-acceptance each upload a `greeterhq.repo-trace.v1` artifact from
`ci.yml` on `main` and send `docs-refresh`, and greeter-acceptance publishes
`greeterhq.ledger.v2` to `ledger-prod` and `ledger-stage`. greeter-docs is the
consumer that is still missing.

## What Changes

- New hexagonal Ruby application under `lib/greeter_docs/`:
  - a pure domain (`domain/`) with the shared heading slug rule and a coverage
    rule that lists every requirement on `main` with no passing scenario;
  - source ports for specs, traces, ledgers, the API description, ADRs,
    diagrams, contracts and SLOs, plus a publisher port (`ports/`);
  - adapters that read shallow clones, downloaded trace artifacts, the raw
    ledger files, local docs, and an ERB HTML publisher (`adapters/`).
- `bin/fetch-sources`: shallow-clones the four producer repos at `main` and
  downloads each one's latest successful `main` `ci.yml` `repo-trace` artifact.
  For greeter-http it also downloads the prod smoke trace
  (`repo-trace-smoke-prod`) from the latest successful `main` run of
  `smoke-prod.yml`, because the requirements verified only against a deployed
  stage are always skipped in CI.
- `bin/build-docs`: composition root. It builds the site into `_site/` and
  exits non-zero, listing each violation, when coverage fails or a source is
  invalid.
- Pages: an index, one page per repo, the traceability grid
  (requirement x channel), the API page (rendered server-side from
  `openapi.yaml`, with a link to a copy of the file), the ADR pages, the
  architecture page (Mermaid C4), and placeholder pages for contracts and SLOs.
- greeter-docs checks its own requirements. RSpec writes
  `tmp/traces/greeter-docs/repo-trace.json` with a formatter copied from
  greeter-cli, in the same job, before `bin/build-docs`.
- `.github/workflows/docs.yml`: build (with a read-only GitHub App token, RSpec,
  build, and an offline lychee check) on push, refresh, schedule, manual run and
  pull request, and a deploy to GitHub Pages at
  https://greeterhq.github.io/greeter-docs/ for everything except pull
  requests.
- Project setup brought in line with this design: the `openspec/config.yaml`
  context and task rules, `.kiro/hooks/tdd-guards.json` (the `lib/greeter_docs`
  matcher, no Cucumber, Ruby 3.3.13), and a workspace testing-discipline
  steering file (RSpec only).
- ADRs 0001–0003 in `docs/adr/`, and C4 context and container diagrams in
  `docs/diagrams/`.

### Ports and pages touched

- Source ports: SpecSource, TraceSource, LedgerSource, ApiSource, AdrSource,
  DiagramSource, ContractSource (null), SloSource (null). Outbound: Publisher.
- Pages: `index.html`, `repos/<repo>.html`, `traceability.html`, `api.html`
  (plus `openapi.yaml`), `adr/index.html` and `adr/<repo>/<slug>.html`, `architecture.html`,
  `contracts.html`, `slo.html`.

### New dependencies on other repos' artifacts

- greeter-core, greeter-cli, greeter-http, greeter-acceptance:
  `openspec/specs/**/spec.md` on `main`, and the `repo-trace` artifact of the
  latest successful `main` run of `ci.yml`.
- greeter-acceptance: `openspec/requirement-tags.yml`, and `ledger.json` on the
  `ledger-prod` and `ledger-stage` branches.
- greeter-http: `openapi.yaml` and `docs/adr/*.md`, and the
  `repo-trace-smoke-prod` artifact of the latest successful `main` run of
  `.github/workflows/smoke-prod.yml`. greeter-http adds that workflow
  separately; this change only reads its artifact.

## Non-goals

- Writing to, or opening PRs against, any other repo. All sources are read-only.
- Contract-test (Pact) and SLO data. Those pages are placeholders until later
  changes add real sources.
- Using the `repository_dispatch` `client_payload` to choose what is fetched or
  built. Every run rebuilds everything from `main`.
- Rendering un-merged OpenSpec changes. Only main specs count.
- Interactive API consoles (Redoc, Swagger UI) and any client-side script other
  than the pinned Mermaid module.
- Per-version history of results. The site shows the latest results only.

## Capabilities

### New Capabilities

- `coverage-gate`: deciding, from specs, traces, the requirement-tag map and the
  prod ledger, which requirements on `main` lack a passing scenario. The build
  fails and names them.
- `docs-sources`: reading and validating every input (spec headings, repo
  traces, ledgers, the API description, ADRs, diagrams, and the null contract
  and SLO sources). It also defines how invalid or missing inputs are reported.
- `docs-site`: the published pages, what each one shows, HTML escaping of every
  sourced value, and the internal-link check.
- `docs-deployment`: the `docs.yml` triggers, credentials, permissions,
  concurrency, greeter-docs' own trace, and Pages deployment.

### Modified Capabilities

None. `openspec/specs/` is empty.

## Impact

- New code: `lib/greeter_docs/**`, `bin/build-docs`, `bin/fetch-sources`,
  `templates/*.erb`, `.github/workflows/docs.yml`, `spec/**` (including
  `spec/support/repo_trace/`, copied from greeter-cli).
- New docs: `docs/adr/0001–0003`, `docs/diagrams/c4-context.mmd`,
  `docs/diagrams/c4-container.mmd`.
- Changed config: `openspec/config.yaml`, `.kiro/hooks/tdd-guards.json`, and the
  new `.kiro/steering/testing-discipline.md`.
- Gems: none added. The YAML, JSON and ERB support comes from the standard
  library.
- Pull requests now run the docs build, so a coverage failure shows before
  merge.
- External: a GitHub App with read access to the four repos
  (`vars.DOCS_READER_APP_CLIENT_ID`, `secrets.DOCS_READER_APP_PRIVATE_KEY`).
  GitHub Pages must be enabled with source "GitHub Actions". `lychee` runs in CI.
- greeter-http's `deployed-stage-exposes-version-headers` is verified only by
  its `@smoke` scenario, which `ci.yml` always skips. Until greeter-http's
  `smoke-prod.yml` has produced a passing `repo-trace-smoke-prod` artifact,
  `bin/build-docs` fails and names that requirement (see design.md, D12 and
  Risks). greeter-http's workflow must land, and run once, before this change
  merges.
