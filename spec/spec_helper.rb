# frozen_string_literal: true

require "bundler/setup"
require "simplecov"

# Configure SimpleCov for CI
require "simplecov-cobertura" if ENV["CI"]

SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"
  
  # Add formatters for both HTML and XML (for CodeCov)
  if ENV["CI"]
    SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::CoberturaFormatter
    ])
  end
end

# Ensure coverage directory exists
SimpleCov.coverage_dir "coverage"

require "rails-migration-guard"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  config.before(:each) do
    MigrationGuard.reset_configuration!
  end
end