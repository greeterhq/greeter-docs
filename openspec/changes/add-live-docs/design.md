# Design

## Context

greeter-docs has only a scaffold: a Gemfile with rspec and rubocop,
`bin/guard-test-edits`, empty `lib/greeter_docs/`, `docs/adr/`,
`docs/diagrams/`, `spec/` and `templates/`, and no main specs. The producers
already exist (see proposal.md, Why):

- Each producer's `ci.yml` uploads a merged `repo-trace` artifact on `main`
  (retention 90 days) and sends `docs-refresh`.
- greeter-acceptance's `record.yml` publishes `ledger.json` to `ledger-prod` and
  `ledger-stage`. Its `openspec/requirement-tags.yml` maps the five `greeting`
  heading slugs to ledger keys, for example
  `a-channel-greets-a-valid-guest: greeting-happy`.
- Capability paths can be nested. greeter-cli has
  `openspec/specs/tooling/live-docs-traceability/spec.md`.
- greeter-cli's `spec/support/repo_trace_formatter.rb` and
  `spec/support/repo_trace/document.rb` (commit 7b43842) write
  `greeterhq.repo-trace.v1` to the path in `REPO_TRACE_PATH`. greeter-http
  already copies them with `REPO` changed.

Specs: `specs/coverage-gate`, `specs/docs-sources`, `specs/docs-site`,
`specs/docs-deployment`.

## Goals / Non-Goals

**Goals:**
- The domain is testable with in-memory models only. All I/O sits behind ports.
- Every failure message names what the operator must fix: repo, capability,
  requirement and file, or the file or environment and the reason.
- Tests never touch the network. Fetchers and command runners are injected.

**Non-Goals:**
- Incremental builds or caching between runs. Every run rebuilds from scratch.
- A general Markdown or OpenAPI renderer. The renderers cover the constructs
  the current files use: for Markdown, headings, paragraphs, lists, code and
  links; for OpenAPI, operations, parameters, request bodies, responses,
  headers and local `$ref`s.
- Copying greeter-cli's trace check (`repo_trace/check.rb`). greeter-docs'
  coverage is enforced by its own `CoverageRule` over its own trace.

## Decisions

### D1. Specs come from parsing headings, not the OpenSpec CLI
`GitSpecSource` parses the `spec.md` headings itself with the shared slug rule,
the same rule every producer's trace check uses, so slugs match by
construction. The build needs no Node or OpenSpec install in CI.

The alternative was `openspec show --json` in each clone. It would add a Node
toolchain, and the docs would depend on the CLI's own heading normalisation
agreeing with the trace checks. This change also updates
`openspec/config.yaml`, `.kiro/hooks/tdd-guards.json` and the workspace
testing-discipline steering so that they describe this design.

### D2. Layout
```
lib/greeter_docs/domain/   slug.rb repo.rb requirement.rb scenario.rb result.rb
                           ledger_view.rb api_description.rb adr.rb diagram.rb
                           docs_model.rb coverage_rule.rb violation.rb
lib/greeter_docs/ports/    spec_source.rb trace_source.rb ledger_source.rb api_source.rb
                           adr_source.rb diagram_source.rb contract_source.rb
                           slo_source.rb publisher.rb
lib/greeter_docs/adapters/ git_spec_source.rb artifact_trace_source.rb
                           raw_ledger_source.rb file_api_source.rb file_adr_source.rb
                           file_diagram_source.rb null_contract_source.rb
                           null_slo_source.rb erb_html_publisher.rb markdown.rb
lib/greeter_docs/build.rb  use case: gather sources -> DocsModel -> CoverageRule -> publish
spec/support/repo_trace_formatter.rb, spec/support/repo_trace/document.rb
                           copied from greeter-cli 7b43842, REPO = "greeter-docs"
bin/build-docs  bin/fetch-sources
```
Ports are Ruby modules that document the method each adapter implements (for
example `SpecSource#repos -> [Repo]`). Tests use in-memory doubles of them.
Every file starts with `# frozen_string_literal: true`.

