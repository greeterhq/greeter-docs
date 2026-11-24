# frozen_string_literal: true

# Checks greeter-docs' own tagging rule against the loaded suite: every
# `#### Scenario:` in this repo's main specs and in-flight changes has exactly
# one example tagged with its requirement and scenario slugs, and no example is
# tagged with a slug that is not a heading.
RSpec.describe 'greeter-docs scenario coverage' do
  def slug(text)
    text.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
  end

  def spec_files
    Dir[File.join(SpecHelpers::ROOT, 'openspec', 'specs', '**', 'spec.md')] +
      Dir[File.join(SpecHelpers::ROOT, 'openspec', 'changes', '*', 'specs', '**', 'spec.md')]
      .reject { |path| path.include?('/changes/archive/') }
  end

  # [requirement-slug, scenario-slug] pairs from the headings, outside code fences.
  def heading_pairs
    spec_files.flat_map do |path|
      current = nil
      fenced = false
      File.readlines(path).filter_map do |line|
        fenced = !fenced if line.start_with?('```')
        next if fenced

        requirement_heading = line[/\A### Requirement: (.+)$/, 1]
        scenario_heading = line[/\A#### Scenario: (.+)$/, 1]
        current = slug(requirement_heading) if requirement_heading
        [current, slug(scenario_heading)] if scenario_heading
      end
    end.uniq
  end

  def tagged_pairs
    RSpec.world.example_groups.flat_map(&:descendants).flat_map(&:examples)
         .map { |example| example.metadata.values_at(:requirement, :scenario) }
         .select { |(req, scen)| req && scen }
  end

  def full_run?
    loaded = RSpec.configuration.files_to_run.map { |path| File.expand_path(path) }
    Dir[File.join(SpecHelpers::ROOT, 'spec', '**', '*_spec.rb')].all? { |path| loaded.include?(path) }
  end

  context 'when the whole suite is loaded', requirement: 'greeter-docs-records-its-own-trace',
                                            scenario: 'every-greeter-docs-scenario-has-exactly-one-tagged-example' do
    it 'has exactly one tagged example per scenario and no tag outside the headings' do
      skip 'partial run: only a full suite run can check scenario coverage' unless full_run?

      counts = tagged_pairs.tally
      missing = heading_pairs.reject { |pair| counts.key?(pair) }
      repeated = heading_pairs.select { |pair| counts.fetch(pair, 0) > 1 }
      unknown = counts.keys - heading_pairs

      expect([missing, repeated, unknown]).to eq([[], [], []]),
                                              "missing: #{missing.map { |p| p.join(' / ') }}\n" \
                                              "repeated: #{repeated.map { |p| p.join(' / ') }}\n" \
                                              "unknown: #{unknown.map { |p| p.join(' / ') }}"
    end
  end
end
