# frozen_string_literal: true

module GreeterDocs
  module Adapters
    # Reads greeter-http's openapi.yaml as plain YAML and resolves local
    # `#/...` $refs. A non-local $ref is kept as-is and never fetched; a cycle
    # or nesting deeper than MAX_DEPTH is a SourceError.
    class FileApiSource
      include Ports::ApiSource

      METHODS = %w[get put post delete options head patch trace].freeze
      MAX_DEPTH = 32

      def initialize(path:, commit:)
        @path = path
        @commit = commit
        @label = File.basename(path)
      end

      def api
        raw = Limits.read(@path, @label)
        document = Limits.yaml(raw, @label)
        raise SourceError, "#{@label}: not an OpenAPI document" unless document.is_a?(Hash)

        info = document.fetch('info', {})
        info = {} unless info.is_a?(Hash)
        Domain::ApiDescription.new(title: info['title'].to_s, version: info['version'].to_s,
                                   description: info['description'].to_s, commit: @commit, raw: raw,
                                   operations: operations(document))
      end

      private

      def operations(document)
        paths = document['paths']
        return [] unless paths.is_a?(Hash)

        paths.flat_map do |path, item|
          next [] unless item.is_a?(Hash)

          METHODS.select { |verb| item[verb].is_a?(Hash) }.map { |verb| operation(document, path, verb, item[verb]) }
        end
      end

      def operation(document, path, verb, spec)
        resolved = resolve(document, spec, [], 0)
        Domain::ApiDescription::Operation.new(
          http_method: verb, path: path.to_s, summary: resolved['summary'].to_s,
          parameters: Array(resolved['parameters']), request_body: resolved['requestBody'],
          responses: (resolved['responses'] || {}).to_h { |code, response| [code.to_s, response] }
        )
      end

      def resolve(document, node, seen, depth)
        raise SourceError, "#{@label}: $ref nesting deeper than #{MAX_DEPTH}" if depth > MAX_DEPTH

        case node
        when Hash then resolve_hash(document, node, seen, depth)
        when Array then node.map { |item| resolve(document, item, seen, depth + 1) }
        else node
        end
      end

      def resolve_hash(document, node, seen, depth)
        ref = node['$ref']
        return node.transform_values { |value| resolve(document, value, seen, depth + 1) } unless local_ref?(ref)
        raise SourceError, "#{@label}: $ref cycle at #{ref}" if seen.include?(ref)

        resolve(document, pointer(document, ref), seen + [ref], depth + 1)
      end

      def local_ref?(ref)
        ref.is_a?(String) && ref.start_with?('#/')
      end

      def pointer(document, ref)
        node = document
        ref.delete_prefix('#/').split('/').each do |part|
          key = part.gsub('~1', '/').gsub('~0', '~')
          raise SourceError, "#{@label}: $ref #{ref} does not resolve" unless node.is_a?(Hash) && node.key?(key)

          node = node[key]
        end
        node
      end
    end
  end
end