### D3. Coverage semantics (domain)
`CoverageRule#violations(model)` returns `Violation(repo, capability,
requirement_slug, spec_path)` sorted by repo, capability and requirement:
- Not tag-mapped: covered if `model.results(repo)` has any result with that
  requirement slug and `status == "passed"`. Matching is by requirement slug
  within the repo, because traces carry no capability.
- Tag-mapped (`repo.requirement_tags[slug]` present): covered if the prod
  `LedgerView` has `requirements[key]` with any channel `"passed"`. If prod is
  `not_recorded`, the requirement is reported as *pending*, not as a violation.
  Stage is never consulted.

`Build` raises `CoverageFailed(violations)` before calling the publisher, so a
failing build writes no `_site/`. `bin/build-docs` prints one line per
violation and exits 1, for example:

```
greeter-http version-headers deployed-stage-exposes-version-headers openspec/specs/version-headers/spec.md
```

### D4. Spec parsing
`GitSpecSource` globs `openspec/specs/**/spec.md` in `tmp/repos/<repo>` for the
four producers, and in the workspace root for greeter-docs. Reading the
workspace reads exactly the commit under build, and needs neither a clone nor
a token. The parser matches the lines `^### Requirement: (.+)$` and
`^#### Scenario: (.+)$` outside fenced code blocks. The requirement-tag map is
read as plain YAML (`YAML.safe_load`, string keys and values only).

### D5. Validation and errors
Each adapter raises `GreeterDocs::SourceError` with a message naming the file or
environment and the field. `bin/build-docs` collects the source errors and
coverage violations, prints them, and exits 1. Trace validation checks only
what the specs require (`schema`, `repo` matching the directory, valid JSON),
plus that the `results` entries are objects with string `requirement`,
`scenario` and `status`. Anything more would duplicate the producers' merge
checks.

### D6. Ledger fetching
`RawLedgerSource.new(fetcher:)`. The fetcher is a callable `(url) ->
[status, body]`. Production uses `Net::HTTP` with a 10 s timeout and no
redirects followed. Tests pass a lambda. A 404 gives
`LedgerView.not_recorded(env)`. Any other non-200 status, or a network error,
raises `SourceError` naming the environment. The raw URLs are public, so no
token is sent.

### D7. Publishing and escaping
`ErbHtmlPublisher` renders `templates/*.erb` with
`ERB.new(src, trim_mode: "-")` through one `h()` helper (`CGI.escapeHTML`). It
has no `raw` helper.
- **ADRs**: Markdown is converted by `adapters/markdown.rb`, a small renderer
  that escapes every text run before wrapping it in tags and keeps only
  `http`, `https` and relative link targets.
- **Run links**: built only when `run_id` matches `\A\d+\z`.
- **Diagrams**: the Mermaid text is escaped inside `<pre class="mermaid">`.
  Mermaid reads `textContent`, so the escaped entities still render. Mermaid is
  loaded once from
  `https://cdn.jsdelivr.net/npm/mermaid@11.17.2/dist/mermaid.esm.min.mjs`
  (11.17.2 is the version jsdelivr resolved for `mermaid@11` on 2026-11-21),
  with `securityLevel: "strict"`.
- **API**: `api.erb` walks `paths` and, for each operation, renders its
  parameters, request body, responses and response headers. It resolves local
  `#/components/...` `$ref`s (the fixture has 28) and shows a non-local `$ref`
  as escaped text. The publisher writes the original `openapi.yaml` bytes to
  `_site/openapi.yaml`, and `api.html` links to it.
- **Links**: relative everywhere, so the site works under `/greeter-docs/`.

Alternatives: kramdown or commonmarker for Markdown, which add a gem and pass
raw HTML through by default; Redoc for the API, which adds a script and
conflicts with "no client-side script except Mermaid".

