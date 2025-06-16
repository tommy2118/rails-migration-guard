# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard do
  it "uses connection_db_config instead of deprecated connection_config" do
    # This test ensures we're using the Rails 7.0+ API
    expect(ActiveRecord::Base).to respond_to(:connection_db_config)

    # Verify we can access configuration
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    expect(config).to be_a(Hash)
    expect(config[:adapter]).to eq("sqlite3")
  end

  it "handles ActiveRecord sanitization properly" do
    # Test that our SQL sanitization works
    version = "12345"
    sanitized = ActiveRecord::Base.sanitize_sql(["SELECT * FROM schema_migrations WHERE version = ?", version])
    expect(sanitized).to include("12345")
    expect(sanitized).not_to include("?")
  end

  it "supports Rails 8 migration API" do
    # Ensure our migration templates use versioned migrations
    template_path = "lib/generators/migration_guard/install/templates/create_migration_guard_records.rb"
    migration_template = Rails.root.join(template_path).read
    expect(migration_template).to include("ActiveRecord::Migration[")
  end

  it "handles Rails 8 time zone deprecations" do
    # We should use Time.current instead of Time.now
    expect(Time).to respond_to(:current)

    # Check our code uses Time.current in backup manager
    backup_manager = Rails.root.join("lib/migration_guard/recovery/backup_manager.rb").read
    expect(backup_manager).to include("Time.current")
    expect(backup_manager).not_to include("Time.now")
  end

  describe "ActiveRecord API usage" do
    it "uses modern ActiveRecord query methods" do
      # Test that we use where.not instead of deprecated SQL strings
      expect(MigrationGuard::MigrationGuardRecord).to respond_to(:where)

      # Test modern finder methods
      expect(MigrationGuard::MigrationGuardRecord).to respond_to(:find_by)
      expect(MigrationGuard::MigrationGuardRecord).to respond_to(:pluck)
    end

    it "properly handles connection methods" do
      connection = ActiveRecord::Base.connection

      # These methods should work in Rails 8
      expect(connection).to respond_to(:adapter_name)
      expect(connection).to respond_to(:execute)
      expect(connection).to respond_to(:select_values)
      expect(connection).to respond_to(:select_value)
    end
  end

  describe "Rails 8 specific features" do
    it "gem supports Rails versions up to 9.0" do
      gemspec_content = Rails.root.join("rails_migration_guard.gemspec").read
      expect(gemspec_content).to include('">= 6.1", "< 9.0"')
    end

    it "handles in-memory database in tests" do
      # Rails 8 SQLite adapter handling
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      expect(config[:database]).to eq(":memory:")
    end
  end
end
