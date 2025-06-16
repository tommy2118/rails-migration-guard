# frozen_string_literal: true

require "rails_helper"
require "generators/migration_guard/install/install_generator"
require "fileutils"
require "tmpdir"

RSpec.describe MigrationGuard::Generators::InstallGenerator do
  let(:destination_root) { Dir.mktmpdir }
  let(:generator) { described_class.new([], {}, destination_root: destination_root) }

  before do
    FileUtils.mkdir_p(File.join(destination_root, "config", "initializers"))
    FileUtils.mkdir_p(File.join(destination_root, "db", "migrate"))
    allow(Rails).to receive(:version).and_return("7.0.0")
    allow(generator).to receive(:say)
  end

  after do
    FileUtils.remove_entry(destination_root)
  end

  describe "Rails version check" do
    it "passes with Rails 6.1+" do
      allow(Rails).to receive(:version).and_return("6.1.0")

      expect { generator.check_rails_version }.not_to raise_error
    end

    it "fails with Rails < 6.1" do
      allow(Rails).to receive(:version).and_return("6.0.0")

      expect do
        generator.check_rails_version
      end.to raise_error(Thor::Error, "Rails version requirement not met")
    end
  end

  describe "file generation" do
    let(:templates_path) { File.expand_path("../../../lib/generators/migration_guard/install/templates", __dir__) }

    before do
      allow(generator).to receive(:template) do |source, dest|
        template_path = File.join(templates_path, source)
        destination_path = File.join(destination_root, dest)

        FileUtils.mkdir_p(File.dirname(destination_path))
        FileUtils.cp(template_path, destination_path)
      end

      allow(generator).to receive(:migration_template) do |source, dest|
        template_path = File.join(templates_path, source)
        timestamp = Time.current.strftime("%Y%m%d%H%M%S")
        migration_name = File.basename(dest, ".rb")
        destination_path = File.join(destination_root, "db", "migrate", "#{timestamp}_#{migration_name}.rb")

        FileUtils.mkdir_p(File.dirname(destination_path))

        # Process ERB template
        content = File.read(template_path)
        processed_content = content.gsub(/<%= ActiveRecord::Migration.current_version %>/, "7.0")
        File.write(destination_path, processed_content)
      end

      generator.create_initializer_file
      generator.create_migration_file
    end

    it "creates initializer file" do
      initializer_path = File.join(destination_root, "config", "initializers", "migration_guard.rb")

      expect(File.exist?(initializer_path)).to be true

      content = File.read(initializer_path)
      aggregate_failures do
        expect(content).to include("MigrationGuard.configure")
        expect(content).to include("config.enabled_environments = %i[development staging]")
        expect(content).to include("config.git_integration_level = :warning")
        expect(content).to include("config.track_branch = true")
      end
    end

    it "creates migration file" do
      migration_files = Dir.glob(File.join(destination_root, "db", "migrate", "*_create_migration_guard_records.rb"))

      expect(migration_files).not_to be_empty

      content = File.read(migration_files.first)
      aggregate_failures do
        expect(content).to include("class CreateMigrationGuardRecords")
        expect(content).to include("create_table :migration_guard_records")
        expect(content).to include("t.string :version, null: false")
        expect(content).to include("t.string :branch")
        expect(content).to include("t.string :author")
        expect(content).to include("t.string :status")
        expect(content).to include("t.index :version, unique: true")
        expect(content).to include("def down")
        expect(content).to include("drop_table :migration_guard_records")
      end
    end

    it "creates database-specific metadata column" do
      migration_files = Dir.glob(File.join(destination_root, "db", "migrate", "*_create_migration_guard_records.rb"))
      content = File.read(migration_files.first)

      aggregate_failures do
        expect(content).to include("if connection.adapter_name.match?(/PostgreSQL|MySQL/)")
        expect(content).to include("t.json :metadata")
        expect(content).to include("t.text :metadata")
      end
    end
  end

  describe "success message" do
    it "displays installation success message" do
      allow(generator).to receive(:readme)

      generator.display_post_install_message

      expect(generator).to have_received(:readme).with("README")
    end
  end
end