### D8. greeter-docs' own trace
Copy greeter-cli's `RepoTraceFormatter` and `RepoTrace::Document` (commit
7b43842) into `spec/support/` and `spec/support/repo_trace/`, changing only
`REPO = 'greeter-docs'`. `docs.yml` runs
`bundle exec rspec --format progress --format RepoTraceFormatter` with
`REPO_TRACE_PATH: tmp/traces/greeter-docs/repo-trace.json` in `env`, in the
`build` job before `bin/build-docs`. greeter-docs therefore needs no artifact
upload or download, and the same `CoverageRule` applies to it.
`bin/fetch-sources` never touches `tmp/traces/greeter-docs`.

The tagging rules follow the producers:
- Each example carries exactly one `requirement:` and one `scenario:` slug.
- Each greeter-docs scenario has exactly one such example. A suite-level spec
  checks this against the trace.
- Shared examples are included with `it_behaves_like` inside a tagged
  `context`.
- Tag-like test data uses string keys (`{ 'requirement' => ... }`) or lives in
  `spec/fixtures/`.

### D9. Fetch script
`bin/fetch-sources` uses an injectable runner (`Open3.capture3` with argv
arrays, never a shell string). For each of the four repos it runs
`gh repo clone greeterhq/<repo> tmp/repos/<repo> -- --depth 1 --branch main`.
`gh repo clone` uses `GH_TOKEN`, so the private repos clone without putting the
token in a URL. It then runs the `gh run list` and `gh run download` commands
given in `specs/docs-deployment`. It first removes `tmp/repos/<repo>` and
`tmp/traces/<repo>` for those four repos, so stale files never leak into a
build. Error messages print the argv and stderr with any `GH_TOKEN` value
replaced by `***`.

### D10. Workflow
`docs.yml` has top-level `permissions: {}`. `build` is `contents: read`. `deploy`
is `pages: write, id-token: write` with
`if: github.event_name != 'pull_request'`. The `build` steps:

1. `actions/checkout` with `persist-credentials: false`.
2. `ruby/setup-ruby` with `ruby-version: "3.3"` and `bundler-cache: true`,
   commented as in greeter-acceptance's `ci.yml`:
   > Ruby: CI tracks the latest 3.3.x patch. Newer runner images only build the
   > latest patch of each series, so an exact patch pin would break whenever a
   > new patch ships. The repo's .ruby-version (3.3.13) remains the local
   > development pin.
3. The app token step.
4. `bin/fetch-sources` (`env: GH_TOKEN`).
5. **Install lychee.** The link-check examples in the RSpec suite run `lychee`,
   so it must be on `PATH` before step 7. The step pins lychee `lychee-v0.24.2`
   (released 2026-05-01) for x86_64 Linux. Its sha256,
   `1f4e0ef7f6554a6ed33dd7ac144fb2e1bbed98598e7af973042fc5cd43951c9a`, is taken
   from the release's published
   `lychee-x86_64-unknown-linux-gnu.tar.gz.sha256`, and on 2026-11-21 it matched
   the downloaded tarball. Both values are in the step's `env`, and `run:` has
   no `${{`:
   ```yaml
   - name: Install lychee
     env:
       LYCHEE_VERSION: lychee-v0.24.2
       LYCHEE_SHA256: 1f4e0ef7f6554a6ed33dd7ac144fb2e1bbed98598e7af973042fc5cd43951c9a
     run: |
       curl -fsSLo "$RUNNER_TEMP/lychee.tar.gz" \
         "https://github.com/lycheeverse/lychee/releases/download/$LYCHEE_VERSION/lychee-x86_64-unknown-linux-gnu.tar.gz"
       echo "$LYCHEE_SHA256  $RUNNER_TEMP/lychee.tar.gz" | sha256sum -c -
       tar -xzf "$RUNNER_TEMP/lychee.tar.gz" -C "$RUNNER_TEMP"
       echo "$RUNNER_TEMP/lychee-x86_64-unknown-linux-gnu" >> "$GITHUB_PATH"
   ```
