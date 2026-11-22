# frozen_string_literal: true

module GreeterDocs
  # The build use case: read every source through its port, apply the coverage
  # rule, and publish only when there is no source error and no violation.
  # Returns the exit code and the lines to print; it prints nothing itself.
  class Build
    Result = Data.define(:exit_code, :lines)

    PORTS = %i[spec_source trace_source ledger_source api_source adr_source diagram_source contract_source
               slo_source publisher].freeze
    ENVIRONMENTS = %w[prod stage].freeze

    # Takes each port listed in PORTS, plus clock: (a callable returning a Time).
    def initialize(clock:, **ports)
      missing = PORTS - ports.keys
      extra = ports.keys - PORTS
      raise ArgumentError, "missing #{missing.join(', ')}" if missing.any?
      raise ArgumentError, "unknown #{extra.join(', ')}" if extra.any?

      @ports = ports
      @clock = clock
    end

    def call
      errors = []
      model = gather(errors)
      return failure(errors) if errors.any?

      violations = Domain::CoverageRule.new.violations(model)
      return failure(violations.map(&:to_s)) if violations.any?

      @ports.fetch(:publisher).publish(model)
      Result.new(exit_code: 0, lines: [])
    end

    private

    def gather(errors)
      repos = attempt(errors, []) { port(:spec_source).repos }
      Domain::DocsModel.new(repos: repos, traces: traces(repos, errors), ledgers: ledgers(errors),
                            **documents(errors), built_at: @clock.call)
    end

    def documents(errors)
      { api: attempt(errors) { port(:api_source).api },
        adrs: attempt(errors, []) { port(:adr_source).adrs },
        diagrams: attempt(errors, []) { port(:diagram_source).diagrams },
        contracts: port(:contract_source).contracts, slos: port(:slo_source).slos }
    end

    def traces(repos, errors)
      repos.filter_map { |repo| attempt(errors) { port(:trace_source).trace(repo.name) } }
           .to_h { |trace| [trace.repo, trace] }
    end

    def ledgers(errors)
      ENVIRONMENTS.filter_map { |env| attempt(errors) { port(:ledger_source).ledger(env) } }
                  .to_h { |ledger| [ledger.environment, ledger] }
    end

    def attempt(errors, fallback = nil)
      yield
    rescue SourceError => e
      errors << e.message
      fallback
    end

    def port(name)
      @ports.fetch(name)
    end

    def failure(lines)
      Result.new(exit_code: 1, lines: lines.map { |line| LogSafe.line(line) })
    end
  end
end
