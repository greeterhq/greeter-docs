# frozen_string_literal: true

RSpec.describe 'GreeterDocs::Domain::Slug' do
  context 'with the shared slug rule', requirement: 'headings-become-slugs-by-the-shared-rule',
                                       scenario: 'slug-rule-turns-headings-into-slugs' do
    it 'lowercases, collapses non-alphanumeric runs to one hyphen and trims, without camel-case splitting' do
      table = {
        'A channel greets a valid guest' => 'a-channel-greets-a-valid-guest',
        'Clock#now raises NotImplementedError' => 'clock-now-raises-notimplementederror',
        'Equal names agree across ==, eql?, hash, and uniq' => 'equal-names-agree-across-eql-hash-and-uniq',
        '"  --Leading and trailing!!  "' => 'leading-and-trailing',
        'Record mode uses the latest published suite version' =>
          'record-mode-uses-the-latest-published-suite-version'
      }

      expect(table.keys.to_h { |heading| [heading, GreeterDocs::Domain::Slug.call(heading)] }).to eq(table)
    end
  end
end