6. **Lint**: `bundle exec rubocop`.
7. `bundle exec rspec` with the trace formatter (D8).
8. `bin/build-docs`.
9. **Link check**: `lychee --offline --no-progress _site`, using the binary from
   step 5.
10. `actions/upload-pages-artifact` (`path: _site`).

`actions/configure-pages` is not used. It reads the Pages settings through the
API, which the `contents: read` build job cannot do, and the site uses none of
its outputs: every link is relative, so the base path needs no configuration.

Actions are pinned to full commit SHAs with a version comment. lychee is
installed exactly once, by step 5, and no `lycheeverse/` action is used. The
RSpec link examples and the site check run the same pinned, verified binary.

### D11. Names fixed by the red tests
The specs written in tasks 1.3–1.9 fix these names:
- `Domain::Trace`: a repo trace's `repo`, `sha`, `run_id`, `recorded_at` and
  `results`.
- `CoverageRule#not_yet_recorded(model)`: the tag-mapped requirements whose
  prod ledger is not recorded.
- `CoverageRule#summary(model)`: the counts `covered`, `uncovered` and
  `not_yet_recorded`.
- `Build#call`: returns a result with `exit_code` and `lines`.
- `GreeterDocs::LogSafe`: `.line` and `.value`, per S1 and S7.
- `GreeterDocs::FetchSources`: built with `runner:`, `root:`, `env:`, `out:`
  and `err:`.
- `RawLedgerSource.default_fetcher`: the `Net::HTTP` fetcher. Only
  `bin/build-docs` fetches with `default_fetcher`. Specs may inspect its
  configuration (timeouts, redirects) but never fetch with it. Every spec that
  reads a ledger injects a fake fetcher. Building it opens no connection: it
  only holds its settings, and connects on `call(url)`.

### Fixtures (captured from real output)
The Red tests tasks copy these into `spec/fixtures/`. The tool for all of them
is gh 2.104.0, and they were downloaded on 2026-11-21T11:05:27Z.

| fixture | source | id |
|---|---|---|
| `traces/greeter-core/repo-trace.json` | `gh run download -R greeterhq/greeter-core 44297674561 -n repo-trace` | run 44297674561, sha 2ef6510, 52 results, sha256 0b2e6afd… |
| `traces/greeter-cli/repo-trace.json` | `gh run download -R greeterhq/greeter-cli 44725327875 -n repo-trace` | run 44725327875, sha 88a7d56, 93 results (88 rspec, 5 cucumber), sha256 529fe948… |
| `traces/greeter-http/repo-trace.json` | `gh run download -R greeterhq/greeter-http 44622828436 -n repo-trace` | run 44622828436, sha 5b818a2, 181 results (1 skipped), sha256 53dce46e… |
| `traces/greeter-acceptance/repo-trace.json` | `gh run download -R greeterhq/greeter-acceptance 44894113504 -n repo-trace` | run 44894113504, sha 7a3272c, 151 results (2 skipped), sha256 afb5a2dc… |
| `ledgers/prod.json` | `git show origin/ledger-prod:ledger.json` in `../greeter-acceptance` | commit 5bbea1ad31a5bb9b1bbe73ec466d16c55b2262aa (2026-11-21T08:53:06Z), sha256 4a2192e0… |
| `repos/<repo>/openspec/**` | sibling checkouts on `main` | core 2ef6510, cli 88a7d56, http 5b818a2, acceptance 7a3272c |
| `repos/greeter-http/openapi.yaml`, `docs/adr/*.md` | `git show 5b818a2:<path>` in `../greeter-http` | commit 5b818a2fa3f69d9a8bcc9c44f634c2ee2984670c |

Excerpt of the greeter-http trace (run 44622828436):
```json
{"schema": "greeterhq.repo-trace.v1", "repo": "greeter-http",
 "sha": "5b818a2fa3f69d9a8bcc9c44f634c2ee2984670c",
 "recorded_at": "2026-11-19T21:51:18Z", "run_id": "44622828436",
 "results": [
  {"requirement": "greet-a-guest-and-return-a-running-count",
   "scenario": "first-greeting-for-a-new-guest", "status": "passed",
   "source": "cucumber", "location": "features/greeting_counter.feature:12"},
  {"requirement": "deployed-stage-exposes-version-headers",
   "scenario": "smoke-check-on-a-deployed-stage", "status": "skipped",
   "source": "cucumber", "location": "features/version_headers.feature:7"}]}
```
`run_id` is a string of digits in CI and `null` in local runs.

