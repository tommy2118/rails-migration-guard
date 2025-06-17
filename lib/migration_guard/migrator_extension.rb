# frozen_string_literal: true

module MigrationGuard
  # Extensions to ActiveRecord::Migrator to detect batch migrations
  module MigratorExtension
    def migrate
      # Start batch tracking if warnings are enabled
      if MigrationGuard.enabled? && MigrationGuard.configuration.warn_after_migration
        MigrationGuard::WarningCollector.start_batch
      end

      result = super

      # End batch and show consolidated warnings if needed
      if MigrationGuard.enabled? && MigrationGuard.configuration.warn_after_migration
        MigrationGuard::WarningCollector.end_batch
      end

      result
    rescue StandardError => e
      # Ensure we reset the batch state on error
      MigrationGuard::WarningCollector.reset! if MigrationGuard.enabled?
      raise e
    end
  end
end

# Prepend the extension to ActiveRecord::Migrator
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Migrator.prepend(MigrationGuard::MigratorExtension) if defined?(ActiveRecord::Migrator)
end
