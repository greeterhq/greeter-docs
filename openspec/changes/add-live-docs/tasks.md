# Tasks

Test files under `spec/` are written only in group 1, with
`tmp/allow-test-edits` present. Remove that file when group 1 ends, and never
edit those files in later groups. If a test looks wrong later, stop and raise
it.

Every example that verifies an OpenSpec scenario in this change carries exactly
one `requirement:` and one `scenario:` slug (shared slug rule). Each scenario
has exactly one such example. Shared examples are included with
`it_behaves_like` inside a tagged `context`. Tag-like test data uses string keys
or lives in `spec/fixtures/`.

## 1. Red tests

- [x] 1.1 Add `.rspec` (`--require spec_helper`) and `spec/spec_helper.rb`. Copy greeter-cli's `spec/support/repo_trace_formatter.rb` and `spec/support/repo_trace/document.rb` at 7b43842, with `REPO = 'greeter-docs'` and a header comment naming the source commit. Verify that `bundle exec rspec --format RepoTraceFormatter` with `REPO_TRACE_PATH=tmp/traces/greeter-docs/repo-trace.json` runs with 0 examples and writes a v1 file with no results.
- [x] 1.2 Capture the fixtures into `spec/fixtures/`. Run the four `gh run download` commands and `git show 5bbea1ad31a5bb9b1bbe73ec466d16c55b2262aa:ledger.json` exactly as listed in design.md, Fixtures. Copy each sibling checkout's `openspec/specs/**` and `openspec/requirement-tags.yml` at the recorded commits, and greeter-http's `openapi.yaml` and `docs/adr/*.md` at 5b818a2. Verify that the sha256 of each trace and of the ledger matches design.md.
- [x] 1.3 Write the domain specs `spec/domain/slug_spec.rb` and `spec/domain/coverage_rule_spec.rb`, in-memory only, with one tagged example per `coverage-gate` domain scenario. Verify that they fail with `NameError` for `GreeterDocs::Domain::Slug` and `CoverageRule`.
- [x] 1.4 Write the adapter specs for `GitSpecSource` (fixture clones, a nested capability, fenced code, a greeter-docs workspace root) and `ArtifactTraceSource` (the real traces, plus wrong-schema, wrong-repo and malformed-JSON variants). Verify that they fail with `NameError`.
- [x] 1.5 Write the adapter specs for `RawLedgerSource` (an injected fetcher returning 200 with the fixture, 404, 500, and a wrong schema), `FileApiSource` (including the `!ruby/object` case), `FileAdrSource`, `FileDiagramSource`, `NullContractSource` and `NullSloSource`. Verify that they fail with `NameError`.
- [x] 1.6 Write `spec/bin/fetch_sources_spec.rb` (stubbed runner: the expected argv, no greeter-docs command, an empty run list, token redaction), `spec/support/repo_trace_formatter_spec.rb` (the v1 document for greeter-docs), and `spec/workflows/docs_workflow_spec.rb` (parses `docs.yml` for each `docs-deployment` workflow scenario). Verify that they fail with `NameError` or `Errno::ENOENT` for the missing files.
- [x] 1.7 Write the publisher snapshot spec `spec/adapters/erb_html_publisher_spec.rb`. It publishes the fixture model to a temp dir and asserts:
  - the greeter-core requirement rows and the run link;
  - the prod grid cells (`n/a`, `passed`, `verified`) and stage "not yet recorded";
  - the API operation's parameters, request body, responses and headers, and the byte-identical `openapi.yaml` copy with its link;
  - the ADR links, the pinned Mermaid module and the placeholders;
  - `<script>alert(1)</script>` escaped on every page.

  Verify that it fails with `NameError`.
