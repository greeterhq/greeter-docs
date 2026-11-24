# frozen_string_literal: true

require 'json'

module GreeterDocs
  module Adapters
    # Reads tmp/traces/<repo>/repo-trace.json (greeterhq.repo-trace.v1). Refuses
    # any other schema and any file whose repo differs from its directory.
    class ArtifactTraceSource
      include Ports::TraceSource

      SCHEMA = 'greeterhq.repo-trace.v1'

      # subdir: 'prod-smoke' reads the prod smoke trace (design D12) with the
      # same validation and messages.
      def initialize(workspace_root:, subdir: nil)
        @workspace_root = workspace_root
        @subdir = subdir
      end

      def trace(repo)
        label = File.join(*['tmp', 'traces', repo, @subdir, 'repo-trace.json'].compact)
        path = File.join(@workspace_root, label)
        return nil unless File.exist?(path)

        document = parse(Limits.read(path, label), label)
        check(document, repo, label)
        Domain::Trace.new(repo: repo, sha: document['sha'], run_id: document['run_id'],
                          recorded_at: document['recorded_at'], results: results(document['results'], label))
      end

      private

      def parse(text, label)
        document = JSON.parse(text)
        raise SourceError, "#{label}: not a JSON object" unless document.is_a?(Hash)

        document
      rescue JSON::ParserError
        raise SourceError, "#{label}: not valid JSON"
      end

      def check(document, repo, label)
        unless document['schema'] == SCHEMA
          raise SourceError, "#{label}: schema is #{LogSafe.value(document['schema'])}, expected #{SCHEMA}"
        end
        return if document['repo'] == repo

        raise SourceError, "#{label}: repo is #{LogSafe.value(document['repo'])}, expected #{repo}"
      end

      def results(entries, label)
        raise SourceError, "#{label}: results is not a list" unless entries.is_a?(Array)

        entries.each_with_index.map do |entry, index|
          unless entry.is_a?(Hash) && %w[requirement scenario status].all? { |key| entry[key].is_a?(String) }
            raise SourceError, "#{label}: results[#{index}] needs string requirement, scenario and status"
          end

          Domain::Result.new(requirement: entry['requirement'], scenario: entry['scenario'], status: entry['status'],
                             source: entry['source'], location: entry['location'])
        end
      end
    end
  end
end
