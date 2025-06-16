# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "open3"

# rubocop:disable Metrics/ModuleLength, Metrics/MethodLength, Metrics/AbcSize, Layout/LineLength, RSpec/VerifiedDoubles

module RecoveryIntegrationHelpers
  # Setup a temporary Rails app environment for integration testing
  def with_temporary_rails_app
    Dir.mktmpdir("migration_guard_test") do |temp_dir|
      setup_rails_app_structure(temp_dir)
      setup_git_repository(temp_dir)

      within_app_directory(temp_dir) do
        yield temp_dir
      end
    end
  end

  # Create a complete Rails app structure for testing
  def setup_rails_app_structure(app_root)
    # Essential directories
    %w[
      db/migrate
      db/backups
      config
      app/models
      lib
      log
      tmp
    ].each do |dir|
      FileUtils.mkdir_p(File.join(app_root, dir))
    end

    # Create essential files
    create_rails_config_files(app_root)
    create_migration_guard_table(app_root)
  end

  # Initialize git repository with basic structure
  def setup_git_repository(app_root)
    within_app_directory(app_root) do
      run_git_command("git init")
      run_git_command("git config user.name 'Test User'")
      run_git_command("git config user.email 'test@example.com'")

      # Create initial commit
      File.write(".gitignore", "/log/*\n/tmp/*\n/db/*.sqlite3\n")
      run_git_command("git add .")
      run_git_command("git commit -m 'Initial commit'")

      # Create main branch
      run_git_command("git branch -M main")
    end
  end

  # Create a feature branch with migrations
  def create_feature_branch_with_migrations(app_root, branch_name, migration_versions)
    within_app_directory(app_root) do
      run_git_command("git checkout -b #{branch_name}")

      migration_versions.each do |version|
        create_test_migration(app_root, version, "TestFeature#{version}")
      end

      run_git_command("git add db/migrate/")
      run_git_command("git commit -m 'Add feature migrations'")
      run_git_command("git checkout main")
    end
  end

  # Create and apply migrations to database
  def apply_migrations_to_database(app_root, migration_versions)
    within_app_directory(app_root) do
      migration_versions.each do |version|
        # Simulate applying migration to schema_migrations
        ActiveRecord::Base.connection.execute(
          "INSERT INTO schema_migrations (version) VALUES ('#{version}')"
        )

        # Create tracking record
        MigrationGuard::MigrationGuardRecord.create!(
          version: version,
          branch: current_git_branch,
          author: "test@example.com",
          status: "applied",
          metadata: { applied_at: Time.current.iso8601 }
        )
      end
    end
  end

  # Create orphaned migrations (applied but not in main branch)
  def create_orphaned_migrations(app_root, versions)
    within_app_directory(app_root) do
      # Create feature branch with migrations
      run_git_command("git checkout -b temp_feature")

      versions.each do |version|
        create_test_migration(app_root, version, "OrphanedMigration#{version}")
      end

      run_git_command("git add db/migrate/")
      run_git_command("git commit -m 'Add orphaned migrations'")

      # Apply migrations to database
      apply_migrations_to_database(app_root, versions)

      # Switch back to main and delete feature branch
      run_git_command("git checkout main")
      run_git_command("git branch -D temp_feature")

      # Remove migration files from main branch
      versions.each do |version|
        Dir.glob(File.join(app_root, "db/migrate/*#{version}*")).each do |file|
          File.delete(file)
        end
      end
    end
  end

  # Create stuck rollback scenario
  def create_stuck_rollback_scenario(app_root, version)
    within_app_directory(app_root) do
      # Create migration record in rolling_back state
      MigrationGuard::MigrationGuardRecord.create!(
        version: version,
        branch: "feature/test",
        author: "test@example.com",
        status: "rolling_back",
        updated_at: 2.hours.ago, # Stuck for 2 hours
        metadata: { rollback_started_at: 2.hours.ago.iso8601 }
      )

      # Keep it in schema_migrations to simulate partial rollback
      ActiveRecord::Base.connection.execute(
        "INSERT INTO schema_migrations (version) VALUES ('#{version}')"
      )
    end
  end

  # Create version conflict scenario
  def create_version_conflict_scenario(app_root, version)
    within_app_directory(app_root) do
      # Create multiple records with same version
      2.times do |i|
        MigrationGuard::MigrationGuardRecord.create!(
          version: version,
          branch: "feature/branch#{i + 1}",
          author: "dev#{i + 1}@example.com",
          status: "applied",
          metadata: { branch_info: "conflict_#{i + 1}" }
        )
      end
    end
  end

  # Verify database consistency after recovery
  def verify_database_consistency(expected_versions: [], unexpected_versions: [])
    # Check schema_migrations table
    schema_versions = ActiveRecord::Base.connection.execute(
      "SELECT version FROM schema_migrations ORDER BY version"
    ).pluck("version")

    expected_versions.each do |version|
      expect(schema_versions).to include(version),
                                 "Expected version #{version} to be in schema_migrations"
    end

    unexpected_versions.each do |version|
      expect(schema_versions).not_to include(version),
                                     "Expected version #{version} to NOT be in schema_migrations"
    end

    # Check migration_guard_records consistency
    guard_records = MigrationGuard::MigrationGuardRecord.all
    guard_records.each do |record|
      if expected_versions.include?(record.version)
        expect(record.status).not_to eq("orphaned"),
                                     "Expected #{record.version} to not be orphaned"
      end
    end
  end

  # Verify file system state
  def verify_migration_files_exist(app_root, versions)
    versions.each do |version|
      files = Dir.glob(File.join(app_root, "db/migrate/*#{version}*"))
      expect(files).not_to be_empty,
                           "Expected migration file for version #{version} to exist"
    end
  end

  # Verify backup was created
  def verify_backup_created(app_root, backup_name = nil)
    backup_dir = File.join(app_root, "db/backups")
    backup_files = Dir.glob(File.join(backup_dir, "*.sql"))

    if backup_name
      expect(backup_files.any? { |f| f.include?(backup_name) }).to be true,
                                                                      "Expected backup file containing '#{backup_name}' to exist"
    else
      expect(backup_files).not_to be_empty, "Expected at least one backup file to exist"
    end
  end

  # Run recovery process and capture results
  def run_recovery_process(app_root, options = {})
    within_app_directory(app_root) do
      analyzer = MigrationGuard::RecoveryAnalyzer.new
      issues = analyzer.analyze

      if options[:execute_recovery] && issues.any?
        executor = MigrationGuard::RecoveryExecutor.new
        results = issues.map do |issue|
          recovery_action = options[:recovery_action] || issue[:recovery_options].first
          executor.execute_recovery(issue, recovery_action)
        end
        { issues: issues, results: results }
      else
        { issues: issues, results: [] }
      end
    end
  end

  # Simulate database connection failure
  def simulate_database_failure
    original_connection = ActiveRecord::Base.connection

    allow(ActiveRecord::Base).to receive(:connection).and_raise(
      ActiveRecord::ConnectionNotEstablished, "Database connection lost"
    )

    yield
  ensure
    allow(ActiveRecord::Base).to receive(:connection).and_return(original_connection)
  end

  # Simulate git command failure
  def simulate_git_failure(command_pattern)
    allow(Open3).to receive(:capture3).and_wrap_original do |original, *args|
      if args.join(" ").match?(command_pattern)
        ["", "Git command failed", double(success?: false, exitstatus: 1)]
      else
        original.call(*args)
      end
    end
  end

  # Get current git branch
  def current_git_branch
    `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip.presence || "main"
  end

  # Measure performance of recovery operations
  def measure_recovery_performance(migration_count)
    start_time = Time.current
    result = yield
    end_time = Time.current

    duration = end_time - start_time

    {
      result: result,
      duration: duration,
      migrations_per_second: migration_count / duration.to_f,
      performance_acceptable: duration < (migration_count * 0.1) # 100ms per migration max
    }
  end

  private

  def create_rails_config_files(app_root)
    # Create minimal database.yml
    database_config = <<~YAML
      test:
        adapter: sqlite3
        database: ":memory:"
        pool: 5
        timeout: 5000
    YAML

    File.write(File.join(app_root, "config/database.yml"), database_config)
  end

  def create_migration_guard_table(_app_root)
    # Ensure the migration_guard_records table exists
    unless ActiveRecord::Base.connection.table_exists?(:migration_guard_records)
      ActiveRecord::Base.connection.create_table :migration_guard_records do |t|
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
    end

    # Ensure schema_migrations table exists
    return if ActiveRecord::Base.connection.table_exists?(:schema_migrations)

    ActiveRecord::Base.connection.create_table :schema_migrations do |t|
      t.string :version, null: false
      t.index :version, unique: true
    end
  end

  def create_test_migration(app_root, version, class_name)
    content = <<~RUBY
      class #{class_name} < ActiveRecord::Migration[7.0]
        def change
          create_table :#{class_name.underscore.pluralize} do |t|
            t.string :name
            t.timestamps
          end
        end
      end
    RUBY

    filename = "#{version}_#{class_name.underscore}.rb"
    path = File.join(app_root, "db/migrate", filename)

    File.write(path, content)
    path
  end

  def within_app_directory(app_root)
    original_dir = Dir.pwd
    Dir.chdir(app_root)
    yield
  ensure
    Dir.chdir(original_dir)
  end

  def run_git_command(command)
    stdout, stderr, status = Open3.capture3(command)
    raise "Git command failed: #{command}\nSTDOUT: #{stdout}\nSTDERR: #{stderr}" unless status.success?

    stdout
  end
end

# Shared context for recovery integration tests
RSpec.shared_context "with recovery integration setup" do
  include RecoveryIntegrationHelpers

  around do |example|
    with_temporary_rails_app do |app_root|
      @app_root = app_root
      example.run
    end
  end

  # Clean up after each test
  after do
    MigrationGuard::MigrationGuardRecord.delete_all
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations")
  end
end

RSpec.configure do |config|
  config.include RecoveryIntegrationHelpers
end