- [x] 1.8 Write `spec/build_spec.rb` for the build use case: violations named with repo, capability, requirement and spec file; all violations listed; no `_site` on failure; a missing ledger passing; a pass with full coverage. Add `spec/coverage_of_self_spec.rb`, which checks that every greeter-docs `#### Scenario:` in this change has exactly one tagged example (from RSpec's example metadata). Verify that both fail. `build_spec` should fail with `NameError`. `coverage_of_self_spec` should fail with an expectation failure listing any scenario that has no example.
- [x] 1.9 Write the security specs for design S1–S7, S9 and S10:
  - `spec/support/log_safety_spec.rb`: values starting with `::`, values containing newlines or control characters, and a non-slug `repo` value are printed neutralised or as `(invalid value)`.
  - the `fetch_sources_spec` examples for `--event push`/`--event schedule` selection, including the fork-PR scenario.
  - `docs_workflow_spec` examples for the `permission-*` inputs, `BUNDLE_FROZEN`, and a Gemfile with a single source and no `greeter-*` gem.
  - limits examples: oversize trace, ledger and `openapi.yaml`; a YAML alias; a `$ref` cycle; an external `$ref` that is never fetched (the fetcher spy is not called).
  - publisher examples: `javascript:` variants dropped from ADR links; a non-digit ledger `run_id` gives no link; a non-slug channel or key never reaches an `id`/`href` unescaped; a CSP meta tag on every page and no inline `<script>`; the API page shows the greeter-http commit and `info.version`.

  Tag the examples that verify a spec scenario. Verify that they fail with `NameError` or expectation failures.
- [x] 1.10 Remove `tmp/allow-test-edits` and commit the red tests. Verify that `git status` shows no changes under `spec/`.

## 2. Domain

- [x] 2.1 Implement `Domain::Slug` and the value objects (`Repo`, `Requirement`, `Scenario`, `Result`, `LedgerView`, `ApiDescription`, `Adr`, `Diagram`, `DocsModel`, `Violation`). Verify that `spec/domain/slug_spec.rb` is green and that `grep -rE "File|IO|Net|Open3|Dir" lib/greeter_docs/domain` finds nothing.
- [x] 2.2 Implement `CoverageRule#violations(model)` and the pending (not yet recorded) set, per design D3. Verify that `spec/domain/coverage_rule_spec.rb` is green.
- [ ] 2.3 Add the port modules in `lib/greeter_docs/ports/`, each documenting its method contract. Verify that the domain specs still pass and that RuboCop is clean.

## 3. Source adapters

- [ ] 3.1 Implement `GitSpecSource`: the heading parser that skips fenced code, nested capability paths, the tag map read with `YAML.safe_load`, and greeter-docs read from the workspace root. Verify that its adapter spec is green.
- [ ] 3.2 Implement `ArtifactTraceSource` and the `SourceError` messages. Verify that its adapter spec is green.
- [ ] 3.3 Implement `RawLedgerSource` with the injected fetcher and the default `Net::HTTP` fetcher (10 s timeout, no redirects). Verify that its adapter spec is green.
- [ ] 3.4 Implement `FileApiSource`, `FileAdrSource`, `FileDiagramSource`, `NullContractSource` and `NullSloSource`. Verify that their adapter specs are green.

## 4. Publisher and pages

- [ ] 4.1 Implement `ErbHtmlPublisher` with the `h()` helper and the layout, index, repo and traceability templates. Verify that the publisher spec's index, repo-page and grid examples are green.
- [ ] 4.2 Add `api.erb` (operations, parameters, request body, responses and headers, with local `$ref`s resolved) and the `openapi.yaml` copy. Verify that the publisher spec's API examples are green.
- [ ] 4.3 Add the escaping Markdown renderer and the ADR index and page templates. Verify that the publisher spec's ADR examples are green.
- [ ] 4.4 Add the architecture template (Mermaid 11.17.2 ESM, `securityLevel: "strict"`) and the contracts and SLO placeholders. Verify that the whole publisher spec, including the escaping example, is green.
- [ ] 4.5 Write `docs/adr/0001-record-architecture-decisions.md`, `0002-openspec-not-kiro-specs.md` and `0003-shared-acceptance-suite-and-channel-ledger.md`, and `docs/diagrams/c4-context.mmd` (`C4Context`) and `c4-container.mmd` (`C4Container`) naming every system listed in the `docs-site` spec. Verify that the diagram example in the publisher spec is green and that each diagram renders at mermaid.live without errors.

## 5. Composition and tooling

- [ ] 5.1 Implement `GreeterDocs::Build` and `bin/build-docs`: collect the source errors and coverage violations, print one line each, exit 1, and write no `_site` on failure. Verify that `spec/build_spec.rb` is green.
- [ ] 5.2 Implement `bin/fetch-sources` with an injectable `Open3` argv runner, per-repo cleanup of `tmp/repos/<repo>` and `tmp/traces/<repo>`, and token redaction. Verify that its spec is green, except the event-selection and fork-PR examples, which go green in 7.2.
- [ ] 5.3 Run the full suite with the formatter. Verify that `spec/coverage_of_self_spec.rb` is green and that `tmp/traces/greeter-docs/repo-trace.json` has one passed result per greeter-docs scenario.

## 6. Workflow

- [ ] 6.1 Write `.github/workflows/docs.yml` per design D10:
  - triggers including `pull_request`, and `concurrency: pages`;
  - top-level `permissions: {}`;
  - `ruby-version: "3.3"` with the greeter-acceptance comment;
  - the "Install lychee" step (lychee-v0.24.2, sha256 `1f4e0ef7…951c9a`, checked with `sha256sum -c`, added to `GITHUB_PATH`) and the "Lint" step (`bundle exec rubocop`), both before the RSpec step;
  - the link check as a `run:` step, `lychee --offline --no-progress _site`, using that binary (the only lychee install; no `lycheeverse/` action);
  - the RSpec step with the formatter and `REPO_TRACE_PATH`;
  - the `build` job, and the `deploy` job with `if: github.event_name != 'pull_request'`;
  - actions pinned by SHA.

  Verify that `spec/workflows/docs_workflow_spec.rb` is green, except the `permission-*`, `BUNDLE_FROZEN` and Gemfile-source examples, which go green in 7.3. Verify that `actionlint` reports nothing.
- [ ] 6.2 Document the GitHub App, variable, secret and Pages settings from the design's Migration Plan, and the local commands, in `README.md`. Verify that each documented command runs as written.

## 7. Security hardening

- [ ] 7.1 (S1, S7) Add `GreeterDocs::LogSafe`, used by every line `bin/build-docs` and `bin/fetch-sources` print. It replaces control characters and newlines with `\uFFFD`, prefixes any line starting with `::` so it is never a workflow command, truncates values to 200 characters, and echoes a sourced value only when it matches the slug or path pattern (otherwise `(invalid value)`). Verify that `spec/support/log_safety_spec.rb` is green.
- [ ] 7.2 (S2) Change `bin/fetch-sources` to query `gh run list` with `--event push` and with `--event schedule` (`--json databaseId,createdAt`) and download the newer run. Verify that the fetch spec's event-selection and fork-PR examples are green.
- [ ] 7.3 (S3, S9) Add `permission-contents: read` and `permission-actions: read` to the token step, and `BUNDLE_FROZEN: "true"` to the job `env`, in `docs.yml`. Update the README setup to say Actions: read. Verify that the workflow spec's token, frozen-bundle and Gemfile-source examples are green.
- [ ] 7.4 (S4, API7) Add input limits:
  - a 5 MiB cap per trace, ledger and `openapi.yaml` (the ledger fetcher stops reading past the cap);
  - `YAML.safe_load(..., aliases: false, permitted_classes: [])` for the tag map and `openapi.yaml`;
  - a `$ref` resolver with a visited set and a depth limit of 32, and no fetch of a non-local `$ref`;
  - a `Net::HTTP` `read_timeout` and `open_timeout` of 10 s.

  Each limit raises a `SourceError` naming the file or environment. Verify that the limits examples are green.
- [ ] 7.5 (S5, S10) Add the URL rules:
  - ADR link targets are parsed with `URI` after HTML-entity decoding and whitespace stripping, and kept only for `http`, `https` or a scheme-less relative path; anything else renders as text.
  - Every `href` or `id` built from a ledger `run_id`, channel or key passes the digits or slug pattern, or is omitted.
  - The API page shows the greeter-http commit and `info.version`, labelled "main".

  Verify that the publisher's URL and API-version examples are green.
- [ ] 7.6 (S6) Add a `<meta http-equiv="Content-Security-Policy">` to the layout: `default-src 'none'; script-src 'self' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'none'; base-uri 'none'; form-action 'none'`. Move the Mermaid initialisation to `_site/assets/architecture.js`, so that no page has an inline script. Verify that the CSP examples are green and that `architecture.html` still renders both diagrams in a browser with no CSP console errors.

## 8. Verify and docs

- [ ] 8.1 Run `bin/fetch-sources` with a local `GH_TOKEN`, then `bundle exec rspec` with the formatter, then `bin/build-docs`. Confirm that the build fails naming greeter-http `version-headers` `deployed-stage-exposes-version-headers` `openspec/specs/version-headers/spec.md`, as expected per design Risks, and names nothing else. Then run `bin/build-docs` against fixture sources with full coverage, and confirm that it exits 0 and writes `_site/`.
- [ ] 8.2 Run `lychee --offline --no-progress _site` and confirm that it exits 0. Add a link to a missing page, confirm that lychee fails naming the page and the link, then revert.
- [ ] 8.3 Run `bundle exec rspec`, `bundle exec rubocop` and `openspec validate add-live-docs --strict`, and confirm that all are clean.
- [ ] 8.4 (S8) After a real `bin/fetch-sources` with `GH_TOKEN`, confirm that `grep -r "$GH_TOKEN" tmp/repos/*/.git/config` finds nothing, and that `_site/` contains no file from `tmp/` (`find _site -path '*tmp*'` is empty).
