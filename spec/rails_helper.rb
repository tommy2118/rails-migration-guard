# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require "spec_helper"
require "logger"
require "active_support"
require "active_record"
require "rails"
require "rails_migration_guard"

# Configure a minimal Rails application for testing
module TestApp
  class Application < Rails::Application
    config.root = File.expand_path("../", __dir__)
    config.eager_load = false

    # Rails 8.0+ timezone handling
    config.active_support.to_time_preserves_timezone = :zone if Rails.version >= "8.0"
  end
end

Rails.application.initialize!

# Setup test database
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Load support files
Rails.root.glob("spec/support/**/*.rb").each { |f| require f }

RSpec.configure do |config|
  config.before(:suite) do
    # Create the migration_guard_records table for testing
    ActiveRecord::Schema.define do
      create_table :migration_guard_records, force: true do |t|
        t.string :version, null: false
        t.string :branch
        t.string :author
        t.string :status
        t.json :metadata
        t.timestamps

        t.index :version, unique: true
        t.index :status
        t.index :created_at
      end

      create_table :schema_migrations, force: true do |t|
        t.string :version, null: false
      end

      add_index :schema_migrations, :version, unique: true
    end
  end

  config.after do
    # Clean up test data
    if ActiveRecord::Base.connection.table_exists?(:migration_guard_records)
      ActiveRecord::Base.connection.execute("DELETE FROM migration_guard_records")
    end
    if ActiveRecord::Base.connection.table_exists?(:schema_migrations)
      ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations")
    end

    # Reset logger instance
    MigrationGuard::Logger.instance_variable_set(:@logger, nil)
  end
end
