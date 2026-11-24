# frozen_string_literal: true

module GreeterDocs
  module Adapters
    class NullContractSource
      include Ports::ContractSource

      def contracts = :not_yet_available
    end
  end
end
