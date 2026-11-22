# frozen_string_literal: true

RSpec.describe 'GreeterDocs::Adapters::ArtifactTraceSource' do
  around do |example|
    with_fetched_workspace do |root|
      @root = root
      example.run
    end
  end

  attr_reader :root

  def source
    GreeterDocs::Adapters::ArtifactTraceSource.new(workspace_root: root)
  end

  def trace_path(repo)
    File.join(root, 'tmp', 'traces', repo, 'repo-trace.json')
  end

  def rewrite_trace(repo)
    document = JSON.parse(File.read(trace_path(repo)))
    yield document
    write_json(trace_path(repo), document)
  end

  context 'when validating repo traces', requirement: 'repo-traces-are-validated-before-use' do
    context 'with the real greeter-http trace', scenario: 'a-real-trace-is-read' do
      it 'returns every result and the run metadata' do
        trace = source.trace('greeter-http')

        expect([trace.repo, trace.sha, trace.run_id, trace.recorded_at])
          .to eq(['greeter-http', '5b818a2fa3f69d9a8bcc9c44f634c2ee2984670c', '44622828436', '2026-11-19T21:51:18Z'])
        expect(trace.results.size).to eq(181)
        skipped = trace.results.find { |r| r.status == 'skipped' }
        expect([skipped.requirement, skipped.scenario, skipped.source, skipped.location])
          .to eq(%w[deployed-stage-exposes-version-headers smoke-check-on-a-deployed-stage cucumber
                    features/version_headers.feature:7])
      end
    end

    context 'with the wrong schema', scenario: 'a-trace-with-the-wrong-schema-fails-the-build-and-is-named' do
      it 'raises a SourceError naming the file and the schema field' do
        rewrite_trace('greeter-core') { |doc| doc['schema'] = 'greeterhq.traceability.v1' }

        expect { source.trace('greeter-core') }.to raise_error(GreeterDocs::SourceError) { |error|
          expect(error.message).to include('tmp/traces/greeter-core/repo-trace.json', 'schema')
        }
      end
    end

    context 'with another repo', scenario: 'a-trace-for-another-repo-fails-the-build-and-is-named' do
      it 'raises a SourceError naming the file, the directory repo and the file repo' do
        rewrite_trace('greeter-cli') { |doc| doc['repo'] = 'greeter-http' }

        expect { source.trace('greeter-cli') }.to raise_error(GreeterDocs::SourceError) { |error|
          expect(error.message).to include('tmp/traces/greeter-cli/repo-trace.json', 'greeter-cli', 'greeter-http')
        }
      end
    end

    context 'with malformed JSON', scenario: 'malformed-json-fails-the-build-and-is-named' do
      it 'raises a SourceError naming the file' do
        write_file(trace_path('greeter-http'), '{"schema": ')

        expect { source.trace('greeter-http') }.to raise_error(GreeterDocs::SourceError,
                                                               %r{tmp/traces/greeter-http/repo-trace\.json})
      end
    end
  end

  describe 'other inputs' do
    it 'returns nil for a repo with no trace file' do
      FileUtils.rm_rf(File.join(root, 'tmp', 'traces', 'greeter-cli'))

      expect(source.trace('greeter-cli')).to be_nil
    end

    it 'refuses a result that is not an object with string requirement, scenario and status' do
      rewrite_trace('greeter-core') { |doc| doc['results'] << { 'requirement' => 1 } }

      expect { source.trace('greeter-core') }.to raise_error(GreeterDocs::SourceError, /results/)
    end

    it 'reads every captured producer trace' do
      counts = SpecHelpers::PRODUCERS.to_h { |repo| [repo, source.trace(repo).results.size] }

      expect(counts).to eq('greeter-core' => 52, 'greeter-cli' => 93, 'greeter-http' => 181,
                           'greeter-acceptance' => 151)
    end
  end
end
