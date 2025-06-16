# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Base class for all recovery actions
    class BaseAction
      attr_reader :git_integration

      def initialize
        @git_integration = GitIntegration.new
      end

      protected

      def migration_exists_in_schema?(version)
        ActiveRecord::Base.connection.select_value(
          ActiveRecord::Base.sanitize_sql(
            ["SELECT 1 FROM schema_migrations WHERE version = ?", version]
          )
        ).present?
      end

      def update_migration_metadata(migration, action_name, additional_metadata = {})
        metadata = migration.metadata.merge(
          "recovery_action" => action_name,
          "recovered_at" => Time.current.iso8601
        ).merge(additional_metadata)

        migration.update!(metadata: metadata)
      end

      def log_success(message)
        Rails.logger.info Colorizer.success(message)
      end

      def log_error(message)
        Rails.logger.error Colorizer.error(message)
      end

      def log_info(message)
        Rails.logger.info Colorizer.info(message)
      end
    end
  end
end
