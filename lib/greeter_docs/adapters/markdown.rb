# frozen_string_literal: true

module GreeterDocs
  module Adapters
    # A small Markdown renderer for ADRs: headings, paragraphs, lists, block
    # quotes and fenced code, with inline rendering in Markdown::Inline. Raw
    # HTML is never passed through: every text run is escaped.
    module Markdown
      FENCE = /\A\s*(```|~~~)/
      HEADING = /\A(\#{1,6})\s+(.*?)\s*#*\s*\z/
      BULLET = /\A\s*[-*+]\s+(.*)\z/
      NUMBERED = /\A\s*\d+[.)]\s+(.*)\z/
      QUOTE = /\A\s*>\s?(.*)\z/
      LISTS = { BULLET => 'ul', NUMBERED => 'ol' }.freeze

      module_function

      def render(text)
        lines = text.to_s.lines.map(&:chomp)
        blocks = []
        index = 0
        index = block(lines, index, blocks) while index < lines.size
        blocks.join("\n")
      end

      # Renders the block starting at lines[index] into blocks and returns the
      # index of the next unread line.
      def block(lines, index, blocks)
        line = lines[index]
        return index + 1 if line.strip.empty?
        return fenced(lines, index, blocks) if FENCE.match?(line)
        return heading(line, index, blocks) if HEADING.match?(line)
        return quote(lines, index, blocks) if QUOTE.match?(line)

        marker = LISTS.keys.find { |pattern| pattern.match?(line) }
        marker ? list(lines, index, blocks, marker) : paragraph(lines, index, blocks)
      end

      def heading(line, index, blocks)
        match = HEADING.match(line)
        level = match[1].size
        blocks << "<h#{level}>#{Inline.render(match[2])}</h#{level}>"
        index + 1
      end

      def fenced(lines, index, blocks)
        finish = ((index + 1)...lines.size).find { |i| FENCE.match?(lines[i]) } || lines.size
        blocks << "<pre><code>#{Inline.h(lines[(index + 1)...finish].join("\n"))}</code></pre>"
        finish + 1
      end

      def list(lines, index, blocks, marker)
        items = []
        index += 1 while index < lines.size && added_to_list?(lines[index], marker, items)
        tag = LISTS.fetch(marker)
        blocks << "<#{tag}>#{items.map { |parts| "<li>#{Inline.render(parts.join(' '))}</li>" }.join}</#{tag}>"
        index
      end

      # Adds a list line to items: a new item, or an indented continuation of
      # the last one. Returns false when the line ends the list.
      def added_to_list?(line, marker, items)
        if (match = marker.match(line))
          items << [match[1]]
        elsif items.any? && line.start_with?(' ') && !line.strip.empty?
          items.last << line.strip
        else
          return false
        end
        true
      end

      def quote(lines, index, blocks)
        parts = []
        while index < lines.size && (match = QUOTE.match(lines[index]))
          parts << match[1]
          index += 1
        end
        blocks << "<blockquote><p>#{Inline.render(parts.join(' '))}</p></blockquote>"
        index
      end

      def paragraph(lines, index, blocks)
        parts = []
        while index < lines.size && !lines[index].strip.empty? && !starts_block?(lines[index])
          parts << lines[index].strip
          index += 1
        end
        blocks << "<p>#{Inline.render(parts.join(' '))}</p>"
        index
      end

      def starts_block?(line)
        [FENCE, HEADING, QUOTE, *LISTS.keys].any? { |pattern| pattern.match?(line) }
      end
    end
  end
end
