# frozen_string_literal: true

module GreeterDocs
  module Adapters
    # Reads requirements and scenarios from `openspec/specs/**/spec.md` headings
    # in the producers' shallow clones and in the greeter-docs checkout, using
    # the shared slug rule. Change deltas under openspec/changes are not read.
    class GitSpecSource
      include Ports::SpecSource

      SELF = 'greeter-docs'
      REQUIREMENT = /\A### Requirement: (.+?)\s*\z/
      SCENARIO = /\A#### Scenario: (.+?)\s*\z/
      FENCE = /\A\s*(```|~~~)/
      TAGS = File.join('openspec', 'requirement-tags.yml')

      def initialize(clones_root:, workspace_root:, producers:)
        @clones_root = clones_root
        @workspace_root = workspace_root
        @producers = producers
      end

      def repos
        @producers.map { |name| repo(name, File.join(@clones_root, name)) } + [repo(SELF, @workspace_root)]
      end

      private

      def repo(name, root)
        specs_root = File.join(root, 'openspec', 'specs')
        requirements = Dir.glob(File.join(specs_root, '**', 'spec.md')).flat_map do |path|
          capability = File.dirname(path).delete_prefix("#{specs_root}/")
          parse(File.read(path), capability, path.delete_prefix("#{root}/"))
        end
        Domain::Repo.new(name: name, requirements: requirements, requirement_tags: tags(name, root))
      end

      def parse(text, capability, spec_path)
        found = []
        fenced = false
        text.each_line do |line|
          fenced = !fenced if FENCE.match?(line)
          next if fenced

          heading(line, capability, spec_path, found)
        end
        found.map { |req| Domain::Requirement.new(**req, scenarios: req[:scenarios].freeze) }
      end

      def heading(line, capability, spec_path, found)
        if (title = line[REQUIREMENT, 1])
          found << { slug: Domain::Slug.call(title), title: title, capability: capability, spec_path: spec_path,
                     scenarios: [] }
        elsif (title = line[SCENARIO, 1]) && found.any?
          found.last[:scenarios] << Domain::Scenario.new(slug: Domain::Slug.call(title), title: title)
        end
      end

      def tags(name, root)
        path = File.join(root, TAGS)
        return {} unless File.file?(path)

        label = "#{name}/#{TAGS}"
        map = Limits.yaml(Limits.read(path, label), label)
        unless map.is_a?(Hash) && map.all? { |key, value| key.is_a?(String) && value.is_a?(String) }
          raise SourceError, "#{label}: must map heading slugs to ledger keys"
        end

        map
      end
    end
  end
end
