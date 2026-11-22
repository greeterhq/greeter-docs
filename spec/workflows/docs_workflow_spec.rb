# frozen_string_literal: true

require 'yaml'

RSpec.describe '.github/workflows/docs.yml' do
  let(:path) { File.join(SpecHelpers::ROOT, '.github', 'workflows', 'docs.yml') }
  let(:text) { File.read(path) }
  let(:workflow) { YAML.safe_load(text) }
  # Psych reads the bare key `on` as true.
  let(:triggers) { workflow.fetch('on') { workflow.fetch(true) } }
  let(:build) { workflow.fetch('jobs').fetch('build') }
  let(:deploy) { workflow.fetch('jobs').fetch('deploy') }
  let(:steps) { build.fetch('steps') }

  def step_using(action)
    steps.find { |step| step['uses'].to_s.start_with?("#{action}@") } || raise("no step uses #{action}")
  end

  def step_running(command)
    steps.find { |step| step['run'].to_s.include?(command) } || raise("no step runs #{command}")
  end

  context 'with triggers', requirement: 'the-docs-workflow-runs-on-main-refresh-schedule-request-and-pull-request',
                           scenario: 'triggers-and-concurrency-are-declared' do
    it 'runs on push to main, docs-refresh, the daily schedule, manual runs and pull requests, in group pages' do
      expect(triggers.dig('push', 'branches')).to eq(['main'])
      expect(triggers.dig('repository_dispatch', 'types')).to eq(['docs-refresh'])
      expect(triggers['schedule']).to eq([{ 'cron' => '23 5 * * *' }])
      expect(triggers).to include('workflow_dispatch', 'pull_request')
      expect(workflow['concurrency']).to eq('group' => 'pages', 'cancel-in-progress' => false)
    end
  end

  context 'with the dispatch payload', requirement: 'the-dispatch-payload-never-steers-the-build',
                                       scenario: 'no-step-reads-the-client-payload' do
    it 'never mentions client_payload' do
      expect(text).not_to include('client_payload')
    end
  end

  context 'with the app token', requirement: 'the-build-job-fetches-with-a-read-only-app-token',
                                scenario: 'build-job-permissions-and-token-are-least-privilege' do
    it 'mints a token scoped to the four repos with contents and actions read, used only by the fetch step' do
      token_step = step_using('actions/create-github-app-token')
      fetch_step = step_running('bin/fetch-sources')

      expect(build['permissions']).to eq('contents' => 'read')
      expect(text).to match(%r{uses: actions/create-github-app-token@[0-9a-f]{40} # v3})
      expect(token_step['with']).to eq(
        'client-id' => '${{ vars.DOCS_READER_APP_CLIENT_ID }}',
        'private-key' => '${{ secrets.DOCS_READER_APP_PRIVATE_KEY }}',
        'owner' => 'greeterhq',
        'repositories' => 'greeter-core,greeter-cli,greeter-http,greeter-acceptance',
        'permission-contents' => 'read',
        'permission-actions' => 'read'
      )
      expect(fetch_step['env']).to eq('GH_TOKEN' => "${{ steps.#{token_step.fetch('id')}.outputs.token }}")
      expect(steps.reject { |step| step.equal?(fetch_step) }.map { |step| step['env'].to_h.keys }.flatten)
        .not_to include('GH_TOKEN')
      expect(steps.filter_map { |step| step['run'] }).to all(satisfy { |run| !run.include?('${{') })
    end
  end

  context 'with the build steps', requirement: 'the-build-job-tests-builds-and-link-checks-before-uploading',
                                  scenario: 'build-steps-run-in-order' do
    it 'sets up Ruby 3.3 and runs fetch, rspec with the trace formatter, build, lychee and upload in order' do
      setup_ruby = step_using('ruby/setup-ruby')
      rspec = step_running('bundle exec rspec')
      lychee = step_running('lychee --offline --no-progress _site')
      upload = step_using('actions/upload-pages-artifact')
      ordered = [step_running('bin/fetch-sources'), rspec, step_running('bin/build-docs'), lychee, upload]

      expect(setup_ruby.dig('with', 'ruby-version')).to eq('3.3')
      expect(text).to include("The repo's .ruby-version (3.3.13) remains")
      expect(rspec['run']).to include('--format RepoTraceFormatter')
      expect(rspec['env']).to include('REPO_TRACE_PATH' => 'tmp/traces/greeter-docs/repo-trace.json')
      expect(lychee['run'].strip).to eq('lychee --offline --no-progress _site')
      expect(upload.dig('with', 'path')).to eq('_site')
      expect(ordered.map { |step| steps.index(step) }).to eq(ordered.map { |step| steps.index(step) }.sort)
      expect(steps.index(setup_ruby)).to be < steps.index(ordered.first)
      expect(ordered).to all(satisfy { |step| !step.key?('if') && !step.key?('continue-on-error') })
      expect(build).not_to include('if', 'continue-on-error')
    end
  end

  context 'with the deploy job',
          requirement: 'the-deploy-job-publishes-to-github-pages-except-for-pull-requests' do
    context 'when declared', scenario: 'deploy-job-is-declared' do
      it 'needs build, skips pull requests, uses github-pages and deploy-pages with pages and id-token write' do
        expect(deploy['needs']).to eq('build')
        expect(deploy['if']).to eq("github.event_name != 'pull_request'")
        expect(deploy['environment']).to eq('name' => 'github-pages',
                                            'url' => '${{ steps.deployment.outputs.page_url }}')
        expect(deploy['permissions']).to eq('pages' => 'write', 'id-token' => 'write')
        expect(deploy['steps'].map { |step| step['uses'].to_s }).to include(start_with('actions/deploy-pages@'))
      end
    end

    context 'when a pull request build fails',
            scenario: 'a-pull-request-with-an-uncovered-requirement-fails-before-merge' do
      it 'runs the build gate on pull requests and never deploys them' do
        build_docs = step_running('bin/build-docs')

        expect(triggers).to include('pull_request')
        expect(build).not_to include('if')
        expect(build_docs).not_to include('if', 'continue-on-error')
        expect(deploy['needs']).to eq('build')
        expect(deploy['if']).to include("github.event_name != 'pull_request'")
      end
    end
  end

  describe 'tools before the test step (design D10)' do
    it 'installs lychee exactly once, from a pinned release checked against a sha256, before rspec' do
      installs = steps.select { |step| step['run'].to_s.include?('lychee-x86_64-unknown-linux-gnu.tar.gz') }
      install = installs.first || raise('no lychee install step')
      rspec = step_running('bundle exec rspec')

      expect(installs.size).to eq(1)
      expect(steps.filter_map { |step| step['uses'] }).to all(satisfy { |uses| !uses.start_with?('lycheeverse/') })
      expect(steps.index(install)).to be < steps.index(rspec)
      expect(install.fetch('env')).to include('LYCHEE_VERSION' => match(/\Alychee-v\d+\.\d+\.\d+\z/),
                                              'LYCHEE_SHA256' => match(/\A[0-9a-f]{64}\z/))
      expect(install['run']).to include('sha256sum -c', 'GITHUB_PATH')
    end

    it 'lints with rubocop in a Lint step before rspec' do
      lint = steps.find { |step| step['name'] == 'Lint' } || raise('no Lint step')

      expect(lint['run']).to eq('bundle exec rubocop')
      expect(steps.index(lint)).to be < steps.index(step_running('bundle exec rspec'))
    end
  end

  describe 'hardening (design S3, S9)' do
    it 'grants nothing at the top level' do
      expect(workflow['permissions']).to eq({})
    end

    it 'pins every action to a full commit SHA' do
      uses = workflow['jobs'].values.flat_map { |job| job['steps'] }.filter_map { |step| step['uses'] }

      expect(uses).to all(match(/@[0-9a-f]{40}\z/))
    end

    it 'checks out without persisting credentials' do
      expect(step_using('actions/checkout').dig('with', 'persist-credentials')).to be(false)
    end

    it 'installs gems from the lockfile only' do
      env = workflow.fetch('env', {}).merge(build.fetch('env', {}))

      expect(env['BUNDLE_FROZEN']).to eq('true')
    end

    it 'resolves gems from a single rubygems.org source with no greeter-* gem' do
      gemfile = File.read(File.join(SpecHelpers::ROOT, 'Gemfile'))
      lockfile = File.read(File.join(SpecHelpers::ROOT, 'Gemfile.lock'))

      expect(gemfile.scan(/^\s*source\s+["']([^"']+)["']/).flatten).to eq(['https://rubygems.org'])
      expect(lockfile.scan(/^\s+remote: (.+)$/).flatten.uniq).to eq(['https://rubygems.org/'])
      expect(lockfile).not_to match(/^\s+greeter-/)
    end
  end
end
