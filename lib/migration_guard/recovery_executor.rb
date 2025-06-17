# frozen_string_literal: true

require "migration_guard/colorizer"
require "migration_guard/recovery/base_action"
require "migration_guard/recovery/backup_manager"
require "migration_guard/recovery/rollback_action"
require "migration_guard/recovery/restore_action"
require "migration_guard/recovery/tracking_action"
require "migration_guard/recovery/schema_action"
require "migration_guard/recovery/manual_intervention"
require "migration_guard/recovery/option_formatter"

module MigrationGuard
  # RecoveryExecutor performs recovery actions for inconsistent migration states
  class RecoveryExecutor
    def initialize(interactive: true)
      @interactive = interactive
      @backup_manager = Recovery::BackupManager.new
      @actions = initialize_actions
      @executing_recovery = false
    end

    def execute_recovery(issue, option = nil)
      return false if executing_recovery?

      @executing_recovery = true

      begin
        create_backup_if_needed
      rescue StandardError => e
        Rails.logger&.error "Failed to create backup: #{e.message}"
        # Continue with recovery even if backup fails
      end

      recovery_method = determine_recovery_method(issue, option)

      return false unless recovery_method

      execute_action(recovery_method, issue)
    ensure
      @executing_recovery = false
    end

    def executing_recovery?
      @executing_recovery
    end

    delegate :create_backup, to: :@backup_manager
    delegate :backup_path, to: :@backup_manager

    private

    def interactive?
      @interactive
    end

    def backup_exists?
      @backup_manager.backup_exists?
    end

    def create_backup_if_needed
      create_backup unless backup_exists?
    end

    def determine_recovery_method(issue, option)
      return option if option

      if interactive?
        prompt_for_option(issue)
      else
        issue[:recovery_options].first
      end
    end

    def initialize_actions
      {
        rollback: Recovery::RollbackAction.new,
        restore: Recovery::RestoreAction.new,
        tracking: Recovery::TrackingAction.new,
        schema: Recovery::SchemaAction.new,
        manual: Recovery::ManualIntervention.new
      }
    end

    def execute_action(recovery_method, issue)
      action_map = build_action_map(issue)
      action = action_map[recovery_method]
      action ? action.call : unknown_option?(recovery_method)
    end

    def build_action_map(issue)
      rollback_actions(issue)
        .merge(restore_actions(issue))
        .merge(tracking_actions(issue))
        .merge(schema_actions(issue))
        .merge(manual_actions(issue))
    end

    def rollback_actions(issue)
      {
        complete_rollback: -> { @actions[:rollback].complete_rollback(issue) },
        mark_as_rolled_back: -> { @actions[:rollback].mark_as_rolled_back(issue) }
      }
    end

    def restore_actions(issue)
      {
        restore_migration: -> { @actions[:restore].restore_migration(issue) },
        restore_from_git: -> { @actions[:restore].restore_from_git(issue) }
      }
    end

    def tracking_actions(issue)
      {
        track_migration: -> { @actions[:tracking].track_migration(issue) },
        consolidate_records: -> { @actions[:tracking].consolidate_records(issue) },
        remove_duplicates: -> { @actions[:tracking].remove_duplicates(issue) }
      }
    end

    def schema_actions(issue)
      {
        remove_from_schema: -> { @actions[:schema].remove_from_schema(issue) },
        reapply_migration: -> { @actions[:schema].reapply_migration(issue) }
      }
    end

    def manual_actions(issue)
      {
        manual_intervention: -> { @actions[:manual].show(issue) }
      }
    end

    def unknown_option?(recovery_method)
      Rails.logger&.error "Unknown recovery option: #{recovery_method}"
      false
    end

    def prompt_for_option(issue)
      display_options(issue)
      get_user_choice(issue)
    end

    def display_options(issue)
      display_header(issue)
      display_recovery_options(issue)
      display_additional_options(issue)
    end

    def display_header(issue)
      Rails.logger&.debug { "\n#{Colorizer.info("Recovery options for #{issue[:type].to_s.humanize}:")}" }
      Rails.logger&.debug { "Version: #{issue[:version]}" }
      Rails.logger&.debug { "#{issue[:description]}\n\n" }
    end

    def display_recovery_options(issue)
      issue[:recovery_options].each_with_index do |option, index|
        Rails.logger&.debug "#{index + 1}. #{Recovery::OptionFormatter.format(option)}"
      end
    end

    def display_additional_options(issue)
      manual_index = issue[:recovery_options].size + 1
      Rails.logger&.debug { "#{manual_index}. Manual intervention (show SQL commands)" }
      Rails.logger&.debug "0. Skip this issue\n\n"
      Rails.logger&.debug { "Select option (0-#{manual_index}): " }
    end

    def get_user_choice(issue)
      choice = gets.chomp.to_i
      process_user_choice(choice, issue)
    end

    def process_user_choice(choice, issue)
      return nil if choice.zero?
      return :manual_intervention if choice == issue[:recovery_options].size + 1

      if choice.between?(1, issue[:recovery_options].size)
        issue[:recovery_options][choice - 1]
      else
        Rails.logger&.debug Colorizer.error("Invalid choice. Skipping...")
        nil
      end
    end
  end
end
