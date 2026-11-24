# frozen_string_literal: true

module GreeterDocs
  module Domain
    # One environment's greeterhq.ledger.v2 file, or the fact that it is not
    # yet recorded.
    class LedgerView
      Channel = Data.define(:name, :verification, :version, :run_id)

      attr_reader :environment, :suite_version, :channels, :requirements

      def self.recorded(environment:, suite_version:, channels:, requirements:)
        new(environment: environment, recorded: true, suite_version: suite_version, channels: channels,
            requirements: requirements)
      end

      def self.not_recorded(environment)
        new(environment: environment, recorded: false, suite_version: nil, channels: {}, requirements: {})
      end

      def initialize(environment:, recorded:, suite_version:, channels:, requirements:)
        @environment = environment
        @recorded = recorded
        @suite_version = suite_version
        @channels = channels.freeze
        @requirements = requirements.freeze
        freeze
      end

      def recorded?
        @recorded
      end

      # True when at least one channel passed the requirement key.
      def passed?(key)
        requirements.fetch(key, {}).value?('passed')
      end
    end
  end
end
