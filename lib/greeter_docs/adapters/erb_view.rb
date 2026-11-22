# frozen_string_literal: true

require 'cgi'
require 'erb'
require 'json'

module GreeterDocs
  module Adapters
    # The context an ERB template renders in: each local becomes a method, and
    # #h escapes. There is deliberately no raw-output helper.
    class ErbView
      def initialize(locals)
        @locals = locals
        locals.each_key { |name| define_singleton_method(name) { @locals.fetch(name) } }
      end

      def h(value)
        CGI.escapeHTML(value.to_s)
      end

      # The value when it is a slug, so it can go into an id or data attribute.
      def slug_or_nil(value)
        Domain::Slug.slug?(value) ? value : nil
      end

      # ` name="value"` for a slug value, or nothing (design S5).
      def attr(name, value)
        safe = slug_or_nil(value)
        safe ? %( #{name}="#{h(safe)}") : ''
      end

      def paragraphs(text)
        text.to_s.split(/\n\s*\n/).map(&:strip).reject(&:empty?).map { |para| "<p>#{h(para)}</p>" }.join("\n")
      end

      def pretty(value)
        JSON.pretty_generate(value)
      rescue StandardError
        value.to_s
      end

      def render(source)
        ERB.new(source, trim_mode: '-').result(binding)
      end
    end
  end
end
