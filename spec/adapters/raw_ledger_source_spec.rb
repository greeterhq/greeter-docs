# frozen_string_literal: true

RSpec.describe 'GreeterDocs::Adapters::RawLedgerSource' do
  def source(responses)
    GreeterDocs::Adapters::RawLedgerSource.new(fetcher: ledger_fetcher(responses))
  end

  context 'when reading prod and stage', requirement: 'ledgers-are-read-for-prod-and-stage' do
    context 'with the real prod ledger', scenario: 'the-real-prod-ledger-is-read' do
      it 'returns the channels with verification and run IDs, and the per-channel requirement statuses' do
        ledger = source('prod' => [200, prod_ledger_body]).ledger('prod')

        expect(ledger).to be_recorded
        expect(ledger.channels.transform_values { |c| [c.verification, c.run_id, c.version] })
          .to eq('cli' => ['verified', '44886860348', 'v0.1.12'], 'http' => ['verified', '44886860348', 'v0.5.22'])
        expect(ledger.requirements.keys)
          .to match_array(%w[greeting-count greeting-happy greeting-idempotent greeting-invalid greeting-returning])
        expect(ledger.requirements['greeting-count']).to eq('cli' => 'not_applicable', 'http' => 'passed')
      end
    end

    context 'with the wrong schema', scenario: 'a-ledger-with-the-wrong-schema-fails-the-build-and-is-named' do
      it 'raises a SourceError naming the environment and the schema field' do
        body = JSON.generate(JSON.parse(stage_ledger_body).merge('schema' => 'greeterhq.ledger.v1'))

        expect { source('stage' => [200, body]).ledger('stage') }.to raise_error(GreeterDocs::SourceError) { |error|
          expect(error.message).to include('stage', 'schema')
        }
      end
    end
  end

  context 'when a ledger cannot be fetched', requirement: 'a-missing-ledger-is-not-yet-recorded' do
    context 'with HTTP 500', scenario: 'a-server-error-is-not-treated-as-missing' do
      it 'raises a SourceError naming the environment' do
        expect { source('prod' => [500, 'oops']).ledger('prod') }.to raise_error(GreeterDocs::SourceError, /prod/)
      end
    end
  end

  describe 'other responses' do
    it 'returns not yet recorded for HTTP 404' do
      ledger = source('stage' => [404, 'Not Found']).ledger('stage')

      expect(ledger).not_to be_recorded
      expect(ledger.environment).to eq('stage')
    end

    it 'fetches the raw ledger-<env> URL for each environment' do
      fetcher = ledger_fetcher('prod' => [200, prod_ledger_body], 'stage' => [200, stage_ledger_body])
      ledger_source = GreeterDocs::Adapters::RawLedgerSource.new(fetcher: fetcher)
      ledger_source.ledger('prod')
      ledger_source.ledger('stage')

      expect(fetcher.urls).to eq([format(SpecHelpers::LEDGER_URL, 'prod'), format(SpecHelpers::LEDGER_URL, 'stage')])
    end

    it 'refuses a ledger whose environment differs from the branch' do
      expect { source('stage' => [200, prod_ledger_body]).ledger('stage') }
        .to raise_error(GreeterDocs::SourceError, /stage.*environment|environment.*stage/)
    end

    it 'wraps a network error in a SourceError naming the environment' do
      expect { source('prod' => SocketError.new('getaddrinfo failed')).ledger('prod') }
        .to raise_error(GreeterDocs::SourceError, /prod/)
    end

    it 'refuses an environment other than prod or stage without fetching' do
      fetcher = ledger_fetcher({})

      expect { GreeterDocs::Adapters::RawLedgerSource.new(fetcher: fetcher).ledger('dev') }
        .to raise_error(ArgumentError)
      expect(fetcher.urls).to be_empty
    end
  end
end
