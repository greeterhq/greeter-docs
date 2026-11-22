# frozen_string_literal: true

# greeterHQ live documentation: a hexagonal application that reads specs,
# traces, ledgers and docs through ports and publishes a static site.
module GreeterDocs
  # Raised by a source adapter when an input is missing, malformed or too
  # large. The message names the file or environment and the field.
  class SourceError < StandardError; end
end

require_relative 'greeter_docs/log_safe'

require_relative 'greeter_docs/domain/slug'
require_relative 'greeter_docs/domain/models'
require_relative 'greeter_docs/domain/ledger_view'
require_relative 'greeter_docs/domain/coverage_rule'

%w[spec_source trace_source ledger_source api_source adr_source diagram_source contract_source slo_source
   publisher].each { |port| require_relative "greeter_docs/ports/#{port}" }

%w[limits git_spec_source artifact_trace_source raw_ledger_source file_api_source file_adr_source
   file_diagram_source null_contract_source null_slo_source markdown markdown_inline erb_view site_assets
   erb_html_publisher].each do |adapter|
  require_relative "greeter_docs/adapters/#{adapter}"
end

require_relative 'greeter_docs/build'
require_relative 'greeter_docs/fetch_sources'
