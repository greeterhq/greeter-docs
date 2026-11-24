# frozen_string_literal: true

module GreeterDocs
  # Ports of the hexagon: each module documents the one method an adapter
  # implements. Source errors are GreeterDocs::SourceError.
  module Ports
    # A repo's greeterhq.repo-trace.v1 file.
    module TraceSource
      # @return [Domain::Trace, nil] nil when the repo has no trace
      def trace(_repo) = raise(NotImplementedError, "#{self.class}#trace")
    end
  end
end
