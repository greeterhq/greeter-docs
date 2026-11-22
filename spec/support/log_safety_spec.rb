# frozen_string_literal: true

require 'stringio'

# Design S1 (workflow-command and newline injection in Actions logs) and S7
# (sourced values echoed in errors).
RSpec.describe 'GreeterDocs::LogSafe' do
  subject(:log_safe) { GreeterDocs::LogSafe }

  describe '.line' do
    it 'never lets a line start a workflow command' do
      ['::add-mask::secret', '::stop-commands::token', '::error file=x::boom'].each do |input|
        expect(log_safe.line(input)).not_to start_with('::')
      end
    end

    it 'replaces newlines and other control characters so one value cannot forge another line' do
      safe = log_safe.line("first\n::warning::forged\r\e[31mred\u0000")

      expect(safe).not_to match(/[\u0000-\u001f\u007f]/)
      expect(safe).to include("\uFFFD")
    end
  end

  describe '.value' do
    it 'echoes slugs and repo-relative paths' do
      expect(log_safe.value('greeter-http')).to eq('greeter-http')
      expect(log_safe.value('tmp/traces/greeter-cli/repo-trace.json')).to eq('tmp/traces/greeter-cli/repo-trace.json')
    end

    it 'replaces anything else with (invalid value)' do
      ['Alice Smith', "greeter-http\n::add-mask::x", '../../etc/passwd', ''].each do |input|
        expect(log_safe.value(input)).to eq('(invalid value)')
      end
    end

    it 'truncates long values to 200 characters' do
      expect(log_safe.value('a' * 300).length).to be <= 201
    end
  end

  describe 'use by the sources and scripts' do
    it 'does not echo a non-slug repo value from a trace' do
      with_fetched_workspace do |root|
        path = File.join(root, 'tmp', 'traces', 'greeter-cli', 'repo-trace.json')
        write_json(path, JSON.parse(File.read(path)).merge('repo' => "::stop-commands::x\nAlice Smith"))

        expect { GreeterDocs::Adapters::ArtifactTraceSource.new(workspace_root: root).trace('greeter-cli') }
          .to raise_error(GreeterDocs::SourceError) { |error|
            expect(error.message).to include('(invalid value)')
            expect(error.message).not_to include('::stop-commands', 'Alice Smith', "\n")
          }
      end
    end

    it 'prints gh stderr from bin/fetch-sources with no workflow-command lines' do
      Dir.mktmpdir do |root|
        err = StringIO.new
        runner = SpecHelpers::StubRunner.new { |_argv| ['', "::error::boom\n::add-mask::x", false] }

        GreeterDocs::FetchSources.new(runner: runner, root: root, env: {}, out: StringIO.new, err: err).call

        expect(err.string.lines).to all(satisfy { |line| !line.start_with?('::') })
      end
    end
  end
end
