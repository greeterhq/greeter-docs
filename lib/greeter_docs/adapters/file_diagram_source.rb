# frozen_string_literal: true

module GreeterDocs
  module Adapters
    # Reads docs/diagrams/*.mmd in greeter-docs.
    class FileDiagramSource
      include Ports::DiagramSource

      def initialize(dir:)
        @dir = dir
      end

      def diagrams
        Dir.glob(File.join(@dir, '*.mmd')).map do |path|
          source = Limits.read(path, File.basename(path)).force_encoding(Encoding::UTF_8)
          Domain::Diagram.new(name: File.basename(path, '.mmd'), source: source)
        end
      end
    end
  end
end
