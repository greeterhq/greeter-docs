# greeter-docs

The greeterHQ live documentation site, published to
https://greeterhq.github.io/greeter-docs/.

It shows every requirement on `main` in greeter-core, greeter-cli, greeter-http,
greeter-acceptance and greeter-docs, the scenarios that verify them, the
latest CI result for each, and what each deployed channel achieved in the
greeter-acceptance ledgers. The build fails, naming the repo, capability,
requirement and spec file, when any requirement on `main` has no passing
scenario.

## How it works

- `bin/fetch-sources` shallow-clones the four producer repos at `main` into
  `tmp/repos/<repo>` and downloads each one's latest successful `main` `ci.yml`
  `repo-trace` artifact (push or schedule runs only) into `tmp/traces/<repo>`.
- The RSpec suite, run with `RepoTraceFormatter`, writes greeter-docs' own trace
  to `tmp/traces/greeter-docs/repo-trace.json`.
- `bin/build-docs` reads those files, the `ledger-prod` and `ledger-stage`
  ledgers, greeter-http's `openapi.yaml` and ADRs, and this repo's `docs/`, then
  writes `_site/`. It writes nothing when a source is invalid or a requirement
  is uncovered.

The design is in `openspec/changes/add-live-docs/design.md` (until archived)
and the decisions in `docs/adr/`.

## Run it locally

Ruby 3.3.13 (`.ruby-version`), with `gh` signed in to an account that can read
the producer repos and their Actions artifacts.

```sh
bundle install
bin/fetch-sources
REPO_TRACE_PATH=tmp/traces/greeter-docs/repo-trace.json bundle exec rspec --format progress --format RepoTraceFormatter
bin/build-docs
lychee --offline --no-progress _site
```

Open `_site/index.html` in a browser. `bundle exec rubocop` lints the code.

## Repository setup for the docs workflow

`.github/workflows/docs.yml` needs:

1. A GitHub App installed on greeter-core, greeter-cli, greeter-http and
   greeter-acceptance only, with repository permissions **Contents: read** and
   **Actions: read** and nothing else. The workflow mints its token with exactly
   those two permissions.
2. In this repo, the variable `DOCS_READER_APP_CLIENT_ID` (the App's client ID)
   and the secret `DOCS_READER_APP_PRIVATE_KEY` (its private key).
3. GitHub Pages enabled with source **GitHub Actions**, and the `github-pages`
   environment allowed to deploy from `main`.

The workflow runs on push to `main`, on `docs-refresh` dispatches from the
producer repos, daily at 05:23 UTC, on manual runs and on pull requests. Pull
requests build and check the site but never deploy it.
