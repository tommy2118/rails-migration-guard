# frozen_string_literal: true

require "migration_guard/colorizer"
require "migration_guard/interactive_mode"
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
  # rubocop:disable Metrics/ClassLength
  class RecoveryExecutor
    def initialize(interactive: true)
      # Use centralized interactive mode detection
      @interactive = InteractiveMode.interactive?(requested_interactive: interactive)
      @backup_manager = Recovery::BackupManager.new
      @actions = initialize_actions
      @executing_recovery = false

      # Log TTY detection if needed
      InteractiveMode.log_tty_detection(interactive, @interactive, :rails_logger)
    end

    def execute_recovery(issue, option = nil)
      return false if executing_recovery?

      # Check for concurrent recovery processes
      check_concurrent_recovery!
      create_recovery_lock

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
      clear_recovery_lock
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
      input = gets

      raise RecoveryError, "No input available. If running in non-interactive mode, use AUTO=true" if input.nil?

      choice = input.chomp.to_i
      process_user_choice(choice, issue)
    rescue Interrupt
      Rails.logger&.info "\nRecovery cancelled by user"
      raise RecoveryError, "Recovery cancelled by user"
    rescue SystemCallError => e
      raise RecoveryError, "Failed to read user input: #{e.message}"
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

    def recovery_lock_file
      Rails.root.join("tmp/migration_guard_recovery.lock")
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def check_concurrent_recovery!
      return unless File.exist?(recovery_lock_file)

      begin
        lock_content = File.read(recovery_lock_file)
        lock_data = JSON.parse(lock_content)

        # Check if lock is stale (older than 30 minutes)
        lock_time = Time.zone.parse(lock_data["created_at"])
        if Time.current - lock_time > 30.minutes
          Rails.logger&.warn "Removing stale recovery lock file (older than 30 minutes)"
          File.delete(recovery_lock_file)
          return
        end

        raise ConcurrentAccessError, "Another recovery process is running (PID: #{lock_data['pid']}). " \
                                     "Started at: #{lock_data['created_at']}. " \
                                     "If this is incorrect, delete #{recovery_lock_file}"
      rescue JSON::ParserError
        # Invalid lock file, remove it
        File.delete(recovery_lock_file)
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def create_recovery_lock
      FileUtils.mkdir_p(File.dirname(recovery_lock_file))

      lock_data = {
        pid: Process.pid,
        created_at: Time.current.iso8601,
        user: ENV["USER"] || "unknown"
      }

      File.write(recovery_lock_file, JSON.pretty_generate(lock_data))
    rescue SystemCallError => e
      Rails.logger&.warn "Failed to create recovery lock file: #{e.message}"
    end

    def clear_recovery_lock
      FileUtils.rm_f(recovery_lock_file)
    rescue SystemCallError => e
      Rails.logger&.warn "Failed to remove recovery lock file: #{e.message}"
    end
  end
  # rubocop:enable Metrics/ClassLength
end