Excerpt of the prod ledger (commit 5bbea1a):
```json
{"schema": "greeterhq.ledger.v2", "environment": "prod",
 "suite": {"version": "v0.3.0"},
 "channels": {"cli": {"state": "current", "reasons": [], "channel_version": "v0.1.12",
   "core_version": "0.1.3", "suite_version": "v0.3.0", "verification": "verified",
   "recorded_at": "2026-11-21T08:52:38Z", "run_id": "44886860348"}, "http": {"…": "…"}},
 "requirements": {"greeting-count": {"cli": "not_applicable", "http": "passed"},
   "greeting-happy": {"cli": "passed", "http": "passed"}, "…": "…"}}
```
The hand-edited variants (wrong schema, wrong repo, `<script>` text, all
`not_applicable`) are derived from these files in spec setup, not stored as
separate captures.

## Risks / Trade-offs

- [Against the real traces above, greeter-http's
  `deployed-stage-exposes-version-headers` has only a `skipped` result, so the
  first deploy fails] → This is the gate working as intended. greeter-http must
  record a passing result for it. The other three producers checked clean in a
  dry run on 2026-11-21.
- [Pull requests share concurrency group `pages`. GitHub keeps only one pending
  run per group, so a newer pending PR run replaces a pending `main` or
  `docs-refresh` run] → The skipped refresh is picked up by the next push,
  dispatch or daily run, because every run rebuilds everything. If that proves
  too slow, a follow-up could give pull requests their own group.
- [Pull requests from forks get no secrets, so the token step fails] → All
  contributors push branches in the org. Fork PRs fail visibly rather than
  silently.
- [The `repo-trace` artifacts expire after 90 days, so the fixtures cannot be
  re-downloaded after about 2027-02-17] → The fixtures are committed. A refresh
  is a separate change (per config apply guidance).
- [Matching traces by requirement slug alone treats two same-named
  requirements in different capabilities of one repo as one] → The producers'
  trace checks already require slugs to be unique within a capability, and no
  current repo repeats one across capabilities. This is accepted for now.
- [A hand-rolled Markdown renderer may mis-render unusual ADR syntax] → The ADRs
  are authored in this org. Escaping is applied before formatting, so a
  mis-render cannot become an injection.
