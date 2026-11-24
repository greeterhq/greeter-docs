# frozen_string_literal: true

require 'stringio'

RSpec.describe 'GreeterDocs::FetchSources' do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:smoke_runs_path) do
    'repos/greeterhq/greeter-http/actions/workflows/smoke-prod.yml/runs?branch=main&status=success&per_page=1'
  end
  let(:smoke_dir) { File.join(root, 'tmp', 'traces', 'greeter-http', 'prod-smoke') }
  let(:smoke_trace) { read_fixture('traces', 'greeter-http', 'prod-smoke', 'repo-trace.json') }
  let(:smoke_sha) { JSON.parse(smoke_trace)['sha'] }
  let(:live_artifact) { [{ 'name' => 'repo-trace-smoke-prod', 'expired' => false }] }

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

  # A smoke-prod.yml run as the REST runs endpoint returns it.
  def smoke_run(overrides = {})
    { 'id' => 3000, 'created_at' => '2026-11-23T00:20:00Z', 'head_branch' => 'main', 'head_sha' => smoke_sha,
      'event' => 'schedule', 'path' => '.github/workflows/smoke-prod.yml' }.merge(overrides)
  end

  # Answers the three smoke calls: the runs lookup, the artifact list, and the
  # download, which writes `files` (name => content) into the -D directory.
  # Returns nil for any other command.
  def smoke_responder(runs: [], artifacts: live_artifact, files: { 'repo-trace-smoke-prod.json' => smoke_trace })
    lambda do |argv|
      if argv == ['gh', 'api', smoke_runs_path]
        [JSON.generate('workflow_runs' => runs), '', true]
      elsif argv.first(2) == %w[gh api] && argv[2].to_s.match?(%r{/actions/runs/\d+/artifacts\z})
        [JSON.generate('artifacts' => artifacts), '', true]
      elsif argv.first(3) == %w[gh run download] && argv.include?('repo-trace-smoke-prod')
        files.each { |name, content| write_file(File.join(root, argv.last, name), content) }
        ['', '', true]
      end
    end
  end

  # A runner that answers smoke calls with `smoke` and everything else with the block.
  def stub_runner(smoke: smoke_responder, &block)
    SpecHelpers::StubRunner.new { |argv| smoke.call(argv) || block&.call(argv) }
  end

  def every_repo_has_runs(smoke: smoke_responder)
    stub_runner(smoke: smoke) do |argv|
      next unless argv.first(3) == %w[gh run list]

      repo_index = SpecHelpers::PRODUCERS.index(argv[argv.index('-R') + 1].delete_prefix('greeterhq/'))
      case event_of(argv)
      when 'push' then [run_list_json(1000 + repo_index, '2026-11-20T10:00:00Z'), '', true]
      when 'schedule' then [run_list_json(2000 + repo_index, '2026-11-17T06:17:00Z'), '', true]
      else ['[]', '', true]
      end
    end
  end

  def smoke_calls(runner)
    runner.calls.select { |argv| argv.first(2) == %w[gh api] || argv.include?('repo-trace-smoke-prod') }
  end

  def expect_failed_without_trace(status)
    expect(status).not_to eq(0)
    expect(err.string).to include('3000')
    expect(File).not_to exist(smoke_dir)
  end

  context 'when fetching the producers',
          requirement: 'sources-are-fetched-as-shallow-main-clones-and-latest-main-traces' do
    context 'with a successful run for every repo', scenario: 'fetch-issues-the-expected-commands' do
      it 'clones, lists and downloads the newer CI run for each repo, then fetches the prod smoke trace' do
        runner = every_repo_has_runs(smoke: smoke_responder(runs: [smoke_run]))

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
        expected += [
          ['gh', 'api', smoke_runs_path],
          ['gh', 'api', 'repos/greeterhq/greeter-http/actions/runs/3000/artifacts'],
          ['gh', 'run', 'download', '3000', '-R', 'greeterhq/greeter-http', '-n', 'repo-trace-smoke-prod',
           '-D', 'tmp/traces/greeter-http/prod-smoke']
        ]
        expect(runner.calls).to eq(expected)
        expect(runner.calls.flatten.join(' ')).not_to include('greeter-docs')
      end
    end

    context 'when a fork pull request from a branch named main ran last',
            scenario: 'a-fork-pull-request-from-a-branch-named-main-is-not-used' do
      it 'downloads the push run, filters every ci.yml lookup by event, and asks smoke-prod for main successes' do
        runner = stub_runner do |argv|
          next unless argv.first(3) == %w[gh run list]

          case event_of(argv)
          when 'push' then [run_list_json(1, '2026-11-01T00:00:00Z'), '', true]
          when 'schedule' then ['[]', '', true]
          else [run_list_json(999, '2026-11-21T00:00:00Z'), '', true] # the fork PR run
          end
        end

        fetch(runner)

        ci_lists = runner.calls.select { |argv| argv.first(3) == %w[gh run list] && argv.include?('ci.yml') }
        downloads = runner.calls.select { |argv| argv.first(3) == %w[gh run download] }
        smoke_lookup = only_item(runner.calls.select do |argv|
          argv.first(2) == %w[gh api] && argv[2].include?('/actions/workflows/smoke-prod.yml/runs?')
        end)
        query = smoke_lookup[2].split('?', 2).last.split('&')
        expect(ci_lists).to all(include('--event'))
        expect(downloads.map { |argv| argv[3] }.uniq).to eq(['1'])
        expect(query).to include('branch=main', 'status=success')
      end
    end

    context 'when a repo has no successful run', scenario: 'a-repo-with-no-successful-run-gets-no-trace' do
      it 'downloads nothing for it and exits zero' do
        runner = stub_runner do |argv|
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

  context 'when fetching the prod smoke trace',
          requirement: 'prod-smoke-traces-come-from-the-latest-successful-smoke-prod-run' do
    context 'with a usable run and a live artifact', scenario: 'the-prod-smoke-trace-is-fetched-from-smoke-prod-yml' do
      it 'runs the three smoke calls after the CI fetches and leaves the file as prod-smoke/repo-trace.json' do
        runner = every_repo_has_runs(smoke: smoke_responder(runs: [smoke_run]))

        expect(fetch(runner)).to eq(0)

        last_ci_download = runner.calls.rindex { |argv| argv.include?('repo-trace') }
        expect(runner.calls.drop(last_ci_download + 1)).to eq(smoke_calls(runner))
        expect(smoke_calls(runner).map { |argv| argv.first(4) })
          .to eq([['gh', 'api', smoke_runs_path],
                  ['gh', 'api', 'repos/greeterhq/greeter-http/actions/runs/3000/artifacts'],
                  %w[gh run download 3000]])
        expect(Dir.children(smoke_dir)).to eq(['repo-trace.json'])
        expect(File.read(File.join(smoke_dir, 'repo-trace.json'))).to eq(smoke_trace)
      end
    end

    context 'with a run of a workflow at another path', scenario: 'a-run-of-a-workflow-at-another-path-is-not-used' do
      it 'looks up no artifact, downloads nothing, says so and exits zero' do
        runner = every_repo_has_runs(
          smoke: smoke_responder(runs: [smoke_run('path' => '.github/workflows/other/smoke-prod.yml')])
        )

        expect(fetch(runner)).to eq(0)
        expect(smoke_calls(runner)).to eq([['gh', 'api', smoke_runs_path]])
        expect(out.string).to include('no prod smoke trace')
        expect(File).not_to exist(smoke_dir)
      end
    end

    context 'with a run from another branch or a pull request',
            scenario: 'a-run-from-another-branch-or-a-pull-request-is-not-used' do
      it 'looks up no artifact for either, downloads nothing, says so and exits zero' do
        [{ 'head_branch' => 'feature/x' }, { 'event' => 'pull_request' }].each do |overrides|
          runner = every_repo_has_runs(smoke: smoke_responder(runs: [smoke_run(overrides)]))

          expect(fetch(runner)).to eq(0), overrides.inspect
          expect(smoke_calls(runner)).to eq([['gh', 'api', smoke_runs_path]]), overrides.inspect
          expect(File).not_to exist(smoke_dir)
        end
        expect(out.string.scan('no prod smoke trace').size).to eq(2)
      end
    end

    context 'with no successful run', scenario: 'no-successful-smoke-prod-run-downloads-nothing' do
      it 'looks up no artifact, downloads nothing, says so and exits zero' do
        runner = every_repo_has_runs(smoke: smoke_responder(runs: []))

        expect(fetch(runner)).to eq(0)
        expect(smoke_calls(runner)).to eq([['gh', 'api', smoke_runs_path]])
        expect(out.string).to include('no prod smoke trace')
      end
    end
  end

  context 'when the smoke artifact is not live',
          requirement: 'the-prod-smoke-artifact-is-downloaded-only-when-live',
          scenario: 'a-smoke-prod-run-without-a-live-artifact-downloads-nothing' do
    it 'downloads nothing for a missing or an expired artifact, says so and exits zero' do
      [[], [{ 'name' => 'repo-trace-smoke-prod', 'expired' => true }]].each do |artifacts|
        runner = every_repo_has_runs(smoke: smoke_responder(runs: [smoke_run], artifacts: artifacts))

        expect(fetch(runner)).to eq(0), artifacts.inspect
        expect(runner.calls).not_to include(include('repo-trace-smoke-prod')), artifacts.inspect
        expect(File).not_to exist(smoke_dir)
      end
      expect(out.string.scan('no prod smoke trace').size).to eq(2)
    end
  end

  context 'when the smoke artifact has the wrong shape',
          requirement: 'the-prod-smoke-artifact-must-hold-only-the-smoke-trace-file' do
    def fetch_with_files(files)
      fetch(every_repo_has_runs(smoke: smoke_responder(runs: [smoke_run], files: files)))
    end

    context 'with no file', scenario: 'an-artifact-with-no-file-fails-the-fetch' do
      it 'exits non-zero, names the run ID and leaves no prod-smoke directory' do
        expect_failed_without_trace(fetch_with_files({}))
      end
    end

    context 'with two files', scenario: 'an-artifact-with-two-files-fails-the-fetch' do
      it 'exits non-zero, names the run ID and leaves no prod-smoke directory' do
        expect_failed_without_trace(fetch_with_files('repo-trace-smoke-prod.json' => smoke_trace,
                                                     'extra.json' => '{}'))
      end
    end

    context 'with one file of another name', scenario: 'an-artifact-file-with-another-name-fails-the-fetch' do
      it 'exits non-zero, names the run ID and leaves no prod-smoke directory' do
        expect_failed_without_trace(fetch_with_files('trace.json' => smoke_trace))
      end
    end
  end

  context 'when the smoke trace names another commit',
          requirement: 'a-downloaded-prod-smoke-trace-must-name-its-run-s-commit',
          scenario: 'a-sha-mismatch-fails-the-fetch-and-leaves-no-trace' do
    it 'exits non-zero, names the run ID, echoes neither sha and leaves no prod-smoke directory' do
      forged = JSON.generate(JSON.parse(smoke_trace).merge('sha' => 'a' * 40))
      runner = every_repo_has_runs(
        smoke: smoke_responder(runs: [smoke_run('head_sha' => 'b' * 40)],
                               files: { 'repo-trace-smoke-prod.json' => forged })
      )

      expect_failed_without_trace(fetch(runner))
      expect(err.string).not_to include('a' * 40)
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
