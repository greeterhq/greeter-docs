# frozen_string_literal: true

require 'stringio'

RSpec.describe 'GreeterDocs::FetchSources' do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  around do |example|
    Dir.mktmpdir('greeter-docs-fetch') do |root|
      @root = root
      example.run
    end
  end

  attr_reader :root

  def run_list_json(id, created_at)
    JSON.generate([{ 'databaseId' => id, 'createdAt' => created_at }])
  end

  def event_of(argv)
    index = argv.index('--event')
    index && argv[index + 1]
  end

  def fetch(runner, env: {})
    GreeterDocs::FetchSources.new(runner: runner, root: root, env: env, out: out, err: err).call
  end

  def every_repo_has_runs
    SpecHelpers::StubRunner.new do |argv|
      next unless argv.first(3) == %w[gh run list]

      repo_index = SpecHelpers::PRODUCERS.index(argv[argv.index('-R') + 1].delete_prefix('greeterhq/'))
      case event_of(argv)
      when 'push' then [run_list_json(1000 + repo_index, '2026-11-20T10:00:00Z'), '', true]
      when 'schedule' then [run_list_json(2000 + repo_index, '2026-11-17T06:17:00Z'), '', true]
      else ['[]', '', true]
      end
    end
  end

  context 'when fetching the producers',
          requirement: 'sources-are-fetched-as-shallow-main-clones-and-latest-main-traces' do
    context 'with a successful run for every repo', scenario: 'fetch-issues-the-expected-commands' do
      it 'clones, lists push and schedule runs, and downloads the newer run for each repo' do
        runner = every_repo_has_runs

        expect(fetch(runner)).to eq(0)

        expected = SpecHelpers::PRODUCERS.each_with_index.flat_map do |repo, index|
          [
            ['gh', 'repo', 'clone', "greeterhq/#{repo}", "tmp/repos/#{repo}", '--', '--depth', '1', '--branch', 'main'],
            ['gh', 'run', 'list', '-R', "greeterhq/#{repo}", '--workflow', 'ci.yml', '--branch', 'main',
             '--status', 'success', '--event', 'push', '--limit', '1', '--json', 'databaseId,createdAt'],
            ['gh', 'run', 'list', '-R', "greeterhq/#{repo}", '--workflow', 'ci.yml', '--branch', 'main',
             '--status', 'success', '--event', 'schedule', '--limit', '1', '--json', 'databaseId,createdAt'],
            ['gh', 'run', 'download', (1000 + index).to_s, '-R', "greeterhq/#{repo}", '-n', 'repo-trace',
             '-D', "tmp/traces/#{repo}"]
          ]
        end
        expect(runner.calls).to eq(expected)
        expect(runner.calls.flatten.join(' ')).not_to include('greeter-docs')
      end
    end

    context 'when a fork pull request from a branch named main ran last',
            scenario: 'a-fork-pull-request-from-a-branch-named-main-is-not-used' do
      it 'downloads the push run and never lists runs without an event filter' do
        runner = SpecHelpers::StubRunner.new do |argv|
          next unless argv.first(3) == %w[gh run list]

          case event_of(argv)
          when 'push' then [run_list_json(1, '2026-11-01T00:00:00Z'), '', true]
          when 'schedule' then ['[]', '', true]
          else [run_list_json(999, '2026-11-21T00:00:00Z'), '', true] # the fork PR run
          end
        end

        fetch(runner)

        lists = runner.calls.select { |argv| argv.first(3) == %w[gh run list] }
        downloads = runner.calls.select { |argv| argv.first(3) == %w[gh run download] }
        expect(lists).to all(include('--event'))
        expect(downloads.map { |argv| argv[3] }.uniq).to eq(['1'])
      end
    end

    context 'when a repo has no successful run', scenario: 'a-repo-with-no-successful-run-gets-no-trace' do
      it 'downloads nothing for it and exits zero' do
        runner = SpecHelpers::StubRunner.new do |argv|
          next unless argv.first(3) == %w[gh run list]

          if argv.include?('greeterhq/greeter-cli')
            ['[]', '',
             true]
          else
            [run_list_json(5, '2026-11-20T00:00:00Z'), '', true]
          end
        end

        expect(fetch(runner)).to eq(0)
        downloads = runner.calls.select { |argv| argv.first(3) == %w[gh run download] }
        expect(downloads.map { |argv| argv[5] }).to eq(%w[greeterhq/greeter-core greeterhq/greeter-http
                                                          greeterhq/greeter-acceptance])
      end
    end

    context 'when a command fails with the token in its output', scenario: 'the-token-is-not-echoed' do
      it 'redacts the token from stdout and stderr and exits non-zero' do
        token = 'ghs_s3cr3tT0kenValue'
        runner = SpecHelpers::StubRunner.new do |argv|
          ['', "fatal: could not read from https://x-access-token:#{token}@github.com", false] if argv[1] == 'repo'
        end

        status = fetch(runner, env: { 'GH_TOKEN' => token })

        expect(status).not_to eq(0)
        expect(out.string + err.string).not_to include(token)
        expect(err.string).to include('***')
      end
    end
  end

  describe 'workspace hygiene' do
    it 'removes stale producer clones and traces but never touches greeter-docs' do
      stale = write_file(File.join(root, 'tmp', 'traces', 'greeter-core', 'old.json'), '{}')
      own = write_file(File.join(root, 'tmp', 'traces', 'greeter-docs', 'repo-trace.json'), '{}')
      write_file(File.join(root, 'tmp', 'repos', 'greeter-http', 'stale.txt'), 'x')

      fetch(every_repo_has_runs)

      expect(File).not_to exist(stale)
      expect(File).not_to exist(File.join(root, 'tmp', 'repos', 'greeter-http', 'stale.txt'))
      expect(File).to exist(own)
    end

    it 'ships bin/fetch-sources as an executable' do
      expect(File.executable?(File.join(SpecHelpers::ROOT, 'bin', 'fetch-sources'))).to be(true)
    end
  end
end
