# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'

# Shared helpers for fixtures, temp directories and in-memory domain models.
# Domain constants are referenced only inside methods, so a missing
# implementation fails the calling example with NameError.
module SpecHelpers
  ROOT = File.expand_path('../..', __dir__)
  FIXTURES = File.join(ROOT, 'spec', 'fixtures')
  PRODUCERS = %w[greeter-core greeter-cli greeter-http greeter-acceptance].freeze
  LEDGER_URL = 'https://raw.githubusercontent.com/greeterhq/greeter-acceptance/ledger-%s/ledger.json'
  SCRIPT = '<script>alert(1)</script>'
  ESCAPED_SCRIPT = '&lt;script&gt;alert(1)&lt;/script&gt;'

  # A stub for the Open3 argv runner: records each argv and answers from a
  # block returning [stdout, stderr, success], or nil for a silent success.
  class StubRunner
    attr_reader :calls

    def initialize(&responder)
      @responder = responder
      @calls = []
    end

    def call(*argv)
      @calls << argv
      @responder.call(argv) || ['', '', true]
    end
  end

  def fixture(*parts)
    File.join(FIXTURES, *parts)
  end

  def read_fixture(*parts)
    File.read(fixture(*parts))
  end

  def fixture_json(*parts)
    JSON.parse(read_fixture(*parts))
  end

  def write_file(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def write_json(path, document)
    write_file(path, JSON.pretty_generate(document))
  end

  # A temp workspace laid out the way bin/fetch-sources leaves it:
  # <root>/tmp/repos/<repo> and <root>/tmp/traces/<repo>/repo-trace.json,
  # copied from the captured fixtures. Yields the workspace root.
  def with_fetched_workspace
    Dir.mktmpdir('greeter-docs-ws') do |root|
      PRODUCERS.each do |repo|
        FileUtils.mkdir_p(File.join(root, 'tmp', 'repos'))
        FileUtils.cp_r(fixture('repos', repo), File.join(root, 'tmp', 'repos', repo))
        FileUtils.mkdir_p(File.join(root, 'tmp', 'traces', repo))
        FileUtils.cp(fixture('traces', repo, 'repo-trace.json'), File.join(root, 'tmp', 'traces', repo))
      end
      yield root
    end
  end

  # Adds a passed result for a requirement to a workspace trace, so a fixture
  # workspace can be made fully covered.
  def add_passed_result(root, repo, requirement, scenario, location = 'spec/added_spec.rb:1')
    path = File.join(root, 'tmp', 'traces', repo, 'repo-trace.json')
    document = JSON.parse(File.read(path))
    document['results'] << { 'requirement' => requirement, 'scenario' => scenario, 'status' => 'passed',
                             'source' => 'rspec', 'location' => location }
    write_json(path, document)
  end

  # A ledger fetcher: maps environment -> [status, body]. Records every URL it
  # is asked for in #urls.
  def ledger_fetcher(responses)
    urls = []
    fetcher = lambda do |url|
      urls << url
      environment = responses.keys.find { |env| url == format(LEDGER_URL, env) }
      raise "unexpected URL #{url}" unless environment

      response = responses.fetch(environment)
      raise response if response.is_a?(Exception)

      response
    end
    fetcher.define_singleton_method(:urls) { urls }
    fetcher
  end

  def prod_ledger_body
    read_fixture('ledgers', 'prod.json')
  end

  def stage_ledger_body
    document = JSON.parse(prod_ledger_body)
    document['environment'] = 'stage'
    JSON.generate(document)
  end

  # ---- in-memory domain builders ----

  def domain
    GreeterDocs::Domain
  end

  def scenario(slug, title = slug)
    domain::Scenario.new(slug: slug, title: title)
  end

  def requirement(slug, capability: 'cap', scenarios: ['scenario-one'], title: slug,
                  spec_path: "openspec/specs/#{capability}/spec.md")
    domain::Requirement.new(slug: slug, title: title, capability: capability, spec_path: spec_path,
                            scenarios: scenarios.map { |name| scenario(name) })
  end

  def repo(name, requirements, requirement_tags: {})
    domain::Repo.new(name: name, requirements: requirements, requirement_tags: requirement_tags)
  end

  def result(requirement, scenario, status, location: 'spec/x_spec.rb:1')
    domain::Result.new(requirement: requirement, scenario: scenario, status: status, source: 'rspec',
                       location: location)
  end

  def trace(repo_name, results, run_id: '123', sha: 'a' * 40)
    domain::Trace.new(repo: repo_name, sha: sha, run_id: run_id, recorded_at: '2026-11-21T00:00:00Z',
                      results: results)
  end

  def ledger(environment, requirements, channels: { 'cli' => 'verified', 'http' => 'verified' })
    domain::LedgerView.recorded(
      environment: environment, suite_version: 'v0.3.0',
      channels: channels.to_h do |name, verification|
        [name, domain::LedgerView::Channel.new(name: name, verification: verification, version: 'v1.0.0',
                                               run_id: '44886860348')]
      end,
      requirements: requirements
    )
  end

  def not_recorded(environment)
    domain::LedgerView.not_recorded(environment)
  end

  def model(repos:, traces: [], ledgers: [], api: nil, adrs: [], diagrams: [])
    domain::DocsModel.new(
      repos: repos,
      traces: traces.to_h { |t| [t.repo, t] },
      ledgers: ledgers.to_h { |l| [l.environment, l] },
      api: api, adrs: adrs, diagrams: diagrams,
      contracts: :not_yet_available, slos: :not_yet_available,
      built_at: Time.utc(2026, 11, 21, 12, 0, 0)
    )
  end
end
