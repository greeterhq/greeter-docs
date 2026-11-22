# frozen_string_literal: true

module GreeterDocs
  # Ports of the hexagon: each module documents the one method an adapter
  # implements. Source errors are GreeterDocs::SourceError.
  module Ports
    module DiagramSource
      # @return [Array<Domain::Diagram>] ordered by file name
      def diagrams = raise(NotImplementedError, "#{self.class}#diagrams")
    end
  end
end
