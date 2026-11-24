# frozen_string_literal: true

RSpec.describe 'GreeterDocs::Adapters::GitSpecSource' do
  def source(clones_root, workspace_root)
    GreeterDocs::Adapters::GitSpecSource.new(clones_root: clones_root, workspace_root: workspace_root,
                                             producers: SpecHelpers::PRODUCERS)
  end

  def repo_named(repos, name)
    repos.find { |candidate| candidate.name == name } || raise("no repo #{name}")
  end

  around do |example|
    Dir.mktmpdir('greeter-docs-self') do |workspace|
      @workspace = workspace
      with_fetched_workspace do |root|
        @clones = File.join(root, 'tmp', 'repos')
        example.run
      end
    end
  end

  attr_reader :workspace, :clones

  context 'when reading main spec headings',
          requirement: 'requirements-and-scenarios-are-read-from-main-spec-headings' do
    context 'with a nested capability', scenario: 'headings-in-a-nested-capability-are-read' do
      it 'returns the capability path, requirements in file order with their scenarios, and the spec path' do
        cli = repo_named(source(clones, workspace).repos, 'greeter-cli')
        tooling = cli.requirements.select { |req| req.capability == 'tooling/live-docs-traceability' }

        expect(tooling.first(2).map(&:slug)).to eq(%w[every-requirement-has-a-tagged-test
                                                      tagged-tests-must-match-a-requirement-and-scenario])
        expect(tooling.first.scenarios.map(&:slug)).to eq(%w[slug-rule-turns-headings-into-slugs
                                                             requirement-with-no-tagged-test-fails-and-is-named])
        expect(tooling.first(2).last.scenarios.map(&:slug)).to eq(
          %w[unknown-requirement-slug-fails-and-is-named scenario-slug-is-matched-only-within-its-requirement
             requirements-in-in-flight-changes-are-known fixture-files-are-not-scanned]
        )
        expect(tooling.map(&:spec_path).uniq).to eq(['openspec/specs/tooling/live-docs-traceability/spec.md'])
      end
    end

    context 'with other heading levels and fenced code', scenario: 'other-heading-levels-are-not-requirements' do
      it 'returns only level-3 requirement and level-4 scenario headings outside code fences' do
        write_file(File.join(workspace, 'openspec', 'specs', 'site', 'spec.md'), <<~MD)
          # site Specification

          ## Requirements

          ### Requirement: Real requirement
          Text.

          ##### Note

          ```markdown
          ### Requirement: Fake
          #### Scenario: Fake scenario
          ```

          #### Scenario: Real scenario
          - **WHEN** x
          - **THEN** y
        MD

        docs = repo_named(source(clones, workspace).repos, 'greeter-docs')

        expect(docs.requirements.map(&:slug)).to eq(['real-requirement'])
        expect(docs.requirements.first.scenarios.map(&:slug)).to eq(['real-scenario'])
      end
    end
  end

  context 'when a requirement exists only in a change', requirement: 'only-requirements-on-main-are-checked',
                                                        scenario: 'a-requirement-only-in-a-change-is-not-checked' do
    it 'leaves it out of the model, so the coverage rule reports no violation for it' do
      write_file(File.join(clones, 'greeter-core', 'openspec', 'changes', 'x', 'specs', 'cap', 'spec.md'), <<~MD)
        ## ADDED Requirements

        ### Requirement: Only in a change

        #### Scenario: Not yet on main
      MD

      repos = source(clones, workspace).repos
      core = repo_named(repos, 'greeter-core')
      docs_model = model(repos: [core])

      expect(core.requirements.map(&:slug)).not_to include('only-in-a-change')
      expect(GreeterDocs::Domain::CoverageRule.new.violations(docs_model).map(&:requirement))
        .not_to include('only-in-a-change')
    end
  end

  describe 'repos and tag maps' do
    it 'returns the four producers from their clones and greeter-docs from the workspace' do
      expect(source(clones, workspace).repos.map(&:name))
        .to eq(%w[greeter-core greeter-cli greeter-http greeter-acceptance greeter-docs])
    end

    it "reads greeter-acceptance's requirement-tags.yml as slug -> ledger key" do
      acceptance = repo_named(source(clones, workspace).repos, 'greeter-acceptance')

      expect(acceptance.requirement_tags).to include('a-channel-greets-a-valid-guest' => 'greeting-happy')
      expect(acceptance.requirement_tags.size).to eq(5)
    end

    it 'gives repos without a tag map an empty one' do
      expect(repo_named(source(clones, workspace).repos, 'greeter-core').requirement_tags).to eq({})
    end
  end
end
