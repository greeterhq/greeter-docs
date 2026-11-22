# frozen_string_literal: true

module GreeterDocs
  module Domain
    Scenario = Data.define(:slug, :title)

    # One `### Requirement:` heading on main, with the scenarios below it.
    # spec_path is relative to the repo root.
    Requirement = Data.define(:slug, :title, :capability, :spec_path, :scenarios)

    # requirement_tags maps a requirement slug to the prod ledger key that
    # covers it (openspec/requirement-tags.yml).
    Repo = Data.define(:name, :requirements, :requirement_tags) do
      def initialize(name:, requirements:, requirement_tags: {})
        super
      end
    end

    Result = Data.define(:requirement, :scenario, :status, :source, :location)

    # A repo's greeterhq.repo-trace.v1 file.
    Trace = Data.define(:repo, :sha, :run_id, :recorded_at, :results)

    Adr = Data.define(:repo, :file_name, :title, :body) do
      def slug
        file_name.delete_suffix('.md')
      end
    end

    Diagram = Data.define(:name, :source)

    ApiDescription = Data.define(:title, :version, :description, :commit, :raw, :operations)
    ApiDescription::Operation = Data.define(:http_method, :path, :summary, :parameters, :request_body, :responses)

    DocsModel = Data.define(:repos, :traces, :ledgers, :api, :adrs, :diagrams, :contracts, :slos, :built_at)
  end
end
