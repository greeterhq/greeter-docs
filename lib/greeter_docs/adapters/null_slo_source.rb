# frozen_string_literal: true

module GreeterDocs
  module Adapters
    class NullSloSource
      include Ports::SloSource

      def slos = :not_yet_available
    end
  end
end
