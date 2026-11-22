# frozen_string_literal: true

module GreeterDocs
  module Adapters
    # Reads docs/adr/*.md per repo, taking each title from the first `# ` heading.
    class FileAdrSource
      include Ports::AdrSource

      def initialize(roots:)
        @roots = roots
      end

      def adrs
        @roots.sort_by(&:first).flat_map do |repo, dir|
          Dir.glob(File.join(dir, '*.md')).map do |path|
            body = Limits.read(path, "#{repo}/#{File.basename(path)}").force_encoding(Encoding::UTF_8)
            name = File.basename(path)
            Domain::Adr.new(repo: repo, file_name: name, title: body[/^# (.+?)\s*$/, 1] || name, body: body)
          end
        end
      end
    end
  end
end
