# frozen_string_literal: true

require 'open3'

RSpec.describe 'GreeterDocs::Adapters::ErbHtmlPublisher' do
  let(:mermaid_url) { %r{\Ahttps://cdn\.jsdelivr\.net/npm/mermaid@\d+\.\d+\.\d+/dist/mermaid\.esm\.min\.mjs\z} }
  let(:csp) do
    "default-src 'none'; script-src 'self' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline'; " \
      "img-src 'self' data:; font-src 'self'; connect-src 'none'; base-uri 'none'; form-action 'none'"
  end
  let(:site_pages) do
    %w[index.html traceability.html api.html architecture.html contracts.html slo.html adr/index.html]
  end

  around do |example|
    Dir.mktmpdir('greeter-docs-site') do |site|
      @site = site
      example.run
    end
  end

  attr_reader :site

  def publish(docs_model)
    GreeterDocs::Adapters::ErbHtmlPublisher.new(templates_dir: File.join(SpecHelpers::ROOT, 'templates'),
                                                output_dir: site).publish(docs_model)
  end

  def page(name)
    File.read(File.join(site, name))
  end

  def all_pages
    Dir[File.join(site, '**', '*.html')].to_h { |path| [path.delete_prefix("#{site}/"), File.read(path)] }
  end

  # The model built from the captured fixtures through the real adapters, with
  # greeter-docs' ADRs and diagrams read from this repo.
  def fixture_model
    with_fetched_workspace do |root|
      adapters = GreeterDocs::Adapters
      repos = adapters::GitSpecSource.new(clones_root: File.join(root, 'tmp', 'repos'), workspace_root: root,
                                          producers: SpecHelpers::PRODUCERS).repos
      traces = adapters::ArtifactTraceSource.new(workspace_root: root)
      ledgers = adapters::RawLedgerSource.new(fetcher: ledger_fetcher('prod' => [200, prod_ledger_body],
                                                                      'stage' => [404, '']))
      api = adapters::FileApiSource.new(path: File.join(root, 'tmp', 'repos', 'greeter-http', 'openapi.yaml'),
                                        commit: '5b818a2fa3f69d9a8bcc9c44f634c2ee2984670c').api
      adrs = adapters::FileAdrSource.new(roots: {
                                           'greeter-docs' => File.join(SpecHelpers::ROOT, 'docs', 'adr'),
                                           'greeter-http' => File.join(root, 'tmp', 'repos', 'greeter-http',
                                                                       'docs', 'adr')
                                         }).adrs
      diagrams = adapters::FileDiagramSource.new(dir: File.join(SpecHelpers::ROOT, 'docs', 'diagrams')).diagrams
      model(repos: repos, traces: repos.filter_map { |r| traces.trace(r.name) },
            ledgers: [ledgers.ledger('prod'), ledgers.ledger('stage')], api: api, adrs: adrs, diagrams: diagrams)
    end
  end

  def cell(html, key, channel)
    html[%r{<td[^>]*data-key="#{key}"[^>]*data-channel="#{channel}"[^>]*>\s*([^<]*?)\s*</td>}, 1]
  end

  def section(html, id)
    html[%r{<section[^>]*id="#{id}"[^>]*>(.*?)</section>}m, 1] || raise("no section #{id}")
  end

  def module_import_url(html)
    scripts = html.scan(/<script\b[^>]*>/)
    raise "expected one module script, got #{scripts.inspect}" unless scripts.one? do |tag|
      tag.include?('type="module"')
    end

    src = scripts.first[/src="([^"]+)"/, 1]
    return src if src.start_with?('https://')

    only_item(File.read(File.join(site, src)).scan(%r{https://cdn\.jsdelivr\.net/npm/[^"')\s]+}).uniq)
  end

  context 'with the index', requirement: 'the-index-summarises-repos-and-coverage',
                            scenario: 'index-lists-repos-and-coverage' do
    it 'links every repo page and shows the coverage summary and build time' do
      covered = %w[greeter-core greeter-cli greeter-http greeter-docs].map do |name|
        reqs = (1..10).map { |n| requirement("req-#{n}") }
        [repo(name, reqs), trace(name, reqs.map { |r| result(r.slug, 'scenario-one', 'passed') })]
      end
      tags = (1..5).to_h { |n| ["greeting-#{n}", "key-#{n}"] }
      acceptance = repo('greeter-acceptance', tags.keys.map { |slug| requirement(slug) }, requirement_tags: tags)

      publish(model(repos: covered.map(&:first) + [acceptance], traces: covered.map(&:last),
                    ledgers: [not_recorded('prod'), not_recorded('stage')]))
      html = page('index.html')

      %w[greeter-core greeter-cli greeter-http greeter-acceptance greeter-docs].each do |name|
        expect(html).to include(%(href="repos/#{name}.html"))
      end
      expect(html).to match(/data-summary="covered"[^>]*>\s*40\s*</)
      expect(html).to match(/data-summary="uncovered"[^>]*>\s*0\s*</)
      expect(html).to match(/data-summary="not-yet-recorded"[^>]*>\s*5\s*</)
      expect(html).to include('2026-11-21T12:00:00Z')
    end
  end

  context 'with repo pages', requirement: 'each-repo-has-a-page-of-requirements-and-results' do
    context 'with the greeter-core fixture', scenario: 'a-repo-page-shows-its-requirement-rows' do
      it 'has one row per requirement, the scenario statuses and the run link' do
        docs_model = fixture_model
        core = docs_model.repos.find { |r| r.name == 'greeter-core' }
        traced = docs_model.traces.fetch('greeter-core').results.map { |r| [r.requirement, r.scenario] }.uniq
        main_slugs = core.requirements.map(&:slug)
        off_main = traced.map(&:first).uniq - main_slugs

        publish(docs_model)
        html = page('repos/greeter-core.html')

        expect(html.scan(/<tr[^>]*data-requirement="([^"]+)"/).flatten).to match_array(core.requirements.map(&:slug))
        expect(core.requirements.size).to eq(10)
        traced.select { |(req, _scen)| main_slugs.include?(req) }.each do |(req, scen)|
          expect(html).to match(/data-requirement="#{req}"[^>]*data-scenario="#{scen}"[^>]*data-status="passed"/)
        end
        expect(off_main).not_to be_empty
        off_main.each { |slug| expect(html).not_to include(%(data-requirement="#{slug}")) }
        expect(html).to include('href="https://github.com/greeterhq/greeter-core/actions/runs/44297674561"')
      end
    end

    context 'with a scenario passed only in the prod smoke trace',
            requirement: 'a-scenario-verified-only-by-the-prod-smoke-trace-links-to-its-run',
            scenario: 'a-prod-smoke-only-pass-links-to-the-smoke-prod-run' do
      it 'shows it passed, labels it as verified by the prod smoke run and links that smoke-prod.yml run' do
        document = fixture_json('traces', 'greeter-http', 'prod-smoke', 'repo-trace.json')
        smoke = domain::Trace.new(
          repo: document['repo'], sha: document['sha'], run_id: document['run_id'],
          recorded_at: document['recorded_at'],
          results: document['results'].map { |r| domain::Result.new(**r.transform_keys(&:to_sym)) }
        )
        docs_model = domain::DocsModel.new(**fixture_model.to_h, deployed_traces: { 'greeter-http' => smoke })

        publish(docs_model)
        html = page('repos/greeter-http.html')
        item = html[%r{<li[^>]*data-scenario="smoke-check-on-a-deployed-stage"[^>]*>.*?</li>}m]

        expect(item).to include('data-requirement="deployed-stage-exposes-version-headers"', 'data-status="passed"',
                                'verified by the prod smoke run',
                                'href="https://github.com/greeterhq/greeter-http/actions/runs/45088245869"')
      end
    end

    context 'with a null run ID', scenario: 'a-null-run-id-gives-no-run-link' do
      it 'shows the results without a run link' do
        core = repo('greeter-core', [requirement('local-run')])
        publish(model(repos: [core],
                      traces: [trace('greeter-core', [result('local-run', 'scenario-one', 'passed')], run_id: nil)]))
        html = page('repos/greeter-core.html')

        expect(html).to include('data-status="passed"')
        expect(html).not_to include('/actions/runs/')
      end
    end
  end

  context 'with the traceability grid', requirement: 'the-traceability-grid-shows-requirement-by-channel' do
    context 'with the real prod ledger', scenario: 'the-prod-grid-renders-from-the-real-ledger' do
      it 'has a row per key, n/a for not_applicable, statuses, and verification per channel' do
        publish(fixture_model)
        prod = section(page('traceability.html'), 'prod')

        expect(prod.scan(/<tr[^>]*data-key="([^"]+)"/).flatten)
          .to match_array(%w[greeting-count greeting-happy greeting-idempotent greeting-invalid greeting-returning])
        expect(cell(prod, 'greeting-count', 'cli')).to eq('n/a')
        expect(cell(prod, 'greeting-count', 'http')).to eq('passed')
        expect(cell(prod, 'greeting-happy', 'cli')).to eq('passed')
        expect(prod).to match(/<th[^>]*data-channel="cli"[^>]*>.*?verified.*?v0\.1\.12/m)
        expect(prod).to match(/<th[^>]*data-channel="http"[^>]*>.*?verified.*?v0\.5\.22/m)
        expect(prod).to include('a-channel-greets-a-valid-guest')
      end
    end

    context 'with a missing stage ledger', scenario: 'a-missing-ledger-shows-not-yet-recorded' do
      it 'says not yet recorded and shows no grid for stage' do
        publish(fixture_model)
        stage = section(page('traceability.html'), 'stage')

        expect(stage).to include('not yet recorded')
        expect(stage).not_to include('<table')
      end
    end
  end

  context 'with the API page', requirement: 'the-api-page-renders-the-openapi-description' do
    context 'with the fixture description', scenario: 'the-api-page-shows-the-greetings-operation' do
      it 'shows the operation, its parameters, request body, every response status and header, with no script' do
        publish(fixture_model)
        html = page('api.html')

        expect(html).to include('POST', '/greetings', 'Greet a guest and return the running count')
        expect(html).to include('Idempotency-Key', 'X-Greeter-Synthetic')
        expect(html).to match(%r{data-request-body.*application/json.*name}m)
        %w[201 200 400 409 413 422 500 503].each { |code| expect(html).to include(%(data-response="#{code}")) }
        expect(html).to include('X-Greeter-Version', 'X-Greeter-Core-Version', 'Retry-After')
        expect(html).not_to include('<script')
      end
    end

    context 'with the description copy', scenario: 'the-api-page-links-to-a-copy-of-the-description' do
      it 'writes a byte-identical openapi.yaml and links to it' do
        publish(fixture_model)

        expect(File.binread(File.join(site, 'openapi.yaml')))
          .to eq(File.binread(fixture('repos', 'greeter-http', 'openapi.yaml')))
        expect(page('api.html')).to include('href="openapi.yaml"')
      end
    end
  end

  context 'with ADRs', requirement: 'adrs-have-an-index-and-one-page-each',
                       scenario: 'adr-pages-are-published-for-both-repos' do
    it "links greeter-docs' three ADRs and greeter-http's ADRs, and every linked page exists" do
      publish(fixture_model)
      links = page('adr/index.html').scan(/href="([^"]+\.html)"/).flatten

      expect(links).to include('greeter-docs/0001-record-architecture-decisions.html',
                               'greeter-docs/0002-openspec-not-kiro-specs.html',
                               'greeter-docs/0003-shared-acceptance-suite-and-channel-ledger.html',
                               'greeter-http/0001-record-architecture-decisions.html',
                               'greeter-http/0002-openapi-authored-and-validated-not-generated.html')
      links.grep(/\Agreeter-/).each { |link| expect(File).to exist(File.join(site, 'adr', link)) }
    end
  end

  context 'with the architecture page', requirement: 'the-architecture-page-renders-the-c4-diagrams' do
    context 'with the real diagrams', scenario: 'the-architecture-page-loads-one-pinned-mermaid-module' do
      it 'has the two diagrams and loads one exact-version Mermaid module' do
        publish(fixture_model)
        html = page('architecture.html')
        diagrams = html.scan(%r{<pre class="mermaid">\s*(.*?)</pre>}m).flatten

        expect(diagrams.size).to eq(2)
        expect(diagrams.map { |d| d.lines.first.strip }).to contain_exactly('C4Context', 'C4Container')
        expect(module_import_url(html)).to match(mermaid_url)
      end
    end

    context 'with the diagram files', scenario: 'the-diagrams-name-every-system' do
      it 'mentions every system between the context and container diagrams' do
        text = %w[c4-context.mmd c4-container.mmd]
               .map { |name| File.read(File.join(SpecHelpers::ROOT, 'docs', 'diagrams', name)) }.join("\n")

        expect(text).to include('greeter-core', 'greeter-cli', 'greeter-http', 'greeter-acceptance', 'greeter-docs',
                                'ledger-prod', 'ledger-stage', 'GitHub Pages')
      end
    end
  end

  context 'with placeholders', requirement: 'contracts-and-slo-pages-are-placeholders',
                               scenario: 'placeholder-pages-say-not-yet-available' do
    it 'publishes contracts.html and slo.html saying not yet available' do
      publish(model(repos: []))

      expect(page('contracts.html')).to include('not yet available')
      expect(page('slo.html')).to include('not yet available')
    end
  end

  context 'with sourced script text', requirement: 'no-page-renders-unescaped-sourced-text',
                                      scenario: 'a-script-heading-is-escaped' do
    it 'escapes it on every page that shows it' do
      script = SpecHelpers::SCRIPT
      core = repo('greeter-core', [requirement('evil', title: "Evil #{script}")])
      api = domain::ApiDescription.new(
        title: 'greeter-http', version: '1.0.0', description: script, commit: 'c' * 40, raw: "openapi: 3.1.0\n",
        operations: [domain::ApiDescription::Operation.new(http_method: 'post', path: '/greetings', summary: script,
                                                           parameters: [], request_body: nil, responses: {})]
      )
      adr = domain::Adr.new(repo: 'greeter-docs', file_name: '0001-x.md', title: 'X', body: "# X\n\n#{script}\n")
      diagram = domain::Diagram.new(name: 'c4-context', source: "C4Context\n  title #{script}\n")
      prod = ledger('prod', { 'greeting-happy' => { script => 'passed' } }, channels: { script => 'verified' })

      publish(model(repos: [core], traces: [trace('greeter-core', [])], ledgers: [prod, not_recorded('stage')],
                    api: api, adrs: [adr], diagrams: [diagram]))

      all_pages.each { |name, html| expect(html).not_to include(script), "#{name} has raw script text" }
      %w[repos/greeter-core.html api.html adr/greeter-docs/0001-x.html architecture.html traceability.html]
        .each { |name| expect(page(name)).to include(SpecHelpers::ESCAPED_SCRIPT), "#{name} lacks escaped text" }
    end
  end

  context 'with internal links', requirement: 'a-broken-internal-link-fails-the-build' do
    def lychee(dir)
      Open3.capture2e('lychee', '--offline', '--no-progress', dir)
    end

    context 'with a broken link', scenario: 'a-broken-internal-link-fails-the-build' do
      it 'fails and names the page and the link' do
        write_file(File.join(site, 'index.html'), '<html><body><a href="repos/missing.html">x</a></body></html>')

        output, status = lychee(site)

        expect(status).not_to be_success
        expect(output).to include('index.html', 'repos/missing.html')
      end
    end

    context 'with the published fixture site', scenario: 'the-published-site-has-no-broken-internal-links' do
      it 'passes the offline link check' do
        publish(fixture_model)

        output, status = lychee(site)

        expect(status).to be_success, output
      end
    end
  end

  describe 'URL safety (design S5)' do
    it 'drops script-scheme ADR link targets and keeps http, https and relative ones' do
      body = <<~MD
        # Links

        [a](JaVaScript:alert(1)) [b]( javascript:alert(1)) [c](java&#x09;script:alert(1)) [d](data:text/html,x)
        [ok](https://example.com/) [rel](../index.html)
      MD
      adr = domain::Adr.new(repo: 'greeter-docs', file_name: '0009-links.md', title: 'Links', body: body)
      publish(model(repos: [], adrs: [adr]))
      hrefs = page('adr/greeter-docs/0009-links.html').scan(/href="([^"]*)"/).flatten

      expect(hrefs).to include('https://example.com/', '../index.html')
      expect(hrefs.grep(/script|data:/i)).to be_empty
    end

    it 'links a ledger run only when its run_id is all digits' do
      prod = domain::LedgerView.recorded(
        environment: 'prod', suite_version: 'v0.3.0',
        channels: { 'cli' => domain::LedgerView::Channel.new(name: 'cli', verification: 'verified', version: 'v1',
                                                             run_id: '12abc') },
        requirements: { 'greeting-happy' => { 'cli' => 'passed' } }
      )
      publish(model(repos: [], ledgers: [prod, not_recorded('stage')]))

      expect(page('traceability.html')).not_to include('12abc"')
      expect(page('traceability.html')).not_to include('/actions/runs/12abc')
    end

    it 'never puts a non-slug channel or key into an id or data attribute' do
      prod = ledger('prod', { 'Bad Key"><' => { 'cli' => 'passed' } }, channels: { 'c li"' => 'verified' })
      publish(model(repos: [], ledgers: [prod, not_recorded('stage')]))
      html = page('traceability.html')

      expect(html.scan(/\s(?:id|data-key|data-channel)="([^"]*)"/).flatten)
        .to all(match(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/))
    end
  end

  describe 'page hardening (design S6, S10)' do
    it 'sets the CSP meta tag on every page and has no inline script' do
      publish(fixture_model)

      all_pages.each do |name, html|
        expect(html).to include(%(<meta http-equiv="Content-Security-Policy" content="#{csp}">)), name
        expect(html.scan(/<script\b[^>]*>/)).to all(include('src=')), name
      end
      site_pages.each { |name| expect(all_pages).to include(name) }
    end

    it 'labels the API page with the greeter-http main commit and version' do
      publish(fixture_model)
      html = page('api.html')

      expect(html).to include('5b818a2fa3f69d9a8bcc9c44f634c2ee2984670c', '0.5.22')
      expect(html).to match(/\bmain\b/)
    end
  end
end
