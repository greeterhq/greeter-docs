# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'

module GreeterDocs
  # Shallow-clones the producer repos at main into tmp/repos/<repo> and
  # downloads each one's latest successful main `repo-trace` artifact into
  # tmp/traces/<repo>. Only push and schedule runs are considered, so a fork
  # pull request from a branch named main is never used (design S2).
  # greeter-docs itself is never fetched.
  class FetchSources
    PRODUCERS = %w[greeter-core greeter-cli greeter-http greeter-acceptance].freeze
    EVENTS = %w[push schedule].freeze

    class Failed < StandardError; end

    # runner: a callable taking an argv and returning [stdout, stderr, success].
    def initialize(root:, runner: nil, env: ENV, out: $stdout, err: $stderr)
      @root = root
      @env = env
      @out = out
      @err = err
      @runner = runner || method(:capture)
    end

    def call
      PRODUCERS.each { |repo| fetch(repo) }
      0
    rescue Failed => e
      @err.puts(LogSafe.line(redact(e.message)))
      1
    end

    private

    def fetch(repo)
      clean(repo)
      run!('gh', 'repo', 'clone', "greeterhq/#{repo}", "tmp/repos/#{repo}", '--', '--depth', '1', '--branch', 'main')
      run_id = latest_run(repo)
      return say("#{repo}: no successful main run of ci.yml; no trace") unless run_id

      run!('gh', 'run', 'download', run_id, '-R', "greeterhq/#{repo}", '-n', 'repo-trace', '-D', "tmp/traces/#{repo}")
      say("#{repo}: cloned main and downloaded repo-trace from run #{run_id}")
    end

    def clean(repo)
      FileUtils.rm_rf(File.join(@root, 'tmp', 'repos', repo))
      FileUtils.rm_rf(File.join(@root, 'tmp', 'traces', repo))
      FileUtils.mkdir_p(File.join(@root, 'tmp', 'repos'))
    end

    # The newer of the latest successful push run and schedule run, as a string.
    def latest_run(repo)
      runs = EVENTS.filter_map do |event|
        listing = run!('gh', 'run', 'list', '-R', "greeterhq/#{repo}", '--workflow', 'ci.yml', '--branch', 'main',
                       '--status', 'success', '--event', event, '--limit', '1', '--json', 'databaseId,createdAt')
        parse_runs(listing, repo).first
      end
      runs.max_by { |run| run['createdAt'].to_s }&.fetch('databaseId')&.to_s
    end

    def parse_runs(listing, repo)
      runs = JSON.parse(listing)
      raise Failed, "gh run list for greeterhq/#{repo} returned an unexpected shape" unless runs.is_a?(Array)

      runs.select { |run| run.is_a?(Hash) && run['databaseId'] }
    rescue JSON::ParserError
      raise Failed, "gh run list for greeterhq/#{repo} returned invalid JSON"
    end

    def run!(*argv)
      stdout, stderr, success = @runner.call(*argv)
      raise Failed, "#{argv.join(' ')} failed: #{stderr}" unless success

      stdout
    end

    def capture(*argv)
      stdout, stderr, status = Open3.capture3(*argv, chdir: @root)
      [stdout, stderr, status.success?]
    end

    def say(message)
      @out.puts(LogSafe.line(redact(message)))
    end

    def redact(text)
      token = @env['GH_TOKEN'].to_s
      token.empty? ? text : text.gsub(token, '***')
    end
  end
end
