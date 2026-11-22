# frozen_string_literal: true

require 'net/http'

# Design S4 (unbounded inputs) and the API7 note (external $ref never fetched).
RSpec.describe 'source input limits' do
  let(:limit) { 5 * 1024 * 1024 }

  around do |example|
    Dir.mktmpdir('greeter-docs-limits') do |dir|
      @dir = dir
      example.run
    end
  end

  attr_reader :dir

  def api_from(yaml)
    path = write_file(File.join(dir, 'openapi.yaml'), yaml)
    GreeterDocs::Adapters::FileApiSource.new(path: path, commit: 'c' * 40).api
  end

  it 'refuses a trace larger than 5 MiB, naming the file' do
    write_file(File.join(dir, 'tmp', 'traces', 'greeter-core', 'repo-trace.json'), " #{'x' * limit}")

    expect { GreeterDocs::Adapters::ArtifactTraceSource.new(workspace_root: dir).trace('greeter-core') }
      .to raise_error(GreeterDocs::SourceError, %r{tmp/traces/greeter-core/repo-trace\.json})
  end

  it 'refuses a ledger body larger than 5 MiB, naming the environment' do
    source = GreeterDocs::Adapters::RawLedgerSource.new(fetcher: ledger_fetcher('prod' => [200, 'x' * (limit + 1)]))

    expect { source.ledger('prod') }.to raise_error(GreeterDocs::SourceError, /prod/)
  end

  it 'refuses an openapi.yaml larger than 5 MiB' do
    expect { api_from("openapi: 3.1.0\n# #{'x' * limit}\n") }.to raise_error(GreeterDocs::SourceError, /openapi\.yaml/)
  end

  it 'refuses YAML aliases in openapi.yaml' do
    yaml = <<~YAML
      openapi: 3.1.0
      info: &info
        title: t
        version: '1'
      x-copy: *info
      paths: {}
    YAML

    expect { api_from(yaml) }.to raise_error(GreeterDocs::SourceError, /openapi\.yaml/)
  end

  it 'refuses YAML aliases in requirement-tags.yml, naming the file' do
    repo_dir = File.join(dir, 'repos', 'greeter-acceptance')
    write_file(File.join(repo_dir, 'openspec', 'specs', 'greeting', 'spec.md'), "### Requirement: A\n")
    write_file(File.join(repo_dir, 'openspec', 'requirement-tags.yml'), "a: &x greeting-happy\nb: *x\n")
    source = GreeterDocs::Adapters::GitSpecSource.new(clones_root: File.join(dir, 'repos'), workspace_root: dir,
                                                      producers: ['greeter-acceptance'])

    expect { source.repos }.to raise_error(GreeterDocs::SourceError, /requirement-tags\.yml/)
  end

  it 'refuses a $ref cycle instead of recursing forever' do
    yaml = <<~YAML
      openapi: 3.1.0
      info: { title: t, version: '1' }
      paths:
        /x:
          get:
            summary: s
            parameters:
              - $ref: '#/components/parameters/A'
            responses: {}
      components:
        parameters:
          A: { $ref: '#/components/parameters/B' }
          B: { $ref: '#/components/parameters/A' }
    YAML

    expect { api_from(yaml) }.to raise_error(GreeterDocs::SourceError, /\$ref/)
  end

  it 'shows a non-local $ref as text and never fetches it' do
    allow(Net::HTTP).to receive(:start).and_raise('network used')
    allow(Net::HTTP).to receive(:get).and_raise('network used')
    yaml = <<~YAML
      openapi: 3.1.0
      info: { title: t, version: '1' }
      paths:
        /x:
          get:
            summary: s
            parameters:
              - $ref: 'https://attacker.example/param.yaml'
            responses: {}
    YAML

    operation = api_from(yaml).operations.sole

    expect(operation.parameters).to eq([{ '$ref' => 'https://attacker.example/param.yaml' }])
    expect(Net::HTTP).not_to have_received(:start)
    expect(Net::HTTP).not_to have_received(:get)
  end

  it 'uses 10 second open and read timeouts and follows no redirects in the default ledger fetcher' do
    allow(Net::HTTP).to receive(:new)
    allow(Net::HTTP).to receive(:start)
    fetcher = GreeterDocs::Adapters::RawLedgerSource.default_fetcher

    expect([fetcher.open_timeout, fetcher.read_timeout, fetcher.follows_redirects?]).to eq([10, 10, false])
    expect(Net::HTTP).not_to have_received(:new)
    expect(Net::HTTP).not_to have_received(:start)
  end
end
