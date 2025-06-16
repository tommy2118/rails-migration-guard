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

desc "Run development console with test data"
task console: :environment do
  exec "bin/console"
end

desc "Run manual test scenarios"
task "test:manual" => :environment do
  puts "Setting up manual test environment..."

  # Load the gem in development mode
  require_relative "lib/rails_migration_guard"

  # Create test migrations
  test_dir = "tmp/manual_test"
  FileUtils.mkdir_p("#{test_dir}/db/migrate")

  # Create sample migration files
  migrations = [
    %w[20240101000001 CreateUsers],
    %w[20240102000001 AddEmailToUsers],
    %w[20240103000001 CreatePosts],
    %w[20240104000001 AddAuthorToPosts]
  ]

  migrations.each do |version, name|
    File.write("#{test_dir}/db/migrate/#{version}_#{name.underscore}.rb", <<~RUBY)
      class #{name} < ActiveRecord::Migration[7.0]
        def change
          # Test migration
        end
      end
    RUBY
  end

  puts "Created #{migrations.size} test migrations in #{test_dir}/db/migrate"
  puts "Run 'bin/console' to interact with the test environment"
end

desc "Generate sample migration files for testing"
# rubocop:disable Metrics/BlockLength
task "test:fixtures" => :environment do
  fixtures_dir = "spec/fixtures/migrations"
  FileUtils.mkdir_p(fixtures_dir)

  # Various migration scenarios
  scenarios = {
    "valid_migration" => <<~RUBY,
      class CreateTestTable < ActiveRecord::Migration[7.0]
        def change
          create_table :test_table do |t|
            t.string :name
            t.timestamps
          end
        end
      end
    RUBY
    "invalid_syntax" => <<~RUBY,
      class InvalidSyntax < ActiveRecord::Migration[7.0]
        def change
          create_table :test_table do |t|
            t.string :name
          # Missing end
        end
      end
    RUBY
    "complex_migration" => <<~RUBY
      class ComplexMigration < ActiveRecord::Migration[7.0]
        def up
          create_table :complex_table do |t|
            t.string :name, null: false
            t.integer :count, default: 0
            t.jsonb :metadata
            t.timestamps
          end
      #{'    '}
          add_index :complex_table, :name, unique: true
          add_index :complex_table, :created_at
        end
      #{'  '}
        def down
          drop_table :complex_table
        end
      end
    RUBY
  }

  scenarios.each do |name, content|
    timestamp = Time.zone.now.strftime("%Y%m%d%H%M%S")
    filename = "#{fixtures_dir}/#{timestamp}_#{name}.rb"
    File.write(filename, content)
    puts "Created fixture: #{filename}"
    sleep 1 # Ensure unique timestamps
  end

  puts "\nCreated #{scenarios.size} fixture migrations in #{fixtures_dir}"
end
# rubocop:enable Metrics/BlockLength

desc "Clean up test artifacts"
task "test:clean" => :environment do
  dirs = %w[tmp/manual_test spec/fixtures/migrations]
  dirs.each do |dir|
    if File.exist?(dir)
      FileUtils.rm_rf(dir)
      puts "Removed #{dir}"
    end
  end

  # Clean up test database
  test_db = "tmp/test.db"
  if File.exist?(test_db)
    File.delete(test_db)
    puts "Removed test database"
  end
end
