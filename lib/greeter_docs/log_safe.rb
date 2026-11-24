# frozen_string_literal: true

module GreeterDocs
  # Makes text safe to print to a GitHub Actions log (design S1, S7).
  #
  # A log line that starts with `::` is run as a workflow command, and an
  # embedded newline forges a second line. Values read from sources are echoed
  # only when they look like a slug or a repo-relative path.
  module LogSafe
    REPLACEMENT = "\uFFFD"
    CONTROL = /[\u0000-\u001f\u007f]/
    MAX_VALUE = 200
    SLUG = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    # Each segment starts with a word character or '-', so '.', '..' and empty
    # segments are refused.
    PATH = %r{\A[\w-][\w.-]*(?:/[\w-][\w.-]*)*\z}
    INVALID = '(invalid value)'

    module_function

    def line(text)
      safe = text.to_s.gsub(CONTROL, REPLACEMENT)
      safe.lstrip.start_with?('::') ? "#{REPLACEMENT} #{safe}" : safe
    end

    def value(text)
      return INVALID unless text.is_a?(String) && (SLUG.match?(text) || PATH.match?(text))

      text.length > MAX_VALUE ? "#{text[0, MAX_VALUE]}…" : text
    end
  end
end
