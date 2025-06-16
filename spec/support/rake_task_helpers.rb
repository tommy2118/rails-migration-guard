# frozen_string_literal: true

# Helper methods for testing rake tasks
# rubocop:disable Metrics/ModuleLength
module RakeTaskHelpers
  def self.included(base)
    # rubocop:disable RSpec/BeforeAfterAll
    base.before(:all) do
      Rails.application.load_tasks if Rake::Task.tasks.empty?
    end
    # rubocop:enable RSpec/BeforeAfterAll

    base.before do
      # Reset all tasks to allow re-execution
      Rake::Task.tasks.each(&:reenable) if Rake::Task.tasks.any?
    end
  end

  # Run a rake task with optional environment variables
  def run_rake_task(task_name, env_vars = {})
    original_env = ENV.to_h
    env_vars.each { |k, v| ENV[k] = v.to_s }

    Rake::Task[task_name].reenable
    Rake::Task[task_name].execute
  ensure
    ENV.replace(original_env)
  end

  # Invoke a rake task with arguments
  def invoke_rake_task(task_name, *args)
    Rake::Task[task_name].reenable
    Rake::Task[task_name].invoke(*args)
  end

  # Capture output from a rake task
  def capture_rake_output(&block)
    original_stdout = $stdout
    original_stderr = $stderr
    stdout_io = StringIO.new
    stderr_io = StringIO.new
    $stdout = stdout_io
    $stderr = stderr_io

    block.call

    {
      stdout: stdout_io.string,
      stderr: stderr_io.string
    }
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  # Capture Rails logger output
  def capture_logger_output(&block)
    original_logger = Rails.logger
    string_io = StringIO.new
    Rails.logger = Logger.new(string_io)
    Rails.logger.formatter = proc { |_severity, _time, _progname, msg| "#{msg}\n" }

    block.call

    string_io.string
  ensure
    Rails.logger = original_logger
  end

  # Simulate user input for interactive tasks
  def with_simulated_input(*inputs)
    original_stdin = $stdin
    $stdin = StringIO.new("#{inputs.join("\n")}\n")
    yield
  ensure
    $stdin = original_stdin
  end

  # Temporarily disable MigrationGuard
  def with_disabled_migration_guard
    original_enabled = MigrationGuard.enabled?
    allow(MigrationGuard).to receive(:enabled?).and_return(false)
    yield
  ensure
    allow(MigrationGuard).to receive(:enabled?).and_return(original_enabled)
  end

  # Create a test migration file
  # rubocop:disable Metrics/MethodLength
  def create_test_migration_file(version, name = "test_migration", content = nil)
    migration_dir = Rails.root.join("db/migrate")
    FileUtils.mkdir_p(migration_dir)

    content ||= <<~RUBY
      class #{name.camelize} < ActiveRecord::Migration[#{Rails.version.to_f}]
        def change
          create_table :#{name.pluralize} do |t|
            t.string :name
            t.timestamps
          end
        end
      end
    RUBY

    filename = "#{version}_#{name}.rb"
    path = migration_dir.join(filename)
    File.write(path, content)
    path
  end
  # rubocop:enable Metrics/MethodLength

  # Clean up test migration files
  def cleanup_test_migrations
    migration_dir = Rails.root.join("db/migrate")
    FileUtils.rm_rf(Dir.glob(migration_dir.join("*.rb")))
  end

  # Create a migration record with sensible defaults
  def create_migration_record(version, **options)
    defaults = {
      status: "applied",
      branch: "feature/test",
      author: "test@example.com",
      created_at: Time.current,
      metadata: {}
    }

    MigrationGuard::MigrationGuardRecord.create!(
      version: version,
      **defaults.merge(options)
    )
  end

  # Add a migration to schema_migrations table
  def add_to_schema_migrations(version)
    ActiveRecord::Base.connection.execute(
      "INSERT INTO schema_migrations (version) VALUES ('#{version}')"
    )
  end

  # Remove a migration from schema_migrations table
  def remove_from_schema_migrations(version)
    ActiveRecord::Base.connection.execute(
      "DELETE FROM schema_migrations WHERE version = '#{version}'"
    )
  end

  # Mock git integration
  # rubocop:disable Metrics/MethodLength
  def mock_git_integration(overrides = {})
    git_integration = instance_double(MigrationGuard::GitIntegration)

    defaults = {
      current_branch: "feature/test",
      main_branch: "main",
      migration_versions_in_trunk: [],
      author_email: "test@example.com",
      uncommitted_changes?: false,
      file_exists_in_branch?: true
    }

    allow(MigrationGuard::GitIntegration).to receive(:new).and_return(git_integration)

    defaults.merge(overrides).each do |method, return_value|
      if return_value.is_a?(Proc)
        allow(git_integration).to receive(method, &return_value)
      else
        allow(git_integration).to receive(method).and_return(return_value)
      end
    end

    git_integration
  end
  # rubocop:enable Metrics/MethodLength

  # Assert rake task output contains expected content
  def expect_task_output(task_name, env_vars = {})
    output = capture_logger_output do
      run_rake_task(task_name, env_vars)
    end

    expect(output)
  end

  # Create multiple migration records with different states
  # rubocop:disable Metrics/MethodLength
  def setup_migration_scenario(scenario)
    case scenario
    when :clean
      # All migrations in trunk
      %w[001 002 003].each do |v|
        create_migration_record("202401010000#{v}", branch: "main")
      end
    when :orphaned
      # Mix of trunk and orphaned migrations
      create_migration_record("20240101000001", branch: "main")
      create_migration_record("20240101000002", branch: "feature/users")
      create_migration_record("20240101000003", branch: "feature/posts")
    when :conflicts
      # Version conflicts
      create_migration_record("20240101000001", branch: "feature/a")
      create_migration_record("20240101000001", branch: "feature/b").tap do |record|
        # rubocop:disable Rails/SkipsModelValidations
        record.update_column(:id, record.id + 1000)
        # rubocop:enable Rails/SkipsModelValidations
      end
    when :mixed_states
      # Various migration states
      create_migration_record("20240101000001", status: "applied")
      create_migration_record("20240101000002", status: "rolled_back")
      create_migration_record("20240101000003", status: "rolling_back")
    end
  end
  # rubocop:enable Metrics/MethodLength
end
# rubocop:enable Metrics/ModuleLength

# Include in RSpec configuration
RSpec.configure do |config|
  config.include RakeTaskHelpers, type: :rake
  config.include RakeTaskHelpers, rake: true
end
