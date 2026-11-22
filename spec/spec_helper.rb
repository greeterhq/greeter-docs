# frozen_string_literal: true

LIB = File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift(LIB)

# lib/greeter_docs.rb does not exist until the implementation lands. Loading it
# only when present makes the red suite fail on the missing constants
# (NameError) rather than on a LoadError at boot.
require 'greeter_docs' if File.exist?(File.join(LIB, 'greeter_docs.rb'))

require_relative 'support/repo_trace_formatter'
require_relative 'support/helpers'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.include SpecHelpers
end
