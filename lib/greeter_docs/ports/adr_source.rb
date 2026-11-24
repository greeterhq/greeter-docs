# frozen_string_literal: true

module GreeterDocs
  # Ports of the hexagon: each module documents the one method an adapter
  # implements. Source errors are GreeterDocs::SourceError.
  module Ports
    module AdrSource
      # @return [Array<Domain::Adr>] ordered by repo and file name
      def adrs = raise(NotImplementedError, "#{self.class}#adrs")
    end
  end
end
