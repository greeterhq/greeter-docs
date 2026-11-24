# frozen_string_literal: true

module GreeterDocs
  module Domain
    # A requirement on main, named by repo, capability, slug and spec file.
    RequirementRef = Data.define(:repo, :capability, :requirement, :spec_path) do
      def to_s
        [repo, capability, requirement, spec_path].join(' ')
      end
    end
    Violation = RequirementRef

    # Decides which requirements on main lack a passing scenario.
    #
    # - A requirement not in its repo's tag map is covered when the repo's CI
    #   trace or prod smoke trace has a result for its slug with status "passed".
    # - A tag-mapped requirement ignores the trace. It is covered when the prod
    #   ledger has a channel "passed" for its key, and is not yet recorded (not a
    #   violation) while the prod ledger is missing. Stage never counts.
    class CoverageRule
      def violations(model)
        sorted(judge(model).select { |_ref, verdict| verdict == :uncovered }.map(&:first))
      end

      def not_yet_recorded(model)
        sorted(judge(model).select { |_ref, verdict| verdict == :not_yet_recorded }.map(&:first))
      end

      def summary(model)
        counts = judge(model).map(&:last).tally
        { covered: counts.fetch(:covered, 0), uncovered: counts.fetch(:uncovered, 0),
          not_yet_recorded: counts.fetch(:not_yet_recorded, 0) }
      end

      # The verdict for one requirement: :covered, :uncovered or :not_yet_recorded.
      def verdict(model, repo, requirement)
        key = repo.requirement_tags[requirement.slug]
        return ledger_verdict(model.ledgers['prod'], key) if key

        passed_slugs(model, repo.name).include?(requirement.slug) ? :covered : :uncovered
      end

      private

      def judge(model)
        model.repos.flat_map do |repo|
          repo.requirements.map do |requirement|
            ref = RequirementRef.new(repo: repo.name, capability: requirement.capability,
                                     requirement: requirement.slug, spec_path: requirement.spec_path)
            [ref, verdict(model, repo, requirement)]
          end
        end
      end

      def ledger_verdict(prod, key)
        return :not_yet_recorded unless prod&.recorded?

        prod.passed?(key) ? :covered : :uncovered
      end

      # Requirement slugs with a passed result in the repo's CI or prod smoke trace.
      def passed_slugs(model, repo_name)
        trace_passes(model.traces[repo_name]) + trace_passes(model.deployed_traces[repo_name])
      end

      def trace_passes(trace)
        return [] unless trace

        trace.results.select { |result| result.status == 'passed' }.map(&:requirement)
      end

      def sorted(refs)
        refs.sort_by { |ref| [ref.repo, ref.capability, ref.requirement] }
      end
    end
  end
end
