# frozen_string_literal: true

# Sample migration for testing
class SampleMigration < ActiveRecord::Migration[7.0]
  def change
    create_table :sample_table do |t|
      t.string :name
      t.text :description
      t.integer :count, default: 0
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :sample_table, :name
    add_index :sample_table, :created_at
  end
end
