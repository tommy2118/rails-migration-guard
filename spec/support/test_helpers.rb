# frozen_string_literal: true

module TestHelpers
  # Create a temporary migration file for testing
  def create_migration(version, name, content = nil)
    content ||= <<~RUBY
      class #{name} < ActiveRecord::Migration[7.0]
        def change
          create_table :#{name.underscore} do |t|
            t.string :name
            t.timestamps
          end
        end
      end
    RUBY

    filename = "#{version}_#{name.underscore}.rb"
    path = Rails.root.join("db", "migrate", filename)

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)

    path
  end

  # Create a migration guard record
  def create_migration_record(version, attributes = {})
    MigrationGuard::MigrationGuardRecord.create!(
      {
        version: version,
        branch: "feature/test",
        author: "test@example.com",
        status: "applied"
      }.merge(attributes)
    )
  end

  # Mock git integration
  def mock_git_integration(overrides = {})
    git = instance_double(MigrationGuard::GitIntegration)

    defaults = {
      current_branch: "feature/test",
      main_branch: "main",
      author_email: "test@example.com",
      migration_versions_in_trunk: [],
      migration_versions_in_branches: { "main" => [] },
      target_branches: ["main"]
    }

    defaults.merge(overrides).each do |method, value|
      allow(git).to receive(method).and_return(value)
    end

    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git)
    git
  end

  # Setup test database with schema
  def setup_test_database
    ActiveRecord::Base.connection.create_table :migration_guard_records, force: true do |t|
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

    ActiveRecord::Base.connection.create_table :schema_migrations, force: true do |t|
      t.string :version, null: false
    end
  end

  # Clean up test artifacts
  def cleanup_test_files
    # Remove test migrations
    FileUtils.rm_rf(Rails.root.join("db/migrate"))

    # Clear database
    MigrationGuard::MigrationGuardRecord.delete_all if table_exists?(:migration_guard_records)
  end

  private

  def table_exists?(table_name)
    ActiveRecord::Base.connection.table_exists?(table_name)
  end
end

RSpec.configure do |config|
  config.include TestHelpers
end
