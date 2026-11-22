# frozen_string_literal: true

module GreeterDocs
  # Ports of the hexagon: each module documents the one method an adapter
  # implements. Source errors are GreeterDocs::SourceError.
  module Ports
    # A ledger branch's greeterhq.ledger.v2 file.
    module LedgerSource
      # @param environment ["prod", "stage"]
      # @return [Domain::LedgerView] not_recorded when the ledger is missing
      def ledger(_environment) = raise(NotImplementedError, "#{self.class}#ledger")
    end
  end
end
