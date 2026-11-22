# frozen_string_literal: true

module GreeterDocs
  # Ports of the hexagon: each module documents the one method an adapter
  # implements. Source errors are GreeterDocs::SourceError.
  module Ports
    # greeter-http's OpenAPI description.
    module ApiSource
      # @return [Domain::ApiDescription]
      def api = raise(NotImplementedError, "#{self.class}#api")
    end
  end
end
