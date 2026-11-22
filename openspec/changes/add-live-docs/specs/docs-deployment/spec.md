# Spec Delta

## Purpose

Defines when and how the live documentation site is fetched, built, checked
and deployed to GitHub Pages, how greeter-docs records its own trace, and the
least-privilege credentials the docs workflow uses.

## ADDED Requirements

### Requirement: The docs workflow runs on main, refresh, schedule, request and pull request
`.github/workflows/docs.yml` SHALL run on push to `main`, on
`repository_dispatch` of type `docs-refresh`, daily on schedule `23 5 * * *`,
on `workflow_dispatch`, and on `pull_request`. Runs SHALL share concurrency
group `pages` with `cancel-in-progress: false`.

#### Scenario: Triggers and concurrency are declared
- **WHEN** `.github/workflows/docs.yml` is parsed
- **THEN** `on` has `push.branches: [main]`, `repository_dispatch.types: [docs-refresh]`, `schedule` with cron `23 5 * * *`, `workflow_dispatch` and `pull_request`, and `concurrency` is group `pages` with `cancel-in-progress: false`

### Requirement: The dispatch payload never steers the build
No step of `docs.yml` SHALL read `github.event.client_payload`. Every run SHALL
fetch and build the same sources from `main` whatever the payload says.

#### Scenario: No step reads the client payload
- **WHEN** `.github/workflows/docs.yml` is read as text
- **THEN** it does not contain `client_payload`

### Requirement: The build job fetches with a read-only app token
The `build` job SHALL have `permissions: {contents: read}`. It SHALL mint a
token with `actions/create-github-app-token@v3`, with client-id
`vars.DOCS_READER_APP_CLIENT_ID`, private-key
`secrets.DOCS_READER_APP_PRIVATE_KEY`, owner `greeterhq` and repositories
`greeter-core,greeter-cli,greeter-http,greeter-acceptance`, limited to
`permission-contents: read` and `permission-actions: read`. It SHALL pass the
token to `bin/fetch-sources` only as `GH_TOKEN` in `env`.

#### Scenario: Build job permissions and token are least-privilege
- **WHEN** `.github/workflows/docs.yml` is parsed
- **THEN** `build` has `permissions` exactly `{contents: read}`, the token step uses `actions/create-github-app-token@v3` with those inputs and no other `permission-*` input, the fetch step sets `GH_TOKEN` from the token step's output in `env`, and no `run:` step contains a `${{` expression

### Requirement: The build job tests, builds and link-checks before uploading
The `build` job SHALL set up Ruby with `ruby-version: "3.3"` (the latest 3.3
patch), then run, in this order: `bin/fetch-sources`, `bundle exec rspec` with
the repo-trace formatter, `bin/build-docs`, lychee on `_site` with `--offline`,
and `actions/upload-pages-artifact` for `_site`. A failure in any step SHALL
stop the job before the upload.

#### Scenario: Build steps run in order
- **WHEN** `.github/workflows/docs.yml` is parsed
- **THEN** `ruby/setup-ruby` has `ruby-version` `"3.3"`, and the `build` steps run `bin/fetch-sources`, `bundle exec rspec` with `--format RepoTraceFormatter` and `REPO_TRACE_PATH=tmp/traces/greeter-docs/repo-trace.json` in `env`, `bin/build-docs`, lychee with `--offline` on `_site`, and `actions/upload-pages-artifact` with path `_site`, in that order, with no `continue-on-error` and no `if:` on any of them

### Requirement: greeter-docs records its own trace
greeter-docs SHALL use the RSpec formatter and trace document copied from
greeter-cli, with `repo` `greeter-docs`. Run in the build job, it SHALL write
`tmp/traces/greeter-docs/repo-trace.json` (schema `greeterhq.repo-trace.v1`)
with one result per example tagged with both `requirement` and `scenario`. Each
result SHALL hold only the requirement, scenario, status, source and location.

#### Scenario: The suite writes a v1 trace for greeter-docs
- **WHEN** a fixture suite with one passing and one skipped tagged example runs with the formatter and `REPO_TRACE_PATH` set
- **THEN** the file has `schema` `greeterhq.repo-trace.v1`, `repo` `greeter-docs`, `sha`, `run_id` (`GITHUB_RUN_ID` or `null`), `recorded_at`, and two results with statuses `passed` and `skipped`, each with exactly the keys `requirement`, `scenario`, `status`, `source` and `location`

