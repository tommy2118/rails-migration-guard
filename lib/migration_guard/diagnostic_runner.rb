# frozen_string_literal: true

require_relative "colorizer"
require_relative "diagnostic_presenter"
require_relative "diagnostics/infrastructure_checker"
require_relative "diagnostics/git_checker"
require_relative "diagnostics/migration_state_checker"

module MigrationGuard
  # Orchestrates diagnostic checks for troubleshooting MigrationGuard issues
  class DiagnosticRunner
    def initialize(git_integration: GitIntegration.new, reporter: Reporter.new)
      @issues = []
      @warnings = []
      @presenter = DiagnosticPresenter.new(colorizer: Colorizer, output: self)
      @infrastructure = Diagnostics::InfrastructureChecker.new(
        issues: @issues, warnings: @warnings, output: self
      )
      @git = Diagnostics::GitChecker.new(
        issues: @issues, warnings: @warnings, output: self, git_integration: git_integration
      )
      @migration_state = Diagnostics::MigrationStateChecker.new(
        issues: @issues, warnings: @warnings, output: self, reporter: reporter
      )
    end

    def run_all_checks
      @presenter.print_header

      @infrastructure.run_checks
      @git.run_checks
      @migration_state.run_checks

      @presenter.print_summary(@issues, @warnings)
    end
  end
end
