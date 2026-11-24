# frozen_string_literal: true

RSpec.describe 'GreeterDocs::Adapters::FileApiSource' do
  let(:fixture_path) { fixture('repos', 'greeter-http', 'openapi.yaml') }

  def api_from(path, commit: '5b818a2fa3f69d9a8bcc9c44f634c2ee2984670c')
    GreeterDocs::Adapters::FileApiSource.new(path: path, commit: commit).api
  end

  context 'when reading greeter-http openapi.yaml', requirement: 'the-api-description-is-read-from-greeter-http' do
    context 'with the real description', scenario: 'the-real-api-description-is-read' do
      it 'returns title, version and the POST /greetings operation with resolved parameters and responses' do
        api = api_from(fixture_path)
        operation = only_item(api.operations)

        expect([api.title, api.version]).to eq(%w[greeter-http 0.5.22])
        expect([operation.http_method, operation.path, operation.summary])
          .to eq(['post', '/greetings', 'Greet a guest and return the running count'])
        expect(operation.parameters.map { |p| p['name'] }).to eq(%w[Idempotency-Key X-Greeter-Synthetic])
        expect(operation.request_body.dig('content', 'application/json', 'schema', 'required')).to eq(['name'])
        expect(operation.responses.keys).to eq(%w[201 200 400 409 413 422 500 503])
        expect(operation.responses['503']['headers'].keys)
          .to eq(%w[X-Greeter-Version X-Greeter-Core-Version Retry-After])
        expect(operation.responses['201'].dig('headers', 'X-Greeter-Version', 'description'))
          .to start_with('The service version')
      end
    end

    context 'with a custom YAML tag', scenario: 'a-yaml-file-using-a-custom-tag-is-refused-and-named' do
      it 'raises a SourceError naming openapi.yaml and creates no object' do
        Dir.mktmpdir do |dir|
          path = write_file(File.join(dir, 'openapi.yaml'), <<~YAML)
            openapi: 3.1.0
            info: !ruby/object:OpenStruct
              title: pwned
          YAML

          expect { api_from(path) }.to raise_error(GreeterDocs::SourceError, /openapi\.yaml/)
        end
      end
    end
  end

  describe 'other inputs' do
    it 'keeps the original bytes and the source commit' do
      api = api_from(fixture_path)

      expect(api.raw).to eq(File.binread(fixture_path))
      expect(api.commit).to eq('5b818a2fa3f69d9a8bcc9c44f634c2ee2984670c')
    end

    it 'raises a SourceError naming the file when it is missing' do
      expect { api_from('/nonexistent/openapi.yaml') }.to raise_error(GreeterDocs::SourceError, /openapi\.yaml/)
    end
  end
end
