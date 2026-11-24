# frozen_string_literal: true

module GreeterDocs
  # Ports of the hexagon: each module documents the one method an adapter
  # implements. Source errors are GreeterDocs::SourceError.
  module Ports
    # Writes the site for a docs model.
    module Publisher
      def publish(_model) = raise(NotImplementedError, "#{self.class}#publish")
    end
  end
end
