# frozen_string_literal: true

RSpec.describe 'GreeterDocs::Adapters::FileAdrSource and FileDiagramSource' do
  around do |example|
    Dir.mktmpdir('greeter-docs-adr') do |dir|
      @dir = dir
      example.run
    end
  end

  attr_reader :dir

  context 'when reading docs folders', requirement: 'adrs-and-diagrams-are-read-from-docs-folders' do
    context 'with ADRs in both repos', scenario: 'adrs-from-both-repos-are-returned-with-their-titles' do
      it 'returns four ADRs with repo, file name, title and body, ordered by repo and file name' do
        docs_adr = File.join(dir, 'docs', 'adr')
        write_file(File.join(docs_adr, '0002-second.md'), "# 2. Second decision\n\nBody two.\n")
        write_file(File.join(docs_adr, '0001-first.md'), "Preamble\n\n# 1. First decision\n\nBody one.\n")
        source = GreeterDocs::Adapters::FileAdrSource.new(
          roots: { 'greeter-http' => fixture('repos', 'greeter-http', 'docs', 'adr'), 'greeter-docs' => docs_adr }
        )

        adrs = source.adrs

        expect(adrs.map { |adr| [adr.repo, adr.file_name, adr.title] }).to eq(
          [['greeter-docs', '0001-first.md', '1. First decision'],
           ['greeter-docs', '0002-second.md', '2. Second decision'],
           ['greeter-http', '0001-record-architecture-decisions.md', '1. Record architecture decisions'],
           ['greeter-http', '0002-openapi-authored-and-validated-not-generated.md',
            '2. The OpenAPI description is authored and validated, not generated']]
        )
        expect(adrs.first.body).to include('Body one.')
      end
    end

    context 'with two diagrams', scenario: 'diagrams-are-returned-in-file-name-order' do
      it 'returns them in file-name order with their Mermaid text' do
        write_file(File.join(dir, 'c4-context.mmd'), "C4Context\n  title Context\n")
        write_file(File.join(dir, 'c4-container.mmd'), "C4Container\n  title Containers\n")
        write_file(File.join(dir, 'notes.txt'), 'not a diagram')

        diagrams = GreeterDocs::Adapters::FileDiagramSource.new(dir: dir).diagrams

        expect(diagrams.map(&:name)).to eq(%w[c4-container c4-context])
        expect(diagrams.first.source).to start_with('C4Container')
      end
    end
  end

  describe 'missing folders' do
    it 'returns no ADRs for a repo whose folder does not exist' do
      source = GreeterDocs::Adapters::FileAdrSource.new(roots: { 'greeter-docs' => File.join(dir, 'missing') })

      expect(source.adrs).to eq([])
    end
  end
end
