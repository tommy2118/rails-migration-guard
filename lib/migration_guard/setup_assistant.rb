# frozen_string_literal: true

require_relative "colorizer"
require_relative "check_printer"
require_relative "schema_inspector"
require_relative "reporter"
require_relative "git_integration"
require_relative "setup_presenter"

module MigrationGuard
  # Helps new developers set up their environment and understand migration state
  class SetupAssistant
    include CheckPrinter
    include SchemaInspector

    def initialize(reporter: Reporter.new, git_integration: GitIntegration.new)
      @colorizer = Colorizer
      @reporter = reporter
      @git_integration = git_integration
      @issues = []
      @suggestions = []
      @presenter = SetupPresenter.new(colorizer: @colorizer, output: self)
    end

    def run_setup
      @presenter.print_welcome_header
      analyze_environment
      analyze_migration_state
      @presenter.print_summary(issues)
      offer_interactive_fixes
    end

    private

    attr_reader :colorizer, :reporter, :git_integration, :issues, :suggestions

    def analyze_environment
      puts colorizer.info("\u{1F50D} Analyzing your environment...") # rubocop:disable Rails/Output
      puts "" # rubocop:disable Rails/Output

      check_migration_guard_installation
      check_database_connection
      check_git_repository
      check_current_branch
    end

    def check_migration_guard_installation
      if MigrationGuard.enabled?
        print_check("Migration Guard installation", :success, "enabled in #{Rails.env}")
      else
        add_issue("Migration Guard is not enabled in current environment",
                  "Check your configuration in config/environments/#{Rails.env}.rb")
        print_check("Migration Guard installation", :warning, "not enabled in #{Rails.env}")
      end
    end

    def check_database_connection
      ActiveRecord::Base.connection.execute("SELECT 1")
      MigrationGuard::MigrationGuardRecord.table_exists?
      print_check("Database connection", :success, "connected with migration tracking")
    rescue StandardError => e
      add_issue("Database connection failed", "Error: #{e.message}")
      print_check("Database connection", :error, "failed")
    end

    def check_git_repository
      current_branch = git_integration.current_branch
      main_branch = git_integration.main_branch
      print_check("Git repository", :success, "current: #{current_branch}, main: #{main_branch}")
    rescue MigrationGuard::GitError => e
      add_issue("Git repository issue", e.message)
      print_check("Git repository", :error, "issue detected")
    end

    def check_current_branch
      current_branch = git_integration.current_branch
      main_branch = git_integration.main_branch

      if current_branch == main_branch
        print_check("Branch status", :success, "on main branch")
      else
        print_check("Branch status", :info, "on feature branch: #{current_branch}")
        puts colorizer.info("  \u{1F4A1} This is normal for feature development") # rubocop:disable Rails/Output
      end
    rescue MigrationGuard::GitError
      # Already handled in check_git_repository
    end

    def analyze_migration_state
      return unless MigrationGuard.enabled?

      puts "" # rubocop:disable Rails/Output
      puts colorizer.info("\u{1F5C3}\u{FE0F}  Analyzing migration state...") # rubocop:disable Rails/Output
      puts "" # rubocop:disable Rails/Output

      analyze_orphaned_migrations
      analyze_missing_migrations
      analyze_schema_consistency
    end

    def analyze_orphaned_migrations
      orphaned = reporter.orphaned_migrations

      if orphaned.empty?
        print_check("Orphaned migrations", :success, "none found")
      else
        count = orphaned.size
        branches = orphaned.map(&:branch).uniq.join(", ")
        add_issue("#{count} orphaned migration(s) detected",
                  "These migrations exist in your database but not in the main branch")
        add_suggestion("rollback_orphaned",
                       "Roll back orphaned migrations: rails db:migration:rollback_orphaned")
        print_check("Orphaned migrations", :warning, "#{count} found from branches: #{branches}")
      end
    end

    def analyze_missing_migrations
      missing = reporter.missing_migrations
      return report_missing_up_to_date(missing) if missing.empty?

      report_missing_migrations(missing)
    end

    def report_missing_up_to_date(missing)
      source = missing.is_a?(Hash) ? "target branches" : "main branch"
      print_check("Missing migrations", :success, "up to date with #{source}")
    end

    def report_missing_migrations(missing)
      if missing.is_a?(Hash)
        count = missing.values.sum(&:size)
        source = missing.keys.join(", ")
        detail = "#{count} found in: #{source}"
        add_issue("#{count} migration(s) missing from target branches",
                  "Your database is missing migrations from: #{source}")
      else
        count = missing.size
        detail = "#{count} found in main branch"
        add_issue("#{count} migration(s) missing from main branch",
                  "Your database is missing migrations that exist in the main branch")
      end

      add_suggestion("migrate", "Run missing migrations: rails db:migrate")
      print_check("Missing migrations", :warning, detail)
    end

    def analyze_schema_consistency
      schema_versions = fetch_schema_migrations
      tracked_versions = MigrationGuard::MigrationGuardRecord.pluck(:version)

      untracked_in_schema = schema_versions - tracked_versions

      if untracked_in_schema.empty?
        print_check("Schema consistency", :success, "migration tracking is complete")
      else
        count = untracked_in_schema.size
        add_issue("#{count} migration(s) in schema but not tracked",
                  "Some migrations were run before Migration Guard was installed")
        print_check("Schema consistency", :info, "#{count} pre-existing migrations detected")
        puts colorizer.info("  \u{1F4A1} This is normal if Migration Guard was added to an existing project") # rubocop:disable Rails/Output
      end
    end

    def offer_interactive_fixes
      return if suggestions.empty?

      if @presenter.offer_interactive_fixes(suggestions)
        execute_suggestions(suggestions)
      else
        puts colorizer.info("\u{1F4A1} Run these commands manually when you're ready.") # rubocop:disable Rails/Output
      end

      @presenter.print_helpful_commands
    end

    def execute_suggestions(suggestions)
      suggestions.each do |action, description|
        puts colorizer.info("\nRunning: #{description}") # rubocop:disable Rails/Output
        case action
        when "migrate" then system("rails db:migrate")
        when "rollback_orphaned"
          puts colorizer.warning("Rolling back orphaned migrations requires confirmation.") # rubocop:disable Rails/Output
          puts colorizer.info("Run: rails db:migration:rollback_orphaned") # rubocop:disable Rails/Output
        end
      end
    end

    def add_issue(title, description) = issues << [title, description]

    def add_suggestion(action, description) = suggestions << [action, description]
  end
end
