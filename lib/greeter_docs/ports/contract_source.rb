# frozen_string_literal: true

module GreeterDocs
  # Ports of the hexagon: each module documents the one method an adapter
  # implements. Source errors are GreeterDocs::SourceError.
  module Ports
    module ContractSource
      # @return [Object] :not_yet_available until a real source exists
      def contracts = raise(NotImplementedError, "#{self.class}#contracts")
    end
  end
end
