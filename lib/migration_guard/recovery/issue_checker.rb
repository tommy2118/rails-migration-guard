# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Base class for checking specific types of migration issues
    class IssueChecker
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

      def migration_file_exists?(version)
        Rails.root.glob("db/migrate/#{version}_*.rb").any?
      end

      def schema_versions
        ActiveRecord::Base.connection.select_values("SELECT version FROM schema_migrations")
      end

      def tracked_versions
        MigrationGuardRecord.pluck(:version)
      end
    end
  end
end
