# frozen_string_literal: true

require 'cgi'

module GreeterDocs
  module Adapters
    module Markdown
      # Inline Markdown: code spans, bold and links. Every text run is
      # HTML-escaped. Link targets are kept only for http, https and scheme-less
      # relative paths (design S5); anything else renders as the link text.
      module Inline
        TOKEN = /`([^`]+)`|\[([^\]]+)\]\(([^)]*)\)|\*\*(.+?)\*\*/
        SCHEME = /\A([a-z][a-z0-9+.-]*):/i

        module_function

        def render(text)
          out = +''
          rest = text
          while (match = TOKEN.match(rest))
            out << h(match.pre_match) << token(match)
            rest = match.post_match
          end
          out << h(rest)
        end

        def token(match)
          return "<code>#{h(match[1])}</code>" if match[1]
          return "<strong>#{h(match[4])}</strong>" if match[4]

          target = safe_url(match[3])
          target ? %(<a href="#{h(target)}">#{h(match[2])}</a>) : h(match[2])
        end

        # The link target to use, or nil when it must not be linked. Entities
        # are decoded and whitespace and control characters removed first,
        # because browsers ignore them inside a scheme (`java&#x09;script:`).
        def safe_url(raw)
          url = CGI.unescapeHTML(raw.to_s).gsub(/[\u0000-\u0020\u007f]/, '')
          return nil if url.empty? || url.start_with?('//', '\\')

          scheme = url[SCHEME, 1]
          return url.sub(/\.md(?=\z|#)/, '.html') unless scheme

          %w[http https].include?(scheme.downcase) ? url : nil
        end

        def h(text)
          CGI.escapeHTML(text.to_s)
        end
      end
    end
  end
end
