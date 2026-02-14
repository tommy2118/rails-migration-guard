# frozen_string_literal: true

module MigrationGuard
  module SchemaInspector
    def fetch_schema_migrations
      ActiveRecord::Base.connection.select_values("SELECT version FROM schema_migrations")
    rescue StandardError
      []
    end

    def migration_file_paths
      return ["db/migrate"] unless defined?(Rails) && Rails.respond_to?(:application)
      return ["db/migrate"] unless Rails.application

      config_paths = Rails.application.config.paths
      return ["db/migrate"] unless config_paths.respond_to?(:[])

      config_paths["db/migrate"] || ["db/migrate"]
    rescue StandardError
      ["db/migrate"]
    end
  end
end
