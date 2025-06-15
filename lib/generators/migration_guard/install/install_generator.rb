# frozen_string_literal: true

require "rails/generators"
require "rails/generators/migration"

module MigrationGuard
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Creates a MigrationGuard initializer and migration for your application"

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def create_initializer_file
        template "migration_guard.rb", "config/initializers/migration_guard.rb"
      end

      def create_migration_file
        migration_template "create_migration_guard_records.rb", "db/migrate/create_migration_guard_records.rb"
      end

      def display_post_install_message
        readme "README" if behavior == :invoke
      end
    end
  end
end
