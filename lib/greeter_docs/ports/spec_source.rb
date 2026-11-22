# frozen_string_literal: true

module GreeterDocs
  # Ports of the hexagon: each module documents the one method an adapter
  # implements. Source errors are GreeterDocs::SourceError.
  module Ports
    # Requirements and scenarios on main, per repo.
    module SpecSource
      # @return [Array<Domain::Repo>] the producers first, then greeter-docs
      def repos = raise(NotImplementedError, "#{self.class}#repos")
    end
  end
end
