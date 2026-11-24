# frozen_string_literal: true

require 'fileutils'
require 'json'

module GreeterDocs
  # Fetches one repo's prod smoke trace (design D12, S11) for FetchSources.
  #
  # The run is read from the REST runs endpoint, because `gh run list --json`
  # has no `path` field, and is re-checked rather than trusted: it must come
  # from the configured workflow file, on main, and not from a pull request.
  # The artifact must hold exactly the expected file, and that trace's sha
  # must be the run's head_sha. Any failed check removes the download and
  # raises FetchSources::Failed naming the run ID. An unusable run or a missing
  # or expired artifact is not an error: nothing is downloaded.
  class DeployedTraceFetch
    TRACE = 'repo-trace.json'

    # runner: a callable taking an argv and returning [stdout, stderr, success].
    # say: a callable taking one line of output (FetchSources makes it log-safe
    # and redacts the token).
    # config: workflow:, path:, artifact:, file:, dir: (see FetchSources::DEPLOYED_TRACES)
    def initialize(runner:, say:, root:, repo:, config:)
      @runner = runner
      @say = say
      @root = root
      @repo = repo
      @config = config
    end

    def call
      run = usable_run
      return none('no successful run of the configured workflow on main') unless run

      id = run['id'].to_s
      return none("run #{id} has no live #{@config.fetch(:artifact)} artifact") unless live_artifact?(id)

      download(id)
      verify(id, run['head_sha'])
      File.rename(file_path, File.join(dir, TRACE))
      @say.call("#{@repo}: downloaded the prod smoke trace from run #{id}")
    end

    private

    def usable_run
      listing = run!('gh', 'api', "repos/greeterhq/#{@repo}/actions/workflows/#{@config.fetch(:workflow)}/runs" \
                                  '?branch=main&status=success&per_page=1')
      run = parse(listing, 'workflow_runs').first
      run if run.is_a?(Hash) && usable?(run)
    end

    def usable?(run)
      run['path'] == @config.fetch(:path) && run['head_branch'] == 'main' && run['event'] != 'pull_request' &&
        run['id'].to_s.match?(/\A\d+\z/)
    end

    def live_artifact?(id)
      listing = run!('gh', 'api', "repos/greeterhq/#{@repo}/actions/runs/#{id}/artifacts")
      parse(listing, 'artifacts').any? do |artifact|
        artifact.is_a?(Hash) && artifact['name'] == @config.fetch(:artifact) && artifact['expired'] == false
      end
    end

    def download(id)
      run!('gh', 'run', 'download', id, '-R', "greeterhq/#{@repo}", '-n', @config.fetch(:artifact), '-D', relative_dir)
    end

    def verify(id, head_sha)
      files = Dir.exist?(dir) ? Dir.children(dir) : []
      reject(id, "the artifact must hold only #{@config.fetch(:file)}") unless files == [@config.fetch(:file)]
      reject(id, "the trace's sha does not match the run's head_sha") unless trace_sha(id) == head_sha
    end

    def trace_sha(id)
      document = JSON.parse(File.read(file_path))
      document.is_a?(Hash) ? document['sha'] : reject(id, 'the trace is not a JSON object')
    rescue JSON::ParserError, SystemCallError
      reject(id, 'the trace cannot be read')
    end

    def reject(id, reason)
      FileUtils.rm_rf(dir)
      raise FetchSources::Failed, "#{@repo}: prod smoke trace from run #{id} refused: #{reason}"
    end

    # Runs one command; raises FetchSources::Failed with its stderr when it fails.
    def run!(*argv)
      stdout, stderr, success = @runner.call(*argv)
      raise FetchSources::Failed, "#{argv.join(' ')} failed: #{stderr}" unless success

      stdout
    end

    def parse(listing, key)
      document = JSON.parse(listing)
      items = document.is_a?(Hash) ? document[key] : nil
      raise FetchSources::Failed, "#{@repo}: unexpected #{key} listing from the GitHub API" unless items.is_a?(Array)

      items
    rescue JSON::ParserError
      raise FetchSources::Failed, "#{@repo}: invalid JSON in the #{key} listing from the GitHub API"
    end

    def none(reason)
      @say.call("#{@repo}: no prod smoke trace (#{reason})")
    end

    def relative_dir
      File.join('tmp', 'traces', @repo, @config.fetch(:dir))
    end

    def dir
      File.join(@root, relative_dir)
    end

    def file_path
      File.join(dir, @config.fetch(:file))
    end
  end
end
