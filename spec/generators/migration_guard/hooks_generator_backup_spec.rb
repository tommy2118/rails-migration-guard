# frozen_string_literal: true

require "rails_helper"
require "generators/migration_guard/hooks/hooks_generator"
require "fileutils"
require "tmpdir"

RSpec.describe "MigrationGuard::Generators::HooksGenerator backup functionality" do
  let(:destination_root) { Dir.mktmpdir }

  around do |example|
    Dir.chdir(destination_root) do
      example.run
    end
  end

  before do
    FileUtils.mkdir_p(".git/hooks")
  end

  after do
    FileUtils.remove_entry(destination_root)
  end

  describe "backup creation" do
    let(:existing_hook_content) { "#!/bin/sh\n# Custom hook\necho 'custom hook'" }
    let(:hook_path) { ".git/hooks/post-checkout" }
    let(:backup_path) { ".git/hooks/post-checkout.backup" }

    before do
      File.write(hook_path, existing_hook_content)
      File.chmod(0o755, hook_path)
    end

    it "creates a backup of existing hook" do
      generator = MigrationGuard::Generators::HooksGenerator.new
      
      # Silence output for cleaner test
      allow(generator).to receive(:say)
      allow(generator).to receive(:say_status)
      
      generator.send(:create_git_hook, "post-checkout", "new content")
      
      expect(File.exist?(backup_path)).to be true
      expect(File.read(backup_path)).to eq(existing_hook_content)
    end

    it "preserves file permissions in backup" do
      generator = MigrationGuard::Generators::HooksGenerator.new
      
      # Silence output
      allow(generator).to receive(:say)
      allow(generator).to receive(:say_status)
      
      generator.send(:create_git_hook, "post-checkout", "new content")
      
      backup_stat = File.stat(backup_path)
      
      # Check that backup has same permissions as original had
      expect(backup_stat.mode & 0o777).to eq(0o755)
    end

    it "overwrites existing backup if present" do
      # Create an old backup
      old_backup_content = "#!/bin/sh\n# Old backup"
      File.write(backup_path, old_backup_content)
      
      generator = MigrationGuard::Generators::HooksGenerator.new
      
      # Silence output
      allow(generator).to receive(:say)
      allow(generator).to receive(:say_status)
      
      generator.send(:create_git_hook, "post-checkout", "new content")
      
      # Backup should contain the current hook content, not the old backup
      expect(File.read(backup_path)).to eq(existing_hook_content)
      expect(File.read(backup_path)).not_to eq(old_backup_content)
    end
  end

  describe "error handling during backup" do
    it "handles read-only hooks directory gracefully" do
      hook_path = ".git/hooks/post-checkout"
      File.write(hook_path, "existing content")
      
      # Make hooks directory read-only
      File.chmod(0o555, ".git/hooks")
      
      generator = MigrationGuard::Generators::HooksGenerator.new
      
      # Should raise an error when trying to create backup
      expect {
        generator.send(:create_git_hook, "post-checkout", "new content")
      }.to raise_error(Errno::EACCES)
      
      # Restore permissions for cleanup
      File.chmod(0o755, ".git/hooks")
    end
  end
end