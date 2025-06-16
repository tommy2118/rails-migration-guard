# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Handles schema-related recovery actions
    class SchemaAction < BaseAction
      def remove_from_schema(issue)
        version = issue[:version]
        log_info("Removing #{version} from schema_migrations...")

        execute_schema_deletion(version)
        log_success("✓ Removed from schema: #{version}")
        true
      rescue StandardError => e
        log_error("✗ Failed to remove from schema: #{e.message}")
        false
      end

      def reapply_migration(issue)
        migration = issue[:migration]
        version = migration.version
        log_info("Re-applying migration #{version}...")

        migration_file = find_migration_file(version)
        return file_not_found_error(version) unless migration_file

        run_migration(migration_file, version)
        update_reapply_status(migration)
        log_success("✓ Migration re-applied: #{version}")
        true
      rescue StandardError => e
        log_error("✗ Failed to re-apply migration: #{e.message}")
        false
      end

      private

      def execute_schema_deletion(version)
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql(
            ["DELETE FROM schema_migrations WHERE version = ?", version]
          )
        )
      end

      def find_migration_file(version)
        Rails.root.glob("db/migrate/#{version}_*.rb").first
      end

      def file_not_found_error(version) # rubocop:disable Naming/PredicateMethod
        log_error("Migration file not found for #{version}")
        false
      end

      def run_migration(migration_file, version)
        require migration_file
        migration_class = load_migration_class(migration_file)
        migration_instance = migration_class.new
        migration_instance.version = version
        migration_instance.migrate(:up)
      end

      def load_migration_class(migration_file)
        class_name = extract_migration_class_name(migration_file)
        class_name.constantize
      end

      def extract_migration_class_name(migration_file)
        File.basename(migration_file, ".rb")
            .split("_")[1..]
            .join("_")
            .camelize
      end

      def update_reapply_status(migration)
        update_migration_metadata(migration, "reapplied")
        migration.update!(status: "applied")
      end
    end
  end
end
