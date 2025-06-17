# frozen_string_literal: true

require_relative "colorizer"

module MigrationGuard
  class BranchChangeDetector
    def initialize
      @git_integration = GitIntegration.new
      @reporter = Reporter.new
      MigrationGuard::Logger.debug("Initialized BranchChangeDetector")
    end

    def check_branch_change(previous_head, _new_head, is_branch_checkout) # rubocop:disable Metrics/MethodLength
      MigrationGuard::Logger.debug("Checking branch change",
                                   previous_head: previous_head,
                                   is_branch_checkout: is_branch_checkout)

      # Only check on actual branch changes, not file checkouts
      return unless is_branch_checkout == "1"

      # Check if git integration is disabled
      if MigrationGuard.configuration.git_integration_level == :off
        MigrationGuard::Logger.debug("Git integration disabled")
        return
      end

      # Check if branch warnings are enabled
      unless MigrationGuard.configuration.warn_on_switch
        MigrationGuard::Logger.debug("Branch switch warnings disabled")
        return
      end

      previous_branch = branch_name_from_ref(previous_head)
      current_branch = @git_integration.current_branch
      MigrationGuard::Logger.debug("Branch change detected",
                                   from: previous_branch,
                                   to: current_branch)

      # Skip if we couldn't determine the branch change
      return if previous_branch == current_branch

      check_for_orphaned_migrations(previous_branch, current_branch)
    end

    def format_branch_change_warnings
      orphaned = @reporter.orphaned_migrations
      return nil if orphaned.empty?

      output = []
      add_warning_header(output)
      add_orphaned_migrations_list(output, orphaned)
      add_help_text(output)

      output.join("\n")
    end

    private

    def branch_name_from_ref(ref)
      # Try to get branch name from the ref
      result = `git name-rev --name-only #{ref} 2>/dev/null`.strip
      return nil if result.empty? || result.include?("undefined")

      # Clean up the branch name (remove remotes/ prefix and ~N suffixes)
      result.gsub(%r{^remotes/[^/]+/}, "").gsub(/~\d+$/, "")
    rescue StandardError
      nil
    end

    def check_for_orphaned_migrations(previous_branch, current_branch)
      MigrationGuard::Logger.info("Branch switch detected", from: previous_branch, to: current_branch)
      puts "" # rubocop:disable Rails/Output
      puts Colorizer.info("Switched from '#{previous_branch}' to '#{current_branch}'") # rubocop:disable Rails/Output

      warning = format_branch_change_warnings
      return unless warning

      MigrationGuard::Logger.warn("Orphaned migrations detected on branch switch")
      puts warning # rubocop:disable Rails/Output
    end

    def add_warning_header(output)
      output << ""
      output << Colorizer.warning("⚠️  Branch Change Warning")
      output << Colorizer.warning("Your database has migrations not in the current branch:")
      output << ""
    end

    def add_orphaned_migrations_list(output, orphaned)
      orphaned.each do |migration|
        branch_info = migration.branch ? " (from branch: #{migration.branch})" : ""
        output << "  • #{migration.version}#{branch_info}"
      end
    end

    def add_help_text(output)
      output << ""
      output << "Run 'rails db:migration:status' for details or 'rails db:migration:rollback_orphaned' to clean up."
      output << ""
    end
  end
end
