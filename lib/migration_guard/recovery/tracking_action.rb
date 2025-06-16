# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Handles tracking-related recovery actions
    class TrackingAction < BaseAction
      def track_migration(issue)
        version = issue[:version]
        log_info("Tracking migration #{version}...")

        create_tracking_record(version)
        log_success("✓ Migration tracked: #{version}")
        true
      rescue StandardError => e
        log_error("✗ Failed to track migration: #{e.message}")
        false
      end

      def consolidate_records(issue)
        version = issue[:version]
        records = issue[:migrations]
        log_info("Consolidating #{records.count} records for version #{version}...")

        perform_consolidation(records)
        log_success("✓ Consolidated #{records.count} records into one")
        true
      rescue StandardError => e
        log_error("✗ Failed to consolidate records: #{e.message}")
        false
      end

      def remove_duplicates(issue)
        version = issue[:version]
        records = issue[:migrations]
        log_info("Removing duplicate records for version #{version}...")

        count = perform_duplicate_removal(records)
        log_success("✓ Removed #{count} duplicate records")
        true
      rescue StandardError => e
        log_error("✗ Failed to remove duplicates: #{e.message}")
        false
      end

      private

      def create_tracking_record(version)
        MigrationGuardRecord.create!(
          version: version,
          branch: current_branch,
          author: current_author,
          status: "applied",
          metadata: {
            "recovery_action" => "tracked_retrospectively",
            "tracked_at" => Time.current.iso8601
          }
        )
      end

      def current_branch
        @git_integration.current_branch
      rescue StandardError
        "unknown"
      end

      def current_author
        @git_integration.current_author
      rescue StandardError
        nil
      end

      def perform_consolidation(records)
        # Convert to relation if it's an array
        records = MigrationGuardRecord.where(id: records.map(&:id)) if records.is_a?(Array)

        keeper = records.order(updated_at: :desc).first
        others = records.where.not(id: keeper.id)

        metadata = build_consolidated_metadata(records)
        
        # Skip validation to allow updating duplicate version records
        keeper.metadata = metadata
        keeper.save!(validate: false)
        
        others.destroy_all
      end

      def build_consolidated_metadata(records)
        merged_metadata = {}
        records.each { |r| merged_metadata.merge!(r.metadata || {}) }

        # Track which records were consolidated
        consolidated_from = records.map { |r| { "id" => r.id, "branch" => r.branch } }

        merged_metadata.merge(
          "consolidated_at" => Time.current.iso8601,
          "consolidated_from_count" => records.count.to_s,
          "consolidated_from" => consolidated_from
        )
      end

      def perform_duplicate_removal(records)
        # Convert to relation if it's an array
        records = MigrationGuardRecord.where(id: records.map(&:id)) if records.is_a?(Array)

        keeper = find_keeper_record(records)
        others = records.where.not(id: keeper.id)
        count = others.count
        others.destroy_all
        count
      end

      def find_keeper_record(records)
        records.find { |r| r.status == "applied" } ||
          records.order(updated_at: :desc).first
      end
    end
  end
end
