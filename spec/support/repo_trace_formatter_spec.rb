# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe 'RepoTraceFormatter (copied from greeter-cli)' do
  context 'when greeter-docs runs its suite', requirement: 'greeter-docs-records-its-own-trace',
                                              scenario: 'the-suite-writes-a-v1-trace-for-greeter-docs' do
    it 'writes a v1 trace for greeter-docs with one result per tagged example and only the five result keys' do
      Dir.mktmpdir('greeter-docs-trace') do |dir|
        path = File.join(dir, 'repo-trace.json')
        env = { 'REPO_TRACE_PATH' => path, 'GITHUB_SHA' => 'b' * 40, 'GITHUB_RUN_ID' => '4242' }
        command = [RbConfig.ruby, '-S', 'rspec', '--options', File::NULL, '--require', './spec/spec_helper',
                   '--format', 'RepoTraceFormatter', 'spec/fixtures/trace_suite/sample_suite.rb']

        _out, err, status = Open3.capture3(env, *command, chdir: SpecHelpers::ROOT)
        expect(status).to be_success, err

        document = JSON.parse(File.read(path))
        expect(document.slice('schema', 'repo', 'sha', 'run_id'))
          .to eq('schema' => 'greeterhq.repo-trace.v1', 'repo' => 'greeter-docs', 'sha' => 'b' * 40,
                 'run_id' => '4242')
        expect(document['recorded_at']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
        expect(document['results'].map { |r| [r['scenario'], r['status']] })
          .to contain_exactly(%w[fixture-passing passed], %w[fixture-skipped skipped])
        expect(document['results'].map(&:keys).uniq).to eq([%w[requirement scenario status source location]])
        expect(document['results'].map { |r| r['location'] })
          .to all(start_with('spec/fixtures/trace_suite/sample_suite.rb:'))
      end
    end
  end
end
