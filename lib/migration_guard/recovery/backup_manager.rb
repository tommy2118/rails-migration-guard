# frozen_string_literal: true

module MigrationGuard
  module Recovery
    # Manages database backups for recovery operations
    class BackupManager
      attr_reader :backup_path

      def initialize
        @backup_path = nil
      end

      def create_backup
        return skip_for_memory_database if using_memory_database?

        setup_backup_path
        Rails.logger.info Colorizer.info("Creating database backup...")

        adapter_name = ActiveRecord::Base.connection.adapter_name
        result = create_backup_for_adapter(adapter_name)

        return false if result == false

        verify_backup_creation(result)
      end

      def skip_for_memory_database # rubocop:disable Naming/PredicateMethod
        Rails.logger.info Colorizer.info("Skipping backup for in-memory database")
        @backup_path = nil
        false
      end

      def setup_backup_path
        timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
        @backup_path = Rails.root.join("tmp", "migration_recovery_backup_#{timestamp}.sql")
        FileUtils.mkdir_p(File.dirname(@backup_path))
      end

      def using_memory_database?
        config = database_config
        adapter_name = ActiveRecord::Base.connection.adapter_name

        # Check if SQLite with memory database
        if adapter_name =~ /sqlite/i
          source_path = config[:database]
          is_memory = memory_database?(source_path)
          return is_memory
        end

        false
      end

      def backup_exists?
        return false unless @backup_path

        File.exist?(@backup_path)
      end

      private

      def create_backup_for_adapter(adapter_name)
        case adapter_name
        when /postgresql/i
          create_postgres_backup
        when /mysql/i
          create_mysql_backup
        when /sqlite/i
          create_sqlite_backup
        else
          handle_unsupported_adapter(adapter_name)
        end
      end

      def verify_backup_creation(result) # rubocop:disable Naming/PredicateMethod
        if result && @backup_path && File.exist?(@backup_path)
          Rails.logger.info Colorizer.success("✓ Backup created: #{@backup_path}")
          true
        else
          # Don't log error for expected failures (like memory database)
          Rails.logger.error Colorizer.error("✗ Failed to create backup") unless result == false
          false
        end
      end

      def handle_unsupported_adapter(adapter_name) # rubocop:disable Naming/PredicateMethod
        Rails.logger.warn Colorizer.warning("Backup not supported for #{adapter_name}")
        @backup_path = nil
        false
      end

      def create_postgres_backup
        config = database_config
        command = build_postgres_command(config)
        env = postgres_environment(config)

        system(env, *command)
      end

      def build_postgres_command(config)
        [
          "pg_dump",
          "-h", config[:host] || "localhost",
          "-p", (config[:port] || 5432).to_s,
          "-U", config[:username],
          "-d", config[:database],
          "-f", @backup_path.to_s
        ].tap { |cmd| cmd << "-w" if config[:password].blank? }
      end

      def postgres_environment(config)
        config[:password] ? { "PGPASSWORD" => config[:password] } : {}
      end

      def create_mysql_backup
        config = database_config
        command = build_mysql_command(config)

        system(*command, out: @backup_path.to_s)
      end

      def build_mysql_command(config)
        [
          "mysqldump",
          "-h", config[:host] || "localhost",
          "-P", (config[:port] || 3306).to_s,
          "-u", config[:username],
          config[:database]
        ].tap { |cmd| cmd << "-p#{config[:password]}" if config[:password] }
      end

      def create_sqlite_backup
        config = database_config
        source_path = config[:database]

        return handle_memory_database if memory_database?(source_path)

        # Ensure the source file exists before copying
        unless File.exist?(source_path)
          Rails.logger.error "SQLite database file not found: #{source_path}"
          return false
        end

        FileUtils.cp(source_path, @backup_path)
        true
      end

      def memory_database?(path)
        path.to_s == ":memory:" || path.nil?
      end

      def handle_memory_database # rubocop:disable Naming/PredicateMethod
        Rails.logger.warn "Cannot backup in-memory database"
        @backup_path = nil
        false
      end

      def database_config
        ActiveRecord::Base.connection_db_config.configuration_hash
      end
    end
  end
end
