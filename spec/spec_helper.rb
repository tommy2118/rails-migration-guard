# frozen_string_literal: true

# Suppress ActiveSupport deprecation warnings
Warning[:deprecated] = false if defined?(Warning.warn)

require "bundler/setup"
require "simplecov"

SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"
end

require "rails_migration_guard"

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

  config.default_formatter = "doc" if config.files_to_run.one?

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  config.before do
    MigrationGuard.reset_configuration!
  end
end
