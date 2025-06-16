# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::Recovery::BackupManager do
  let(:backup_manager) { described_class.new }
  let(:timestamp) { "20240116_120000" }

  before do
    allow(Time).to receive(:current).and_return(Time.zone.parse("2024-01-16 12:00:00"))
    allow(FileUtils).to receive(:mkdir_p)
  end

  describe "#create_backup" do
    context "with in-memory database" do
      before do
        allow(backup_manager).to receive(:using_memory_database?).and_return(true)
      end

      it "skips backup creation" do
        expect(Rails.logger).to receive(:info).with(/Skipping backup for in-memory database/)

        result = backup_manager.create_backup

        aggregate_failures do
          expect(result).to be false
          expect(backup_manager.backup_path).to be_nil
        end
      end
    end

    context "with PostgreSQL" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("PostgreSQL")
        allow(backup_manager).to receive_messages(using_memory_database?: false, database_config: {
                                                    adapter: "postgresql",
                                                    host: "localhost",
                                                    port: 5432,
                                                    username: "testuser",
                                                    password: "testpass",
                                                    database: "test_db"
                                                  })
      end

      it "creates backup using pg_dump" do
        expected_path = Rails.root.join("tmp", "migration_recovery_backup_#{timestamp}.sql")
        expected_command = [
          "pg_dump",
          "-h", "localhost",
          "-p", "5432",
          "-U", "testuser",
          "-d", "test_db",
          "-f", expected_path.to_s
        ]
        expected_env = { "PGPASSWORD" => "testpass" }

        expect(backup_manager).to receive(:system).with(expected_env, *expected_command).and_return(true)
        allow(File).to receive(:exist?).with(expected_path).and_return(true)

        result = backup_manager.create_backup

        aggregate_failures do
          expect(result).to be true
          expect(backup_manager.backup_path).to eq(expected_path)
        end
      end

      it "handles missing password" do
        allow(backup_manager).to receive(:database_config).and_return({
                                                                        adapter: "postgresql",
                                                                        host: "localhost",
                                                                        username: "testuser",
                                                                        database: "test_db"
                                                                      })

        expected_path = Rails.root.join("tmp", "migration_recovery_backup_#{timestamp}.sql")
        expected_command = [
          "pg_dump", "-h", "localhost", "-p", "5432", "-U", "testuser",
          "-d", "test_db", "-f", expected_path.to_s, "-w"
        ]

        expect(backup_manager).to receive(:system).with({}, *expected_command).and_return(true)
        allow(File).to receive(:exist?).with(expected_path).and_return(true)

        backup_manager.create_backup
      end

      it "handles backup failure" do
        expect(backup_manager).to receive(:system).and_return(nil)
        allow(File).to receive(:exist?).and_return(false)
        expect(Rails.logger).to receive(:error).with(/Failed to create backup/)

        result = backup_manager.create_backup
        expect(result).to be false
      end
    end

    context "with MySQL" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("Mysql2")
        allow(backup_manager).to receive_messages(using_memory_database?: false, database_config: {
                                                    adapter: "mysql2",
                                                    host: "localhost",
                                                    port: 3306,
                                                    username: "testuser",
                                                    password: "testpass",
                                                    database: "test_db"
                                                  })
      end

      it "creates backup using mysqldump" do
        expected_path = Rails.root.join("tmp", "migration_recovery_backup_#{timestamp}.sql")
        expected_command = [
          "mysqldump",
          "-h", "localhost",
          "-P", "3306",
          "-u", "testuser",
          "test_db",
          "-ptestpass"
        ]

        expect(backup_manager).to receive(:system).with(*expected_command, out: expected_path.to_s).and_return(true)
        allow(File).to receive(:exist?).with(expected_path).and_return(true)

        result = backup_manager.create_backup

        aggregate_failures do
          expect(result).to be true
          expect(backup_manager.backup_path).to eq(expected_path)
        end
      end

      it "handles custom port" do
        allow(backup_manager).to receive(:database_config).and_return(
          {
            adapter: "mysql2",
            host: "localhost",
            port: 3307,
            username: "testuser",
            database: "test_db"
          }
        )

        expected_command = [
          "mysqldump",
          "-h", "localhost",
          "-P", "3307",
          "-u", "testuser",
          "test_db"
        ]

        expect(backup_manager).to receive(:system).with(*expected_command, out: anything).and_return(true)
        allow(File).to receive(:exist?).and_return(true)

        backup_manager.create_backup
      end
    end

    context "with SQLite" do
      let(:db_path) { Rails.root.join("db/test.sqlite3") }

      before do
        allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("SQLite")
        allow(backup_manager).to receive_messages(using_memory_database?: false, database_config: {
                                                    adapter: "sqlite3",
                                                    database: db_path.to_s
                                                  })
      end

      it "creates backup by copying file" do
        expected_path = Rails.root.join("tmp", "migration_recovery_backup_#{timestamp}.sql")
        allow(File).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).with(db_path.to_s).and_return(true)
        allow(File).to receive(:exist?).with(expected_path).and_return(true)
        expect(FileUtils).to receive(:cp).with(db_path.to_s, expected_path)

        result = backup_manager.create_backup

        aggregate_failures do
          expect(result).to be true
          expect(backup_manager.backup_path).to eq(expected_path)
        end
      end

      it "handles missing database file" do
        allow(File).to receive(:exist?).and_return(false)
        allow(File).to receive(:exist?).with(db_path.to_s).and_return(false)
        expect(Rails.logger).to receive(:error).with(/SQLite database file not found/)

        result = backup_manager.create_backup
        expect(result).to be false
      end

      it "handles memory database" do
        allow(backup_manager).to receive(:database_config).and_return(
          {
            adapter: "sqlite3",
            database: ":memory:"
          }
        )

        expect(Rails.logger).to receive(:warn).with(/Cannot backup in-memory database/)

        result = backup_manager.create_backup

        aggregate_failures do
          expect(result).to be false
          expect(backup_manager.backup_path).to be_nil
        end
      end
    end

    context "with unsupported adapter" do
      before do
        allow(backup_manager).to receive(:using_memory_database?).and_return(false)
        allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("UnknownDB")
      end

      it "logs warning and returns false" do
        expect(Rails.logger).to receive(:warn).with(/Backup not supported for UnknownDB/)

        result = backup_manager.create_backup

        aggregate_failures do
          expect(result).to be false
          expect(backup_manager.backup_path).to be_nil
        end
      end
    end
  end

  describe "#using_memory_database?" do
    context "with SQLite" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("SQLite")
      end

      it "returns true for :memory: database" do
        allow(backup_manager).to receive(:database_config).and_return(
          { database: ":memory:" }
        )

        expect(backup_manager.using_memory_database?).to be true
      end

      it "returns true for nil database" do
        allow(backup_manager).to receive(:database_config).and_return(
          { database: nil }
        )

        expect(backup_manager.using_memory_database?).to be true
      end

      it "returns false for file-based database" do
        allow(backup_manager).to receive(:database_config).and_return(
          { database: "db/test.sqlite3" }
        )

        expect(backup_manager.using_memory_database?).to be false
      end
    end

    context "with other adapters" do
      it "returns false for PostgreSQL" do
        allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("PostgreSQL")
        allow(backup_manager).to receive(:database_config).and_return(
          { adapter: "postgresql", database: "test_db" }
        )

        expect(backup_manager.using_memory_database?).to be false
      end

      it "returns false for MySQL" do
        allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("Mysql2")
        allow(backup_manager).to receive(:database_config).and_return(
          { adapter: "mysql2", database: "test_db" }
        )

        expect(backup_manager.using_memory_database?).to be false
      end
    end
  end

  describe "#backup_exists?" do
    it "returns true when backup path exists" do
      backup_manager.instance_variable_set(:@backup_path, "/tmp/backup.sql")
      allow(File).to receive(:exist?).with("/tmp/backup.sql").and_return(true)

      expect(backup_manager.backup_exists?).to be true
    end

    it "returns false when backup path is nil" do
      expect(backup_manager.backup_exists?).to be(false)
    end

    it "returns false when backup file doesn't exist" do
      backup_manager.instance_variable_set(:@backup_path, "/tmp/backup.sql")
      allow(File).to receive(:exist?).with("/tmp/backup.sql").and_return(false)

      expect(backup_manager.backup_exists?).to be(false)
    end
  end

  describe "#setup_backup_path" do
    it "creates backup path with timestamp" do
      expected_path = Rails.root.join("tmp", "migration_recovery_backup_#{timestamp}.sql")
      expect(FileUtils).to receive(:mkdir_p).with(Rails.root.join("tmp").to_s)

      backup_manager.setup_backup_path
      expect(backup_manager.backup_path).to eq(expected_path)
    end
  end

  describe "#skip_for_memory_database" do
    it "logs info and resets backup path" do
      backup_manager.instance_variable_set(:@backup_path, "/tmp/backup.sql")
      expect(Rails.logger).to receive(:info).with(/Skipping backup for in-memory database/)

      result = backup_manager.skip_for_memory_database

      aggregate_failures do
        expect(result).to be false
        expect(backup_manager.backup_path).to be_nil
      end
    end
  end
end
