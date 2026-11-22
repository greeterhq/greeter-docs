# frozen_string_literal: true

module GreeterDocs
  module Domain
    # The heading slug rule shared with every greeterHQ trace check: lowercase,
    # each run of characters other than a-z and 0-9 becomes one '-', and '-' is
    # trimmed from both ends. Camel case is not split.
    module Slug
      PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

      module_function

      def call(heading)
        heading.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
      end

      def slug?(value)
        value.is_a?(String) && PATTERN.match?(value)
      end
    end
  end
end
