# frozen_string_literal: true

require_relative "colorizer"
require_relative "reporter"
require_relative "git_integration"

module MigrationGuard
  # Helps new developers set up their environment and understand migration state
  # rubocop:disable Metrics/ClassLength
  class SetupAssistant
    def initialize
      @colorizer = Colorizer
      @reporter = Reporter.new
      @git_integration = GitIntegration.new
      @issues = []
      @suggestions = []
    end

    def run_setup
      print_welcome_header
      analyze_environment
      analyze_migration_state
      print_summary
      offer_interactive_fixes
    end

    private

    attr_reader :colorizer, :reporter, :git_integration, :issues, :suggestions

    def print_welcome_header
      puts colorizer.bold("=" * 60) # rubocop:disable Rails/Output
      puts colorizer.bold("🚀 Welcome to Rails Migration Guard Setup!") # rubocop:disable Rails/Output
      puts colorizer.bold("=" * 60) # rubocop:disable Rails/Output
      puts "" # rubocop:disable Rails/Output
      puts "This assistant will help you set up your development environment" # rubocop:disable Rails/Output
      puts "and ensure your migration state matches the team's configuration." # rubocop:disable Rails/Output
      puts "" # rubocop:disable Rails/Output
    end

    def analyze_environment
      puts colorizer.info("🔍 Analyzing your environment...") # rubocop:disable Rails/Output
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
        puts colorizer.info("  💡 This is normal for feature development") # rubocop:disable Rails/Output
      end
    rescue MigrationGuard::GitError
      # Already handled in check_git_repository
    end

    def analyze_migration_state
      return unless MigrationGuard.enabled?

      puts "" # rubocop:disable Rails/Output
      puts colorizer.info("🗃️  Analyzing migration state...") # rubocop:disable Rails/Output
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

      case missing
      when Array
        analyze_simple_missing_migrations(missing)
      when Hash
        analyze_multi_branch_missing_migrations(missing)
      end
    end

    def analyze_simple_missing_migrations(missing)
      if missing.empty?
        print_check("Missing migrations", :success, "up to date with main branch")
      else
        count = missing.size
        add_issue("#{count} migration(s) missing from main branch",
                  "Your database is missing migrations that exist in the main branch")
        add_suggestion("migrate",
                       "Run missing migrations: rails db:migrate")
        print_check("Missing migrations", :warning, "#{count} found in main branch")
      end
    end

    def analyze_multi_branch_missing_migrations(missing_by_branch)
      if missing_by_branch.empty?
        print_check("Missing migrations", :success, "up to date with target branches")
        return
      end

      total_missing = missing_by_branch.values.sum(&:size)
      branches = missing_by_branch.keys.join(", ")
      add_issue("#{total_missing} migration(s) missing from target branches",
                "Your database is missing migrations from: #{branches}")
      add_suggestion("migrate",
                     "Run missing migrations: rails db:migrate")
      print_check("Missing migrations", :warning, "#{total_missing} found in: #{branches}")
    end

    def analyze_schema_consistency
      # Check if schema_migrations table is in sync with migration guard records
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
        puts colorizer.info("  💡 This is normal if Migration Guard was added to an existing project") # rubocop:disable Rails/Output
      end
    end

    def fetch_schema_migrations
      ActiveRecord::Base.connection.select_values("SELECT version FROM schema_migrations")
    rescue StandardError
      []
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def print_summary
      puts "" # rubocop:disable Rails/Output
      puts colorizer.bold("📋 Summary") # rubocop:disable Rails/Output
      puts "=" * 20 # rubocop:disable Rails/Output

      if issues.empty?
        puts colorizer.success("✅ Everything looks good! Your environment is properly set up.") # rubocop:disable Rails/Output
        puts "" # rubocop:disable Rails/Output
        puts "You can start developing with confidence. Migration Guard will help you:" # rubocop:disable Rails/Output
        puts "• Track migrations across branches" # rubocop:disable Rails/Output
        puts "• Detect orphaned migrations" # rubocop:disable Rails/Output
        puts "• Coordinate with your team" # rubocop:disable Rails/Output
      else
        puts colorizer.warning("⚠️  #{issues.size} issue(s) found that need attention:") # rubocop:disable Rails/Output
        puts "" # rubocop:disable Rails/Output

        issues.each_with_index do |(title, description), index|
          puts colorizer.warning("#{index + 1}. #{title}") # rubocop:disable Rails/Output
          puts "   #{description}" # rubocop:disable Rails/Output
          puts "" # rubocop:disable Rails/Output
        end
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize
    def offer_interactive_fixes
      return if suggestions.empty?

      puts colorizer.bold("🛠️  Recommended Actions") # rubocop:disable Rails/Output
      puts "=" * 25 # rubocop:disable Rails/Output

      suggestions.each_with_index do |(_action, description), index|
        puts colorizer.info("#{index + 1}. #{description}") # rubocop:disable Rails/Output
      end

      puts "" # rubocop:disable Rails/Output
      print "Would you like me to run these commands for you? (y/N): " # rubocop:disable Rails/Output
      response = $stdin.gets.chomp.downcase

      if %w[y yes].include?(response)
        execute_suggestions
      else
        puts colorizer.info("💡 Run these commands manually when you're ready.") # rubocop:disable Rails/Output
      end

      print_helpful_commands
    end
    # rubocop:enable Metrics/AbcSize

    def execute_suggestions
      suggestions.each do |action, description|
        puts "" # rubocop:disable Rails/Output
        puts colorizer.info("Running: #{description}") # rubocop:disable Rails/Output

        case action
        when "migrate"
          system("rails db:migrate")
        when "rollback_orphaned"
          puts colorizer.warning("Rolling back orphaned migrations requires confirmation.") # rubocop:disable Rails/Output
          puts colorizer.info("Run: rails db:migration:rollback_orphaned") # rubocop:disable Rails/Output
        end
      end
    end

    def print_helpful_commands
      puts "" # rubocop:disable Rails/Output
      puts colorizer.bold("📚 Helpful Commands") # rubocop:disable Rails/Output
      puts "=" * 20 # rubocop:disable Rails/Output
      puts "• rails db:migration:status     - Check migration status" # rubocop:disable Rails/Output
      puts "• rails db:migration:doctor     - Run diagnostics" # rubocop:disable Rails/Output
      puts "• rails db:migration:history    - View migration history" # rubocop:disable Rails/Output
      puts "• rails db:migration:authors    - See team contributions" # rubocop:disable Rails/Output
      puts "" # rubocop:disable Rails/Output
      puts colorizer.success("🎉 Happy coding!") # rubocop:disable Rails/Output
    end

    def print_check(name, status, details = nil)
      symbol = case status
               when :success then colorizer.success("✓")
               when :warning then colorizer.warning("⚠")
               when :error then colorizer.error("✗")
               when :info then colorizer.info("ℹ")
               end

      line = "#{symbol} #{name}"
      line += ": #{details}" if details
      puts line # rubocop:disable Rails/Output
    end

    def add_issue(title, description)
      issues << [title, description]
    end

    def add_suggestion(action, description)
      suggestions << [action, description]
    end
  end
  # rubocop:enable Metrics/ClassLength
end
