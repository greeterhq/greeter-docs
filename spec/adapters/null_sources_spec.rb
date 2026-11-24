# frozen_string_literal: true

RSpec.describe 'GreeterDocs::Adapters::NullContractSource and NullSloSource' do
  context 'when no real source exists yet', requirement: 'contracts-and-slos-are-not-yet-available',
                                            scenario: 'null-sources-return-not-yet-available' do
    it 'returns the not yet available state from both, without raising' do
      expect(GreeterDocs::Adapters::NullContractSource.new.contracts).to eq(:not_yet_available)
      expect(GreeterDocs::Adapters::NullSloSource.new.slos).to eq(:not_yet_available)
    end
  end
end
