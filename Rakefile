# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: %i[spec rubocop]

desc "Run specs against multiple Rails versions"
task test_all: :environment do
  %w[6.1 7.0 7.1].each do |rails_version|
    puts "Testing against Rails #{rails_version}"
    system("RAILS_VERSION=#{rails_version} bundle exec rspec") || exit(1)
  end
end

# Load migration_guard tasks in development environment
# This allows testing rake tasks without a full Rails app
begin
  # Preload logger gem for Ruby 3.4+ compatibility
  require "logger" if RUBY_VERSION >= "3.4.0"
  require "rails"
  require_relative "lib/rails_migration_guard"

  # Define a minimal Rails.root for task testing
  Rails.define_singleton_method(:root) { Pathname.new(File.expand_path(".", __dir__)) } unless Rails.respond_to?(:root)

  # Define a minimal Rails.env for task testing
  unless Rails.respond_to?(:env)
    Rails.define_singleton_method(:env) { ActiveSupport::StringInquirer.new("development") }
  end

  # Define :environment task if it doesn't exist
  task :environment do
    # Minimal environment setup for gem development
    require "active_record"
    require "active_support/all"

    # Setup database connection for testing
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:"
    )

    # Load migration guard
    require_relative "lib/rails_migration_guard"
  end

  # Load the rake tasks
  load "lib/tasks/migration_guard.rake"
rescue LoadError => e
  # Rails not available, skip loading migration tasks
  puts "Skipping migration_guard tasks: #{e.message}" if ENV["DEBUG"]
end