#### Scenario: Every greeter-docs scenario has exactly one tagged example
- **WHEN** the full suite runs with the formatter
- **THEN** for every `#### Scenario:` heading in greeter-docs' specs, the trace has exactly one result with that requirement slug and scenario slug, and no result names a slug that is not a heading

### Requirement: The deploy job publishes to GitHub Pages except for pull requests
The `deploy` job SHALL need `build`, run only when
`github.event_name != 'pull_request'`, use environment `github-pages` with its
URL from the deploy step, have `permissions` exactly `pages: write` and
`id-token: write`, and run `actions/deploy-pages`.

#### Scenario: Deploy job is declared
- **WHEN** `.github/workflows/docs.yml` is parsed
- **THEN** `deploy` has `needs: build`, `if: github.event_name != 'pull_request'`, `environment.name: github-pages`, `permissions` exactly `{pages: write, id-token: write}`, and a step using `actions/deploy-pages`

#### Scenario: A pull request with an uncovered requirement fails before merge
- **WHEN** the workflow is parsed and a pull request run's `bin/build-docs` exits non-zero
- **THEN** the `build` job fails and `deploy` does not run, because it needs `build` and is skipped for `pull_request`

### Requirement: Sources are fetched as shallow main clones and latest main traces
For each of greeter-core, greeter-cli, greeter-http and greeter-acceptance,
`bin/fetch-sources` SHALL clone `main` with depth 1 into `tmp/repos/<repo>`. It
SHALL download into `tmp/traces/<repo>/` the `repo-trace` artifact of that
repo's latest successful `main` run of `ci.yml` triggered by `push` or
`schedule`. A repo with no such run gets no trace. It SHALL not fetch
greeter-docs or write outside those directories.

#### Scenario: Fetch issues the expected commands
- **WHEN** `bin/fetch-sources` runs with a stubbed command runner where every repo has a successful run
- **THEN** it runs, for each repo, `gh repo clone greeterhq/<repo> tmp/repos/<repo> -- --depth 1 --branch main`, then `gh run list -R greeterhq/<repo> --workflow ci.yml --branch main --status success --event <event> --limit 1 --json databaseId,createdAt` for `push` and for `schedule`, then `gh run download <id> -R greeterhq/<repo> -n repo-trace -D tmp/traces/<repo>` for the more recent of the two, and runs no command naming greeter-docs

#### Scenario: A fork pull request from a branch named main is not used
- **WHEN** the latest successful `ci.yml` run with head branch `main` came from a `pull_request` event and the latest `push` run is older
- **THEN** the fetch downloads the `push` run's artifact and never the `pull_request` run's

#### Scenario: A repo with no successful run gets no trace
- **WHEN** the stubbed `gh run list` returns `[]` for greeter-cli
- **THEN** no `gh run download` runs for greeter-cli and the fetch exits zero

#### Scenario: The token is not echoed
- **WHEN** `bin/fetch-sources` runs with `GH_TOKEN` set and a command fails
- **THEN** neither its output nor its error message contains the token value

### Requirement: Prod smoke traces come from the latest successful smoke-prod run
After the four CI traces, `bin/fetch-sources` SHALL find greeter-http's latest
successful `smoke-prod.yml` run on `main`, of any event. If that run has a
non-expired `repo-trace-smoke-prod` artifact, it SHALL download it into
`tmp/traces/greeter-http/prod-smoke/`. Otherwise it SHALL download nothing,
say so, and carry on.

#### Scenario: The prod smoke trace is fetched from smoke-prod.yml
- **WHEN** `bin/fetch-sources` runs with a stubbed runner where greeter-http's latest successful `smoke-prod.yml` run has a non-expired `repo-trace-smoke-prod` artifact
- **THEN** after the four repos' CI commands it runs `gh run list -R greeterhq/greeter-http --workflow smoke-prod.yml --branch main --status success --limit 1 --json databaseId,createdAt` with no `--event`, `gh api repos/greeterhq/greeter-http/actions/runs/<id>/artifacts`, and `gh run download <id> -R greeterhq/greeter-http -n repo-trace-smoke-prod -D tmp/traces/greeter-http/prod-smoke`

#### Scenario: A smoke-prod run without a live artifact downloads nothing
- **WHEN** the latest successful `smoke-prod.yml` run lists no `repo-trace-smoke-prod` artifact, or lists it with `expired` true
- **THEN** no `gh run download` runs for it, the output says there is no prod smoke trace, and the fetch exits zero

#### Scenario: No successful smoke-prod run downloads nothing
- **WHEN** the stubbed `gh run list` for `smoke-prod.yml` returns `[]`
- **THEN** no artifact lookup or download runs for it and the fetch exits zero
