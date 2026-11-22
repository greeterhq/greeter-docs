# frozen_string_literal: true

module GreeterDocs
  # Ports of the hexagon: each module documents the one method an adapter
  # implements. Source errors are GreeterDocs::SourceError.
  module Ports
    module SloSource
      # @return [Object] :not_yet_available until a real source exists
      def slos = raise(NotImplementedError, "#{self.class}#slos")
    end
  end
end
