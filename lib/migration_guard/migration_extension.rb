# frozen_string_literal: true

module MigrationGuard
  module MigrationExtension
    def self.prepended(base)
      base.singleton_class.prepend(ClassMethods)
    end

    module ClassMethods
      def migrate(direction)
        result = super
        
        if MigrationGuard.enabled? && respond_to?(:version)
          tracker = MigrationGuard::Tracker.new
          tracker.track_migration(version.to_s, direction)
        end
        
        result
      end
    end

    def migrate(direction)
      result = super
      
      if MigrationGuard.enabled? && respond_to?(:version)
        tracker = MigrationGuard::Tracker.new
        tracker.track_migration(version.to_s, direction)
      end
      
      result
    end

    def exec_migration(conn, direction)
      if MigrationGuard.enabled? && MigrationGuard.configuration.sandbox_mode && direction == :up
        puts "[MigrationGuard] Running migration #{version} in sandbox mode..."
        conn.transaction(requires_new: true) do
          super
          puts "[MigrationGuard] Migration would succeed. Rolling back sandbox..."
          raise ActiveRecord::Rollback
        end
        puts "[MigrationGuard] Sandbox rollback complete. Run without sandbox to apply."
      else
        super
      end
    end
  end
end

# Prepend the extension to ActiveRecord::Migration
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Migration.prepend(MigrationGuard::MigrationExtension)
end