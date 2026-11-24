# frozen_string_literal: true

RSpec.describe 'GreeterDocs::Build' do
  let(:http_violation) do
    'greeter-http version-headers deployed-stage-exposes-version-headers openspec/specs/version-headers/spec.md'
  end

  around do |example|
    with_fetched_workspace do |root|
      @root = root
      @site = File.join(root, '_site')
      example.run
    end
  end

  attr_reader :root, :site

  # deployed: true also wires the prod smoke trace source (design D12).
  def build(ledgers: { 'prod' => [200, prod_ledger_body], 'stage' => [404, ''] }, deployed: false)
    adapters = GreeterDocs::Adapters
    repos_dir = File.join(root, 'tmp', 'repos')
    smoke = if deployed
              { deployed_trace_source: adapters::ArtifactTraceSource.new(workspace_root: root,
                                                                         subdir: 'prod-smoke') }
            else
              {}
            end
    GreeterDocs::Build.new(
      **smoke,
      spec_source: adapters::GitSpecSource.new(clones_root: repos_dir, workspace_root: root,
                                               producers: SpecHelpers::PRODUCERS),
      trace_source: adapters::ArtifactTraceSource.new(workspace_root: root),
      ledger_source: adapters::RawLedgerSource.new(fetcher: ledger_fetcher(ledgers)),
      api_source: adapters::FileApiSource.new(path: File.join(repos_dir, 'greeter-http', 'openapi.yaml'),
                                              commit: '5b818a2fa3f69d9a8bcc9c44f634c2ee2984670c'),
      adr_source: adapters::FileAdrSource.new(roots: {
                                                'greeter-docs' => File.join(SpecHelpers::ROOT, 'docs', 'adr'),
                                                'greeter-http' => File.join(repos_dir, 'greeter-http', 'docs', 'adr')
                                              }),
      diagram_source: adapters::FileDiagramSource.new(dir: File.join(SpecHelpers::ROOT, 'docs', 'diagrams')),
      contract_source: adapters::NullContractSource.new,
      slo_source: adapters::NullSloSource.new,
      publisher: adapters::ErbHtmlPublisher.new(templates_dir: File.join(SpecHelpers::ROOT, 'templates'),
                                                output_dir: site),
      clock: -> { Time.utc(2026, 11, 21, 12, 0, 0) }
    ).call
  end

  def cover_http_requirement
    add_passed_result(root, 'greeter-http', 'deployed-stage-exposes-version-headers', 'smoke-check-on-a-deployed-stage')
  end

  def add_prod_smoke_trace
    path = File.join(root, 'tmp', 'traces', 'greeter-http', 'prod-smoke', 'repo-trace.json')
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.cp(fixture('traces', 'greeter-http', 'prod-smoke', 'repo-trace.json'), path)
  end

  context 'with the prod smoke source', requirement: 'a-prod-smoke-trace-supplements-a-repo-s-ci-trace' do
    context 'when the prod smoke trace passed what CI only skipped',
            scenario: 'a-passed-prod-smoke-result-covers-a-requirement-ci-only-skipped' do
      it 'reports no violation and exits zero' do
        add_prod_smoke_trace

        outcome = build(deployed: true)

        expect(outcome.exit_code).to eq(0), outcome.lines.join("\n")
        expect(File).to exist(File.join(site, 'index.html'))
      end
    end

    context 'when there is no prod smoke trace',
            scenario: 'without-a-prod-smoke-trace-the-requirement-stays-uncovered' do
      it 'exits non-zero and names the requirement exactly as without the source' do
        outcome = build(deployed: true)

        expect(outcome.exit_code).not_to eq(0)
        expect(outcome.lines).to eq([http_violation])
        expect(File).not_to exist(site)
      end
    end
  end

  context 'when requirements on main are uncovered',
          requirement: 'the-build-fails-and-names-every-uncovered-requirement' do
    context 'with the captured sources', scenario: 'an-uncovered-requirement-fails-the-build-and-is-named' do
      it 'exits non-zero, writes no site and names the repo, capability, requirement and spec file' do
        outcome = build

        expect(outcome.exit_code).not_to eq(0)
        expect(outcome.lines).to eq([http_violation])
        expect(File).not_to exist(site)
      end
    end

    context 'with uncovered requirements in two repos', scenario: 'every-violation-is-listed-not-just-the-first' do
      it 'names every violation with its repo, capability and spec file' do
        FileUtils.rm_rf(File.join(root, 'tmp', 'traces', 'greeter-core'))

        lines = build.lines

        expect(lines).to include(http_violation)
        expect(lines).to include('greeter-core greeting-core validates-and-normalises-a-guest-name ' \
                                 'openspec/specs/greeting-core/spec.md')
        expect(lines.count { |line| line.start_with?('greeter-core ') }).to eq(10)
      end
    end

    context 'with every requirement covered', scenario: 'full-coverage-passes-the-build' do
      it 'exits zero and writes the index' do
        cover_http_requirement

        outcome = build

        expect(outcome.exit_code).to eq(0), outcome.lines.join("\n")
        expect(File).to exist(File.join(site, 'index.html'))
      end
    end
  end

  context 'when a ledger is missing', requirement: 'a-missing-ledger-is-not-yet-recorded',
                                      scenario: 'a-missing-ledger-renders-not-yet-recorded-and-the-build-passes' do
    it 'passes and says not yet recorded for stage' do
      cover_http_requirement

      outcome = build(ledgers: { 'prod' => [200, prod_ledger_body], 'stage' => [404, 'Not Found'] })

      expect(outcome.exit_code).to eq(0), outcome.lines.join("\n")
      stage = File.read(File.join(site, 'traceability.html'))[%r{<section[^>]*id="stage"[^>]*>(.*?)</section>}m, 1]
      expect(stage).to include('not yet recorded')
    end
  end

  describe 'source errors' do
    it 'turns a SourceError into a non-zero exit with its message and writes no site' do
      cover_http_requirement
      write_file(File.join(root, 'tmp', 'traces', 'greeter-cli', 'repo-trace.json'), 'not json')

      outcome = build

      expect(outcome.exit_code).not_to eq(0)
      expect(outcome.lines.join("\n")).to include('tmp/traces/greeter-cli/repo-trace.json')
      expect(File).not_to exist(site)
    end

    it 'treats a missing prod ledger as not yet recorded for the tag-mapped greeting requirements' do
      cover_http_requirement

      outcome = build(ledgers: { 'prod' => [404, ''], 'stage' => [404, ''] })

      expect(outcome.exit_code).to eq(0), outcome.lines.join("\n")
      expect(File.read(File.join(site, 'index.html'))).to match(/data-summary="not-yet-recorded"[^>]*>\s*5\s*</)
    end
  end

  describe 'bin/build-docs' do
    it 'ships as an executable' do
      expect(File.executable?(File.join(SpecHelpers::ROOT, 'bin', 'build-docs'))).to be(true)
    end
  end
end
