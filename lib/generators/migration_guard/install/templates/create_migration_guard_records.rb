# frozen_string_literal: true

class CreateMigrationGuardRecords < ActiveRecord::Migration[<%= ActiveRecord::Migration.current_version %>]
  def change
    create_table :migration_guard_records do |t|
      t.string :version, null: false
      t.string :branch
      t.string :author
      t.string :status
      
      # Use json for PostgreSQL/MySQL 5.7+, text for others
      if connection.adapter_name.match?(/PostgreSQL|MySQL/)
        t.json :metadata
      else
        t.text :metadata
      end
      
      t.timestamps

      t.index :version, unique: true
      t.index :status
      t.index :created_at
      t.index [:branch, :status]
    end
  end

  def down
    drop_table :migration_guard_records
  end
end