- [The copied formatter drifts from greeter-cli's] → The copy adds a header
  comment naming greeter-cli commit 7b43842 as its source, so a later diff
  against greeter-cli is easy.
- [The jsdelivr CDN is unavailable] → Only the architecture diagrams degrade,
  to their source text. No other page loads an external script.

## Migration Plan

1. Create the GitHub App with repository permissions Contents: read and
   Actions: read (needed for `gh run list` and `gh run download`), and nothing
   else, installed on the four repos only. Set
   `DOCS_READER_APP_CLIENT_ID` (variable) and `DOCS_READER_APP_PRIVATE_KEY`
   (secret).
2. Set Pages to source "GitHub Actions".
3. Merge. Rollback is reverting the merge. A previously deployed site stays
   live until the next successful deploy.

## Security considerations

Review of 2026-11-21 against the security-review checklist: OWASP API Top 10
(2023), input reflection, error leakage, log injection, IAM scope, and
dependency confusion on greeter-core. The site is static and public, and all
five repos are public (checked with `gh repo view`), so publishing crosses no
confidentiality boundary. The trust boundary is the producers' data: spec text,
traces, the ledger, `openapi.yaml` and ADRs. Anyone who can merge to a
producer's `main` controls that data. Fork pull requests can also start
producer CI runs.

| # | Area | Finding | Severity | Resolution |
|---|---|---|---|---|
| S1 | Log injection | `bin/build-docs` and `bin/fetch-sources` print sourced values (a trace's `repo`, file paths, gh stderr) to the Actions log. A line starting with `::` is run as a workflow command (`::add-mask::`, `::stop-commands::`, `::error file=...::`), and embedded newlines forge extra lines. | Medium | Task 7.1 |
| S2 | API10 unsafe consumption | `gh run list --branch main` matches by head branch name. A fork PR from a branch named `main` that passes CI becomes the "latest successful main run". The producers upload no `repo-trace` on `pull_request`, so the download fails and the docs build breaks: anyone can deny service. | Medium | Spec changed (`--event push` and `--event schedule`, take the newer); task 7.2 |
| S3 | IAM scope | `create-github-app-token` mints a token with every permission the App installation has unless `permission-*` inputs are set. The Migration Plan granted only Contents: read, so artifact download would also have failed without Actions: read. | Medium | Spec changed (`permission-contents: read`, `permission-actions: read`); Migration Plan updated; task 7.3 |
| S4 | API4 resource consumption | Inputs are unbounded: trace, ledger and `openapi.yaml` sizes; YAML alias expansion in `requirement-tags.yml` and `openapi.yaml`; a `$ref` cycle recursing forever; a slow raw-ledger response trickling bytes. | Medium | Task 7.4 |
| S5 | Input reflection | HTML escaping covers text and quoted attributes, but URL attributes need more. An ADR link target such as `JaVaScript:`, `" javascript:"` or `java&#x09;script:` passes a naive prefix check. Ledger `run_id`, channel names and ledger keys reach `href` and `id` without the digits or slug check that trace `run_id` gets. | Low | Task 7.5 |
| S6 | Security misconfiguration | Pages set no Content-Security-Policy, so any future escaping slip runs script. Mermaid is pinned to 11.17.2 on jsdelivr, but its ES module imports chunks that cannot carry SRI, so a CDN compromise means script on `architecture.html`. | Low | Task 7.6 (CSP). CDN risk accepted for a static, credential-free site. |
| S7 | Error leakage | `SourceError` messages echo values read from sources (for example the wrong `repo`). Producer traces exclude guest names by contract, but greeter-docs should not depend on that contract when it prints errors. | Low | Task 7.1 (echo a value only when it matches the slug pattern, otherwise `(invalid value)`) |
| S8 | Credential handling | The app token is in `env` only for the fetch step and is revoked at job end. Still, `gh repo clone` must not leave the token in `tmp/repos/*/.git/config`, and `_site` must never include `tmp/`. | Low | Task 8.4 (verify) |
| S9 | Dependency confusion on greeter-core | greeter-docs does not depend on greeter-core, and the Gemfile has a single `https://rubygems.org` source with no `greeter-*` gem, so there is nothing to confuse. CI should still install from the lockfile only. | Info | Task 7.3 (`BUNDLE_FROZEN: "true"`; workflow spec asserts a single source and no `greeter-*` gem) |
| S10 | API9 inventory | `api.html` shows `openapi.yaml` from greeter-http `main`, which can differ from the deployed version in the ledger. | Info | Task 7.5 (show the greeter-http commit and `info.version`, labelled "main") |

The following checklist items are not applicable:
- API1 (object-level authorization), API3 (property-level authorization) and
  API5 (function-level authorization): the site has no API, no objects and no
  authentication.
- API2 (authentication): the only credential is the app token, covered by S3
  and S8.
- API6 (sensitive business flows): there are none.
- API7 (SSRF): the ledger URLs are constants with two fixed environments, no
  redirects are followed, `client_payload` is never read, and an external
  `$ref` is shown as text and never fetched. Task 7.4 adds a test for the last
  point.
- On `pull_request` from a branch in this repo, PR code runs with the app token
  minted in the same job. Anyone who can push a branch can already edit
  `docs.yml`, so this adds no new access. Fork PRs get no secrets, so their
  token step fails.
