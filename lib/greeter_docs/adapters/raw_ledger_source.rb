# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module GreeterDocs
  module Adapters
    # Reads ledger.json (greeterhq.ledger.v2) for prod and stage from the
    # greeter-acceptance ledger branches through an injected fetcher. A 404 is
    # "not yet recorded"; any other failure is a SourceError.
    class RawLedgerSource
      include Ports::LedgerSource

      ENVIRONMENTS = %w[prod stage].freeze
      URL = 'https://raw.githubusercontent.com/greeterhq/greeter-acceptance/ledger-%s/ledger.json'
      SCHEMA = 'greeterhq.ledger.v2'

      # The Net::HTTP fetcher used by bin/build-docs. Building it opens no
      # connection; #call connects. Redirects are returned as their status,
      # never followed, and the body is read up to Limits::MAX_BYTES + 1.
      class HttpFetcher
        attr_reader :open_timeout, :read_timeout, :max_bytes

        def initialize(open_timeout: 10, read_timeout: 10, max_bytes: Limits::MAX_BYTES)
          @open_timeout = open_timeout
          @read_timeout = read_timeout
          @max_bytes = max_bytes
        end

        def follows_redirects?
          false
        end

        def call(url)
          uri = URI(url)
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: open_timeout,
                                              read_timeout: read_timeout) do |http|
            http.request_get(uri.request_uri) { |response| return [response.code.to_i, capped_body(response)] }
          end
        end

        private

        def capped_body(response)
          body = +''
          response.read_body do |chunk|
            body << chunk
            break if body.bytesize > max_bytes
          end
          body
        end
      end

      def self.default_fetcher
        HttpFetcher.new
      end

      def initialize(fetcher:)
        @fetcher = fetcher
      end

      def ledger(environment)
        raise ArgumentError, "unknown ledger environment #{environment}" unless ENVIRONMENTS.include?(environment)

        status, body = fetch(environment)
        return Domain::LedgerView.not_recorded(environment) if status == 404
        raise SourceError, "ledger #{environment}: HTTP #{status.to_i}" unless status == 200

        view(parse(body, environment), environment)
      end

      private

      def fetch(environment)
        @fetcher.call(format(URL, environment))
      rescue SourceError
        raise
      rescue StandardError => e
        raise SourceError, "ledger #{environment}: fetch failed (#{e.class})"
      end

      def parse(body, environment)
        raise SourceError, "ledger #{environment}: larger than 5 MiB" if body.to_s.bytesize > Limits::MAX_BYTES

        document = JSON.parse(body.to_s)
        raise SourceError, "ledger #{environment}: not a JSON object" unless document.is_a?(Hash)

        document
      rescue JSON::ParserError
        raise SourceError, "ledger #{environment}: not valid JSON"
      end

      def view(document, environment)
        check(document, environment)
        Domain::LedgerView.recorded(
          environment: environment,
          suite_version: document.dig('suite', 'version'),
          channels: channels(document['channels']),
          requirements: requirements(document['requirements'])
        )
      end

      def check(document, environment)
        unless document['schema'] == SCHEMA
          raise SourceError, "ledger #{environment}: schema is #{LogSafe.value(document['schema'])}, expected #{SCHEMA}"
        end
        return if document['environment'] == environment

        raise SourceError,
              "ledger #{environment}: environment is #{LogSafe.value(document['environment'])}, expected #{environment}"
      end

      def channels(entries)
        (entries.is_a?(Hash) ? entries : {}).to_h do |name, entry|
          entry = {} unless entry.is_a?(Hash)
          [name, Domain::LedgerView::Channel.new(name: name, verification: entry['verification'],
                                                 version: entry['channel_version'], run_id: entry['run_id'])]
        end
      end

      def requirements(entries)
        (entries.is_a?(Hash) ? entries : {}).to_h do |key, statuses|
          [key, statuses.is_a?(Hash) ? statuses : {}]
        end
      end
    end
  end
end
