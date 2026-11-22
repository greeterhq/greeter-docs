# frozen_string_literal: true

# Fixture suite for spec/support/repo_trace_formatter_spec.rb. It is not named
# *_spec.rb, so the main suite never loads it; the formatter spec runs it in a
# subprocess.
RSpec.describe 'trace fixture suite' do
  it 'passes', requirement: 'fixture-requirement', scenario: 'fixture-passing' do
    expect(1).to eq(1)
  end

  it 'is skipped', requirement: 'fixture-requirement', scenario: 'fixture-skipped' do
    skip 'fixture'
  end

  it 'is untagged and not recorded' do
    expect(true).to be(true)
  end
end
