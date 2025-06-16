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
  # Only load in development environment, not in test
  if ENV["RAILS_ENV"] != "test" && ENV["SKIP_MIGRATION_GUARD_TASKS"] != "true"
    # Preload logger gem for Ruby 3.4+ compatibility
    require "logger" if RUBY_VERSION >= "3.4.0"
    
    # Try to load rails if available
    begin
      require "rails"
    rescue LoadError
      # Rails not available, define minimal stubs
      module Rails
        def self.root
          Pathname.new(File.expand_path(".", __dir__))
        end
        
        def self.env
          require "active_support/string_inquirer"
          ActiveSupport::StringInquirer.new("development")
        end
      end
    end

    # Define :environment task if it doesn't exist
    unless Rake::Task.task_defined?(:environment)
      # rubocop:disable Rails/RakeEnvironment
      task :environment do
        # Minimal environment setup for gem development
        require "active_record"
        require "active_support/all"

        # Setup database connection for testing
        ActiveRecord::Base.establish_connection(
          adapter: "sqlite3",
          database: ":memory:"
        )
      end
      # rubocop:enable Rails/RakeEnvironment
    end

    # Load the rake tasks
    load "lib/tasks/migration_guard.rake"
  end
rescue LoadError => e
  # Dependencies not available, skip loading migration tasks
  puts "Skipping migration_guard tasks: #{e.message}" if ENV["DEBUG"]
end
