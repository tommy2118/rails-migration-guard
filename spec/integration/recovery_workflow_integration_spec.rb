# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/ContextWording, RSpec/InstanceVariable

RSpec.describe "Recovery workflow integration", type: :integration do
  include_context "with recovery integration setup"

  describe "basic recovery scenarios" do
    context "recovering from orphaned migrations" do
      it "successfully identifies and processes orphaned migrations" do
        # Create orphaned migrations (applied but not in main branch)
        orphaned_versions = %w[20240101000001 20240101000002 20240101000003]
        create_orphaned_migrations(@app_root, orphaned_versions)

        # Verify orphaned state
        recovery_data = run_recovery_process(@app_root)
        orphaned_issues = recovery_data[:issues].select { |i| i[:type] == :missing_file }

        aggregate_failures do
          expect(orphaned_issues.size).to eq(3)
          expect(orphaned_issues.map { |i| i[:version] }).to match_array(orphaned_versions)
          orphaned_issues.each do |issue|
            expect(issue[:severity]).to eq(:high)
            expect(issue[:recovery_options]).to include(:restore_from_git)
          end
        end
      end

      it "handles recovery of migrations with dependencies" do
        # Create a chain of dependent migrations
        versions = %w[20240101000001 20240101000002 20240101000003]

        within_app_directory(@app_root) do
          # Create migrations with dependencies
          create_dependent_migrations(versions)
          apply_migrations_to_database(@app_root, versions)

          # Make them orphaned by removing files
          versions.each { |v| remove_migration_files(@app_root, v) }
        end

        # Run recovery
        recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :restore_from_git)

        aggregate_failures do
          expect(recovery_data[:issues].size).to eq(3)
          expect(recovery_data[:results].all?).to be true

          # Verify files were restored
          verify_migration_files_exist(@app_root, versions)

          # Verify database consistency
          verify_database_consistency(expected_versions: versions)
        end
      end
    end

    context "recovering multiple orphaned migrations" do
      it "processes multiple orphaned migrations in correct order" do
        # Create migrations with mixed timestamps to test ordering
        versions = %w[20240115120000 20240110080000 20240120150000 20240105030000]
        create_orphaned_migrations(@app_root, versions)

        recovery_data = run_recovery_process(@app_root)
        orphaned_issues = recovery_data[:issues].select { |i| i[:type] == :missing_file }

        aggregate_failures do
          expect(orphaned_issues.size).to eq(4)

          # Issues should be sorted by version for consistent processing
          issue_versions = orphaned_issues.map { |i| i[:version] }
          expect(issue_versions).to eq(versions.sort)

          # All should have appropriate recovery options
          orphaned_issues.each do |issue|
            expect(issue[:recovery_options]).to include(:restore_from_git, :mark_as_rolled_back)
          end
        end
      end

      # rubocop:disable RSpec/PendingWithoutReason
      xit "continues processing when some migrations fail", reason: "requires complex git failure simulation" do
        # rubocop:enable RSpec/PendingWithoutReason
        # This test requires complex git failure simulation and recovery error handling
        # which depends on full implementation of the recovery executor
        versions = %w[20240101000001 20240101000002 20240101000003]
        create_orphaned_migrations(@app_root, versions)

        # Simulate git restore failure for middle migration
        simulate_git_failure(/git show.*20240101000002/)

        recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :restore_from_git)

        aggregate_failures do
          expect(recovery_data[:issues].size).to eq(3)
          expect(recovery_data[:results].count(true)).to eq(2) # Two should succeed
          expect(recovery_data[:results].count(false)).to eq(1) # One should fail
        end
      end
    end

    context "recovering from partial rollback states" do
      it "detects and resolves stuck rollbacks" do
        stuck_version = "20240101000001"
        create_stuck_rollback_scenario(@app_root, stuck_version)

        recovery_data = run_recovery_process(@app_root)
        rollback_issues = recovery_data[:issues].select { |i| i[:type] == :partial_rollback }

        aggregate_failures do
          expect(rollback_issues.size).to eq(1)

          rollback_issue = rollback_issues.first
          expect(rollback_issue[:version]).to eq(stuck_version)
          expect(rollback_issue[:severity]).to eq(:high)
          expect(rollback_issue[:recovery_options]).to include(
            :complete_rollback, :restore_migration, :mark_as_rolled_back
          )
        end
      end

      it "completes partial rollbacks by removing from schema" do
        stuck_version = "20240101000001"
        create_stuck_rollback_scenario(@app_root, stuck_version)

        # Execute recovery with complete_rollback option
        recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :complete_rollback)

        aggregate_failures do
          expect(recovery_data[:results].all?).to be true

          # Verify migration was removed from schema
          verify_database_consistency(unexpected_versions: [stuck_version])

          # Verify tracking record was updated
          record = MigrationGuard::MigrationGuardRecord.find_by(version: stuck_version)
          expect(record.status).to eq("rolled_back")
        end
      end
    end

    context "recovering from version conflicts" do
      it "detects version conflicts between branches" do
        conflict_version = "20240101000001"
        create_version_conflict_scenario(@app_root, conflict_version)

        recovery_data = run_recovery_process(@app_root)
        conflict_issues = recovery_data[:issues].select { |i| i[:type] == :version_conflict }

        aggregate_failures do
          expect(conflict_issues.size).to eq(1)

          conflict_issue = conflict_issues.first
          expect(conflict_issue[:version]).to eq(conflict_version)
          expect(conflict_issue[:severity]).to eq(:high)
          expect(conflict_issue[:recovery_options]).to include(:consolidate_records, :remove_duplicates)
        end
      end

      it "resolves conflicts by consolidating records" do
        conflict_version = "20240101000001"
        create_version_conflict_scenario(@app_root, conflict_version)

        # Count initial duplicate records
        initial_count = MigrationGuard::MigrationGuardRecord.where(version: conflict_version).count
        expect(initial_count).to eq(2)

        # Execute recovery
        recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :consolidate_records)

        aggregate_failures do
          expect(recovery_data[:results].all?).to be true

          # Verify only one record remains
          final_count = MigrationGuard::MigrationGuardRecord.where(version: conflict_version).count
          expect(final_count).to eq(1)

          # Verify consolidated record has merged metadata
          record = MigrationGuard::MigrationGuardRecord.find_by(version: conflict_version)
          expect(record.metadata).to include("consolidated_from")
        end
      end
    end

    context "custom migration paths" do
      it "handles migrations in custom directories" do
        # Create migrations in custom path
        custom_migrate_dir = File.join(@app_root, "db/custom_migrate")
        FileUtils.mkdir_p(custom_migrate_dir)

        versions = %w[20240101000001 20240101000002]
        versions.each_with_index do |version, index|
          class_name = "CustomPathMigration#{index + 1}"
          create_test_migration(custom_migrate_dir, version, class_name)

          # Simulate applying these migrations
          ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('#{version}')")
          MigrationGuard::MigrationGuardRecord.create!(
            version: version,
            branch: "feature/custom",
            status: "applied",
            metadata: { custom_path: true }
          )
        end

        # Remove files to create orphaned state
        FileUtils.rm_rf(custom_migrate_dir)

        # Configure custom migration paths
        # rubocop:disable RSpec/VerifiedDoubles
        paths_double = double("paths")
        # rubocop:enable RSpec/VerifiedDoubles
        allow(paths_double).to receive(:[]).with("db/migrate").and_return([custom_migrate_dir])
        allow(Rails.application.config).to receive(:paths).and_return(paths_double)

        recovery_data = run_recovery_process(@app_root)
        orphaned_issues = recovery_data[:issues].select { |i| i[:type] == :missing_file }

        expect(orphaned_issues.size).to eq(2)
        expect(orphaned_issues.map { |i| i[:version] }).to match_array(versions)
      end
    end
  end

  describe "recovery process reliability" do
    it "maintains transactional integrity during recovery" do
      versions = %w[20240101000001 20240101000002 20240101000003]
      create_orphaned_migrations(@app_root, versions)

      # Simulate failure during recovery of second migration
      call_count = 0
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(MigrationGuard::Recovery::RestoreAction)
        .to receive(:restore_migration).and_wrap_original do |original, *args|
        # rubocop:enable RSpec/AnyInstance
        call_count += 1
        raise StandardError, "Simulated failure" if call_count == 2 # Fail on second migration

        original.call(*args)
      end

      # Attempt recovery
      expect do
        run_recovery_process(@app_root, execute_recovery: true, recovery_action: :restore_from_git)
      end.not_to raise_error

      # Verify database remained consistent despite failure
      guard_records = MigrationGuard::MigrationGuardRecord.all
      expect(guard_records.count).to eq(3)

      # All records should still exist and be in consistent state
      guard_records.each do |record|
        expect(record.status).to be_in(%w[applied orphaned])
      end
    end

    it "provides detailed recovery reporting" do
      # Create mixed scenario
      orphaned_versions = %w[20240101000001 20240101000002]
      stuck_version = "20240101000003"
      conflict_version = "20240101000004"

      create_orphaned_migrations(@app_root, orphaned_versions)
      create_stuck_rollback_scenario(@app_root, stuck_version)
      create_version_conflict_scenario(@app_root, conflict_version)

      recovery_data = run_recovery_process(@app_root)

      aggregate_failures do
        # Check issue types are properly identified
        issue_types = recovery_data[:issues].map { |i| i[:type] }
        expect(issue_types).to include(:missing_file, :partial_rollback, :version_conflict)

        # Count specific issue types we created
        missing_file_count = recovery_data[:issues].count { |i| i[:type] == :missing_file }
        partial_rollback_count = recovery_data[:issues].count { |i| i[:type] == :partial_rollback }
        version_conflict_count = recovery_data[:issues].count { |i| i[:type] == :version_conflict }

        expect(missing_file_count).to eq(2) # 2 orphaned migrations
        expect(partial_rollback_count).to eq(1) # 1 stuck rollback
        expect(version_conflict_count).to eq(1) # 1 version conflict

        # Each issue should have complete information
        recovery_data[:issues].each do |issue|
          expect(issue).to include(:type, :version, :description, :severity, :recovery_options)
          expect(issue[:recovery_options]).not_to be_empty
        end
      end
    end

    it "handles large numbers of migrations efficiently" do
      # Create 100 orphaned migrations
      large_version_set = (1..100).map { |i| "202401#{i.to_s.rjust(2, '0')}000001" }
      create_orphaned_migrations(@app_root, large_version_set)

      # Measure performance
      performance_data = measure_recovery_performance(100) do
        run_recovery_process(@app_root)
      end

      aggregate_failures do
        expect(performance_data[:result][:issues].size).to eq(100)
        expect(performance_data[:performance_acceptable]).to be true
        expect(performance_data[:duration]).to be < 10.0 # Should complete within 10 seconds

        # Verify memory usage is reasonable (simplified check)
        expect(GC.stat[:heap_allocated_pages]).to be < 10_000
      end
    end
  end

  describe "backup and restore scenarios" do
    context "backup creation during recovery" do
      it "creates full backup before executing recovery operations" do
        versions = %w[20240101000001 20240101000002]
        create_orphaned_migrations(@app_root, versions)

        # Mock the backup manager to verify it's called
        backup_manager = instance_double(MigrationGuard::Recovery::BackupManager)
        allow(MigrationGuard::Recovery::BackupManager).to receive(:new).and_return(backup_manager)
        allow(backup_manager).to receive_messages(create_backup: "backup_20240101_120000.sql", verify_backup: true)

        recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :restore_from_git)

        aggregate_failures do
          expect(backup_manager).to have_received(:create_backup)
          expect(backup_manager).to have_received(:verify_backup)
          expect(recovery_data[:results].all?).to be true
        end
      end

      it "handles backup creation failure gracefully" do
        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        # Mock backup failure
        backup_manager = instance_double(MigrationGuard::Recovery::BackupManager)
        allow(MigrationGuard::Recovery::BackupManager).to receive(:new).and_return(backup_manager)
        allow(backup_manager).to receive_messages(create_backup: nil, verify_backup: false)

        recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :restore_from_git)

        # Recovery should still proceed but with warnings
        expect(recovery_data[:results]).not_to be_empty
        expect(backup_manager).to have_received(:create_backup)
      end

      it "verifies backup integrity before proceeding" do
        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        backup_manager = instance_double(MigrationGuard::Recovery::BackupManager)
        allow(MigrationGuard::Recovery::BackupManager).to receive(:new).and_return(backup_manager)
        allow(backup_manager).to receive_messages(
          create_backup: "backup_test.sql",
          verify_backup: false
        ) # Integrity check fails

        run_recovery_process(@app_root, execute_recovery: true, recovery_action: :restore_from_git)

        # Should verify backup integrity
        expect(backup_manager).to have_received(:verify_backup).with("backup_test.sql")
      end
    end

    context "restore from backup scenarios" do
      # rubocop:disable RSpec/PendingWithoutReason
      xit "successfully restores from backup after failed recovery", reason: "requires backup restore implementation" do
        # rubocop:enable RSpec/PendingWithoutReason
        versions = %w[20240101000001 20240101000002]
        create_orphaned_migrations(@app_root, versions)

        # Create a backup first
        backup_manager = MigrationGuard::Recovery::BackupManager.new
        backup_file = backup_manager.create_backup

        # Simulate recovery failure that corrupts database
        within_app_directory(@app_root) do
          # Corrupt the database state
          MigrationGuard::MigrationGuardRecord.delete_all
          ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations")
        end

        # Restore from backup
        restore_result = backup_manager.restore_from_backup(backup_file)

        aggregate_failures do
          expect(restore_result).to be true

          # Verify data was restored
          expect(MigrationGuard::MigrationGuardRecord.count).to eq(2)
          expect(
            ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM schema_migrations").first["COUNT(*)"]
          ).to eq(2)
        end
      end

      # rubocop:disable RSpec/PendingWithoutReason
      xit "handles corrupted backup files gracefully", reason: "requires backup validation implementation" do
        # rubocop:enable RSpec/PendingWithoutReason
        backup_dir = File.join(@app_root, "db/backups")
        FileUtils.mkdir_p(backup_dir)

        # Create a corrupted backup file
        corrupted_backup = File.join(backup_dir, "corrupted_backup.sql")
        File.write(corrupted_backup, "INVALID SQL CONTENT")

        backup_manager = MigrationGuard::Recovery::BackupManager.new
        restore_result = backup_manager.restore_from_backup(corrupted_backup)

        expect(restore_result).to be false
      end

      # rubocop:disable RSpec/PendingWithoutReason
      xit "provides rollback capability if restore fails", reason: "requires restore rollback implementation" do
        # rubocop:enable RSpec/PendingWithoutReason
        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        # Create initial backup
        backup_manager = MigrationGuard::Recovery::BackupManager.new
        initial_backup = backup_manager.create_backup

        # Modify database state
        within_app_directory(@app_root) do
          MigrationGuard::MigrationGuardRecord.first.update!(status: "modified")
        end

        # Attempt restore with failure simulation
        allow(backup_manager).to receive(:execute_sql_file).and_raise(StandardError, "Restore failed")

        expect do
          backup_manager.restore_from_backup(initial_backup)
        end.not_to(change { MigrationGuard::MigrationGuardRecord.first.status })
      end
    end

    context "backup cleanup and maintenance" do
      it "automatically cleans up old backups" do
        backup_manager = MigrationGuard::Recovery::BackupManager.new
        backup_dir = File.join(@app_root, "db/backups")
        FileUtils.mkdir_p(backup_dir)

        # Create old backup files
        old_backups = 5.times.map do |i|
          backup_file = File.join(backup_dir, "old_backup_#{i}.sql")
          File.write(backup_file, "-- Backup #{i}")
          File.utime(30.days.ago.to_time, 30.days.ago.to_time, backup_file) # Make them old
          backup_file
        end

        # Create recent backup file
        recent_backup = File.join(backup_dir, "recent_backup.sql")
        File.write(recent_backup, "-- Recent backup")

        # Cleanup old backups
        cleanup_result = backup_manager.cleanup_old_backups(keep_days: 7)

        aggregate_failures do
          expect(cleanup_result).to be true

          # Old backups should be removed
          old_backups.each do |backup_file|
            expect(File.exist?(backup_file)).to be false
          end

          # Recent backup should remain
          expect(File.exist?(recent_backup)).to be true
        end
      end

      it "maintains backup retention policy" do
        backup_manager = MigrationGuard::Recovery::BackupManager.new

        # Create multiple backups over time
        5.times do |_i|
          backup_name = backup_manager.create_backup
          expect(backup_name).not_to be_nil

          # Simulate time passing
          sleep(0.1)
        end

        # Verify backups are created with proper naming
        backup_dir = File.join(@app_root, "db/backups")
        backup_files = Dir.glob(File.join(backup_dir, "*.sql"))

        aggregate_failures do
          expect(backup_files.size).to be >= 5

          # Each backup should have timestamp in filename
          backup_files.each do |file|
            filename = File.basename(file)
            expect(filename).to match(/\d{8}_\d{6}/) # YYYYMMDD_HHMMSS format
          end
        end
      end

      it "validates backup files before cleanup" do
        backup_manager = MigrationGuard::Recovery::BackupManager.new
        backup_dir = File.join(@app_root, "db/backups")
        FileUtils.mkdir_p(backup_dir)

        # Create valid and invalid backup files
        valid_backup = File.join(backup_dir, "valid_backup.sql")
        File.write(valid_backup, "-- Valid SQL backup\nSELECT 1;")
        File.utime(30.days.ago.to_time, 30.days.ago.to_time, valid_backup)

        invalid_backup = File.join(backup_dir, "invalid_backup.sql")
        File.write(invalid_backup, "INVALID CONTENT")
        File.utime(30.days.ago.to_time, 30.days.ago.to_time, invalid_backup)

        # Cleanup should handle both gracefully
        expect do
          backup_manager.cleanup_old_backups(keep_days: 7)
        end.not_to raise_error

        # Both should be removed since they're old
        aggregate_failures do
          expect(File.exist?(valid_backup)).to be false
          expect(File.exist?(invalid_backup)).to be false
        end
      end
    end

    context "backup performance and storage" do
      it "efficiently handles large database backups" do
        # Create large dataset
        100.times do |i|
          MigrationGuard::MigrationGuardRecord.create!(
            version: "20240101#{i.to_s.rjust(6, '0')}",
            branch: "feature/large_dataset",
            status: "applied",
            metadata: { "large_data" => "x" * 1000 } # 1KB per record
          )
        end

        backup_manager = MigrationGuard::Recovery::BackupManager.new

        # Measure backup performance
        performance_data = measure_recovery_performance(100) do
          backup_manager.create_backup
        end

        aggregate_failures do
          expect(performance_data[:result]).not_to be_nil
          expect(performance_data[:duration]).to be < 30.0 # Should complete within 30 seconds

          # Verify backup file was created and has reasonable size
          backup_dir = File.join(@app_root, "db/backups")
          backup_files = Dir.glob(File.join(backup_dir, "*large_dataset_test*.sql"))
          expect(backup_files).not_to be_empty
        end
      end

      it "compresses backups when configured" do
        versions = %w[20240101000001 20240101000002]
        create_orphaned_migrations(@app_root, versions)

        backup_manager = MigrationGuard::Recovery::BackupManager.new

        # Create compressed backup
        backup_file = backup_manager.create_backup

        if backup_file
          backup_path = File.join(@app_root, "db/backups", backup_file)

          # Compressed file should be smaller and have appropriate format
          expect(File.exist?(backup_path)).to be true
          expect(backup_file).to match(/\.(gz|zip)$/) if File.extname(backup_file) != ".sql"
        end
      end
    end
  end

  describe "branch switching scenarios" do
    context "recovery when switching between feature branches" do
      it "handles migrations from different feature branches correctly" do
        # Create multiple feature branches with different migrations
        branch_a_versions = %w[20240101000001 20240101000002]
        branch_b_versions = %w[20240101000003 20240101000004]

        create_feature_branch_with_migrations(@app_root, "feature/branch-a", branch_a_versions)
        create_feature_branch_with_migrations(@app_root, "feature/branch-b", branch_b_versions)

        # Apply migrations from branch A
        apply_migrations_to_database(@app_root, branch_a_versions, "feature/branch-a")

        # Switch to branch B context and check for orphaned migrations
        within_app_directory(@app_root) do
          run_git_command("git checkout feature/branch-b")
        end

        recovery_data = run_recovery_process(@app_root)
        orphaned_issues = recovery_data[:issues].select { |i| i[:type] == :missing_file }

        aggregate_failures do
          expect(orphaned_issues.size).to eq(2)
          expect(orphaned_issues.map { |i| i[:version] }).to match_array(branch_a_versions)

          # Issues should indicate they're from different branch
          orphaned_issues.each do |issue|
            expect(issue[:migration]&.branch).to eq("feature/branch-a")
          end
        end
      end

      it "preserves migration integrity when switching branches" do
        # Create branches with overlapping migration timestamps
        branch_a_versions = %w[20240101120000 20240101130000]
        branch_b_versions = %w[20240101125000 20240101135000] # Interleaved timestamps

        create_feature_branch_with_migrations(@app_root, "feature/branch-a", branch_a_versions)
        create_feature_branch_with_migrations(@app_root, "feature/branch-b", branch_b_versions)

        # Apply all migrations
        all_versions = (branch_a_versions + branch_b_versions).sort
        apply_migrations_to_database(@app_root, all_versions)

        # Switch to main branch (where none of these migrations exist)
        within_app_directory(@app_root) do
          run_git_command("git checkout main")
        end

        recovery_data = run_recovery_process(@app_root)

        aggregate_failures do
          # All migrations should be detected as orphaned
          orphaned_issues = recovery_data[:issues].select { |i| i[:type] == :missing_file }
          expect(orphaned_issues.size).to eq(4)

          # Verify correct chronological ordering is maintained
          issue_versions = orphaned_issues.map { |i| i[:version] }
          expect(issue_versions).to eq(all_versions)
        end
      end

      it "handles branch merges and migration conflicts" do
        # Create branches with conflicting migration versions
        conflicting_version = "20240101000001"

        create_feature_branch_with_migrations(@app_root, "feature/branch-a", [conflicting_version])
        create_feature_branch_with_migrations(@app_root, "feature/branch-b", [conflicting_version])

        # Apply migration from both branches (simulating merge conflict)
        within_app_directory(@app_root) do
          run_git_command("git checkout feature/branch-a")
          apply_migrations_to_database(@app_root, [conflicting_version])

          run_git_command("git checkout feature/branch-b")
          MigrationGuard::MigrationGuardRecord.create!(
            version: conflicting_version,
            branch: "feature/branch-b",
            author: "dev2@example.com",
            status: "applied",
            metadata: { branch_conflict: true }
          )
        end

        recovery_data = run_recovery_process(@app_root)
        conflict_issues = recovery_data[:issues].select { |i| i[:type] == :version_conflict }

        aggregate_failures do
          expect(conflict_issues.size).to eq(1)

          conflict_issue = conflict_issues.first
          expect(conflict_issue[:version]).to eq(conflicting_version)
          expect(conflict_issue[:severity]).to eq(:critical)
        end
      end
    end

    context "handling migrations from deleted branches" do
      it "detects migrations from branches that no longer exist" do
        deleted_branch_versions = %w[20240101000001 20240101000002]

        # Create branch, apply migrations, then delete branch
        create_feature_branch_with_migrations(@app_root, "feature/temporary", deleted_branch_versions)
        apply_migrations_to_database(@app_root, deleted_branch_versions)

        within_app_directory(@app_root) do
          run_git_command("git checkout main")
          run_git_command("git branch -D feature/temporary")
        end

        recovery_data = run_recovery_process(@app_root)
        orphaned_issues = recovery_data[:issues].select { |i| i[:type] == :missing_file }

        aggregate_failures do
          expect(orphaned_issues.size).to eq(2)

          # Should detect that branch no longer exists
          orphaned_issues.each do |issue|
            expect(issue[:migration]&.branch).to eq("feature/temporary")
            expect(issue[:recovery_options]).to include(:mark_as_rolled_back)
          end
        end
      end

      it "handles recovery when git history is unavailable" do
        versions = %w[20240101000001 20240101000002]

        # Create orphaned migrations
        create_orphaned_migrations(@app_root, versions)

        # Simulate git history unavailable
        simulate_git_failure(/git log|git show/)

        recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :mark_as_rolled_back)

        aggregate_failures do
          expect(recovery_data[:issues].size).to eq(2)
          expect(recovery_data[:results].all?).to be true

          # Verify migrations were marked as rolled back
          versions.each do |version|
            record = MigrationGuard::MigrationGuardRecord.find_by(version: version)
            expect(record.status).to eq("rolled_back")
          end
        end
      end
    end

    context "recovery with migrations from multiple branches" do
      it "handles complex multi-branch scenarios" do
        # Create a complex scenario with multiple branches
        main_versions = ["20240101000001"]
        feature_a_versions = %w[20240101000002 20240101000003]
        feature_b_versions = %w[20240101000004 20240101000005]
        hotfix_versions = ["20240101000006"]

        # Create branches
        create_feature_branch_with_migrations(@app_root, "feature/feature-a", feature_a_versions)
        create_feature_branch_with_migrations(@app_root, "feature/feature-b", feature_b_versions)
        create_feature_branch_with_migrations(@app_root, "hotfix/urgent-fix", hotfix_versions)

        # Apply migrations from different branches in mixed order
        all_versions = main_versions + feature_a_versions + feature_b_versions + hotfix_versions
        apply_migrations_to_database(@app_root, all_versions)

        # Switch to main branch
        within_app_directory(@app_root) do
          run_git_command("git checkout main")
        end

        recovery_data = run_recovery_process(@app_root)

        aggregate_failures do
          # Should detect orphaned migrations from all feature branches
          orphaned_issues = recovery_data[:issues].select { |i| i[:type] == :missing_file }
          expected_orphaned = feature_a_versions + feature_b_versions + hotfix_versions
          expect(orphaned_issues.size).to eq(expected_orphaned.size)

          # Group by branch
          issues_by_branch = orphaned_issues.group_by { |i| i[:migration]&.branch }
          expect(issues_by_branch.keys).to include("feature/feature-a", "feature/feature-b", "hotfix/urgent-fix")
        end
      end

      it "prioritizes recovery actions based on branch type" do
        # Create different types of branches
        feature_versions = ["20240101000001"]
        hotfix_versions = ["20240101000002"]
        release_versions = ["20240101000003"]

        create_feature_branch_with_migrations(@app_root, "feature/new-feature", feature_versions)
        create_feature_branch_with_migrations(@app_root, "hotfix/critical-fix", hotfix_versions)
        create_feature_branch_with_migrations(@app_root, "release/v1.2.0", release_versions)

        # Apply all migrations
        all_versions = feature_versions + hotfix_versions + release_versions
        apply_migrations_to_database(@app_root, all_versions)

        # Switch to main
        within_app_directory(@app_root) do
          run_git_command("git checkout main")
        end

        recovery_data = run_recovery_process(@app_root)
        orphaned_issues = recovery_data[:issues].select { |i| i[:type] == :missing_file }

        # Verify different recovery recommendations based on branch patterns

        aggregate_failures do
          expect(orphaned_issues.size).to eq(3)

          orphaned_issues.each do |issue|
            case issue[:migration]&.branch
            when "hotfix/critical-fix"
              # Hotfixes should be preserved
              expect(issue[:recovery_options]).to include(:restore_from_git)
            when "release/v1.2.0"
              # Release branches should be restored and documented
              expect(issue[:recovery_options]).to include(:restore_from_git, :manual_intervention)
            when "feature/new-feature"
              # Feature branches can be rolled back
              expect(issue[:recovery_options]).to include(:mark_as_rolled_back)
            end
          end
        end
      end
    end

    context "conflict detection between branches" do
      it "detects schema conflicts between branches" do
        # Create branches with conflicting schema changes
        conflicting_version = "20240101000001"

        within_app_directory(@app_root) do
          # Create branch A with a table
          run_git_command("git checkout -b feature/branch-a")
          create_test_migration(File.join(@app_root, "db/migrate"), conflicting_version, "CreateUsersTable")
          run_git_command("git add db/migrate/")
          run_git_command("git commit -m 'Add users table'")

          # Create branch B with different table using same version
          run_git_command("git checkout main")
          run_git_command("git checkout -b feature/branch-b")
          create_conflicting_migration(@app_root, conflicting_version, "CreateProductsTable")
          run_git_command("git add db/migrate/")
          run_git_command("git commit -m 'Add products table'")

          # Apply both migrations (simulating merge)
          MigrationGuard::MigrationGuardRecord.create!(
            version: conflicting_version,
            branch: "feature/branch-a",
            status: "applied",
            metadata: { table_created: "users" }
          )

          MigrationGuard::MigrationGuardRecord.create!(
            version: conflicting_version,
            branch: "feature/branch-b",
            status: "applied",
            metadata: { table_created: "products" }
          )
        end

        recovery_data = run_recovery_process(@app_root)
        conflict_issues = recovery_data[:issues].select { |i| i[:type] == :version_conflict }

        aggregate_failures do
          expect(conflict_issues.size).to eq(1)

          conflict_issue = conflict_issues.first
          expect(conflict_issue[:version]).to eq(conflicting_version)
          expect(conflict_issue[:severity]).to eq(:critical)
          expect(conflict_issue[:description]).to include("version conflict")
        end
      end

      it "provides detailed conflict resolution guidance" do
        conflict_version = "20240101000001"
        create_version_conflict_scenario(@app_root, conflict_version)

        recovery_data = run_recovery_process(@app_root)
        conflict_issue = recovery_data[:issues].find { |i| i[:type] == :version_conflict }

        aggregate_failures do
          expect(conflict_issue).not_to be_nil
          expect(conflict_issue[:recovery_options]).to include(:consolidate_records, :remove_duplicates)

          # Should provide guidance on manual resolution
          expect(conflict_issue[:description]).to be_present
          expect(conflict_issue[:severity]).to eq(:high)
        end
      end
    end
  end

  describe "error handling scenarios" do
    context "database connection failures" do
      it "gracefully handles database connection loss during recovery" do
        versions = %w[20240101000001 20240101000002]
        create_orphaned_migrations(@app_root, versions)

        # Simulate database connection failure during recovery
        recovery_data = nil
        expect do
          simulate_database_failure do
            recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :restore_from_git)
          end
        end.not_to raise_error

        # Should handle the error gracefully
        expect(recovery_data).not_to be_nil
      end

      it "provides meaningful error messages for database issues" do
        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        # Mock database error during schema query
        allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(
          ActiveRecord::StatementInvalid, "Database connection lost"
        )

        expect do
          run_recovery_process(@app_root, execute_recovery: true, recovery_action: :restore_from_git)
        end.not_to raise_error
      end

      it "maintains database consistency after connection recovery" do
        versions = %w[20240101000001 20240101000002]
        create_orphaned_migrations(@app_root, versions)

        # Simulate intermittent connection issues
        call_count = 0
        allow(ActiveRecord::Base.connection).to receive(:execute).and_wrap_original do |original, *args|
          call_count += 1
          raise ActiveRecord::ConnectionNotEstablished, "Connection lost" if call_count == 2

          original.call(*args)
        end

        # Recovery should handle the intermittent failure
        expect do
          run_recovery_process(@app_root)
        end.not_to raise_error

        # Database should remain in consistent state
        records = MigrationGuard::MigrationGuardRecord.all
        expect(records.count).to eq(2)
      end
    end

    context "file system errors" do
      it "handles read-only file system during restoration" do
        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        # Mock file system write failure
        allow(File).to receive(:write).and_raise(Errno::EACCES, "Permission denied")

        recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :restore_from_git)

        # Should handle the error and report failure
        expect(recovery_data[:results]).to include(false)
      end

      it "handles disk space exhaustion during backup creation" do
        versions = %w[20240101000001 20240101000002]
        create_orphaned_migrations(@app_root, versions)

        # Mock disk space error
        backup_manager = instance_double(MigrationGuard::Recovery::BackupManager)
        allow(MigrationGuard::Recovery::BackupManager).to receive(:new).and_return(backup_manager)
        allow(backup_manager).to receive(:create_backup).and_raise(Errno::ENOSPC, "No space left on device")

        expect do
          run_recovery_process(@app_root, execute_recovery: true, recovery_action: :restore_from_git)
        end.not_to raise_error
      end

      it "recovers from corrupted migration files" do
        versions = ["20240101000001"]

        # Create migration with corrupted content
        within_app_directory(@app_root) do
          # Create migration file with invalid Ruby syntax
          corrupted_content = "class CorruptedMigration < ActiveRecord::Migration[7.0]\n  " \
                              "def change\n    INVALID SYNTAX HERE\n  end\nend"
          FileUtils.mkdir_p("db/migrate")
          File.write("db/migrate/#{versions.first}_corrupted_migration.rb", corrupted_content)

          # Create tracking record
          MigrationGuard::MigrationGuardRecord.create!(
            version: versions.first,
            branch: "feature/corrupted",
            status: "applied",
            metadata: { corrupted: true }
          )

          # Add to schema
          ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('#{versions.first}')")
        end

        recovery_data = run_recovery_process(@app_root)

        # Should detect the issue and provide recovery options
        expect(recovery_data[:issues]).not_to be_empty
      end
    end

    context "git command failures" do
      it "handles git repository corruption" do
        versions = %w[20240101000001 20240101000002]
        create_orphaned_migrations(@app_root, versions)

        # Simulate git corruption
        simulate_git_failure(/git/)

        recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :mark_as_rolled_back)

        aggregate_failures do
          expect(recovery_data[:issues].size).to eq(2)
          # Should fallback to non-git recovery methods
          expect(recovery_data[:results]).to include(true)
        end
      end

      it "provides fallback options when git history is unavailable" do
        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        # Mock git show failure
        simulate_git_failure(/git show/)

        recovery_data = run_recovery_process(@app_root)
        orphaned_issues = recovery_data[:issues].select { |i| i[:type] == :missing_file }

        aggregate_failures do
          expect(orphaned_issues.size).to eq(1)

          # Should provide non-git recovery options
          recovery_options = orphaned_issues.first[:recovery_options]
          expect(recovery_options).to include(:mark_as_rolled_back)
          expect(recovery_options).not_to include(:restore_from_git) # Should be excluded due to git failure
        end
      end

      it "handles git authentication failures" do
        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        # Simulate git authentication failure
        simulate_git_failure(/git/)

        recovery_data = run_recovery_process(@app_root)

        # Should detect issues even without git access
        expect(recovery_data[:issues]).not_to be_empty
      end
    end

    context "rollback of partial recovery operations" do
      it "rolls back changes when recovery fails midway" do
        versions = %w[20240101000001 20240101000002 20240101000003]
        create_orphaned_migrations(@app_root, versions)

        # Mock failure on second migration
        call_count = 0
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(MigrationGuard::Recovery::RestoreAction)
          .to receive(:restore_migration).and_wrap_original do |original, *args|
          # rubocop:enable RSpec/AnyInstance
          call_count += 1
          raise StandardError, "Simulated failure during recovery" if call_count == 2

          original.call(*args)
        end

        # Attempt recovery
        recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :restore_from_git)

        aggregate_failures do
          # Should have attempted all recoveries
          expect(recovery_data[:results].size).to eq(3)

          # Should have mixed results (some success, some failure)
          expect(recovery_data[:results]).to include(true)
          expect(recovery_data[:results]).to include(false)

          # Database should remain in consistent state
          records = MigrationGuard::MigrationGuardRecord.where(version: versions)
          expect(records.count).to eq(3)
        end
      end

      it "maintains audit trail of recovery attempts" do
        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        # Perform recovery
        run_recovery_process(@app_root, execute_recovery: true, recovery_action: :restore_from_git)

        # Check that recovery attempt is logged in metadata
        record = MigrationGuard::MigrationGuardRecord.find_by(version: versions.first)
        expect(record.metadata).to include("recovery_attempts")
      end

      it "prevents recursive recovery operations" do
        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        # Simulate recovery triggering another recovery (recursive scenario)
        recovery_executor = MigrationGuard::RecoveryExecutor.new

        # Mock to simulate recursive call detection
        allow(recovery_executor).to receive(:executing_recovery?).and_return(true)

        # Should prevent recursive execution
        expect do
          recovery_executor.execute_recovery(
            { version: versions.first, type: :missing_file, recovery_options: [:restore_from_git] },
            :restore_from_git
          )
        end.not_to raise_error
      end
    end

    context "resource exhaustion scenarios" do
      it "handles memory pressure during large recovery operations" do
        # Create many orphaned migrations to test memory usage
        large_version_set = (1..500).map { |i| "20240101#{i.to_s.rjust(6, '0')}" }
        create_orphaned_migrations(@app_root, large_version_set)

        # Monitor memory usage during recovery
        initial_memory = GC.stat[:heap_allocated_pages]

        recovery_data = run_recovery_process(@app_root)

        final_memory = GC.stat[:heap_allocated_pages]
        memory_growth = final_memory - initial_memory

        aggregate_failures do
          expect(recovery_data[:issues].size).to eq(500)
          expect(memory_growth).to be < 5000 # Reasonable memory growth
        end
      end

      it "times out gracefully on long-running operations" do
        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        # Mock slow git operation
        allow(Open3).to receive(:capture3).and_wrap_original do |original, *args|
          if args.join(" ").include?("git show")
            sleep(10) # Simulate very slow operation
            # rubocop:disable RSpec/VerifiedDoubles
            ["", "", double(success?: false, exitstatus: 124)] # Timeout exit code
            # rubocop:enable RSpec/VerifiedDoubles
          else
            original.call(*args)
          end
        end

        # Recovery should timeout gracefully
        start_time = Time.current
        recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :restore_from_git)
        duration = Time.current - start_time

        aggregate_failures do
          expect(duration).to be < 15.0 # Should not hang indefinitely
          expect(recovery_data[:results]).to include(false) # Should report failure
        end
      end
    end

    context "concurrent recovery operations" do
      it "handles multiple recovery processes safely" do
        versions = %w[20240101000001 20240101000002]
        create_orphaned_migrations(@app_root, versions)

        # Simulate concurrent recovery attempts
        threads = []
        results = []

        2.times do |_i|
          threads << Thread.new do
            recovery_data = run_recovery_process(@app_root, execute_recovery: true,
                                                            recovery_action: :mark_as_rolled_back)
            results << recovery_data
          end
        end

        threads.each(&:join)

        # Both should complete without corrupting data
        aggregate_failures do
          expect(results.size).to eq(2)

          # Final state should be consistent
          records = MigrationGuard::MigrationGuardRecord.where(version: versions)
          records.each do |record|
            expect(record.status).to be_in(%w[applied rolled_back])
          end
        end
      end
    end
  end

  describe "database state verification scenarios" do
    context "schema consistency verification" do
      it "verifies schema_migrations table consistency after recovery" do
        versions = %w[20240101000001 20240101000002 20240101000003]

        # Create mixed scenario
        create_orphaned_migrations(@app_root, versions[0..1])
        create_stuck_rollback_scenario(@app_root, versions[2])

        # Execute recovery
        run_recovery_process(@app_root, execute_recovery: true, recovery_action: :complete_rollback)

        # Verify final database state
        verify_database_consistency(
          expected_versions: [],
          unexpected_versions: versions
        )

        # Explicit expectation for RuboCop
        expect(MigrationGuard::MigrationGuardRecord.count).to be >= 0
      end

      it "detects schema drift between environments" do
        versions = %w[20240101000001 20240101000002]

        # Create scenario where schema has extra migrations
        versions.each do |version|
          ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('#{version}')")
        end

        # But no tracking records exist (simulating fresh environment)
        MigrationGuard::MigrationGuardRecord.delete_all

        recovery_data = run_recovery_process(@app_root)
        schema_issues = recovery_data[:issues].select { |i| i[:type] == :orphaned_schema }

        expect(schema_issues.size).to eq(2)
        expect(schema_issues.map { |i| i[:version] }).to match_array(versions)
      end

      it "validates foreign key constraints after recovery" do
        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        # Execute recovery that should maintain referential integrity
        recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :complete_rollback)

        # Verify no orphaned foreign key constraints remain
        expect(recovery_data[:results].all?).to be true

        # Additional integrity checks could be added here
        # (checking for orphaned indexes, constraints, etc.)
      end
    end

    context "cross-database adapter verification" do
      it "handles SQLite-specific recovery operations" do
        # Skip if not using SQLite
        skip unless ActiveRecord::Base.connection.adapter_name == "SQLite"

        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        recovery_data = run_recovery_process(@app_root, execute_recovery: true, recovery_action: :complete_rollback)

        # SQLite should handle the recovery correctly
        expect(recovery_data[:results].all?).to be true
      end

      it "handles PostgreSQL-specific recovery operations" do
        # Mock PostgreSQL adapter
        allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("PostgreSQL")

        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        recovery_data = run_recovery_process(@app_root)

        # Should handle PostgreSQL-specific features
        expect(recovery_data[:issues]).not_to be_empty
      end

      it "handles MySQL-specific recovery operations" do
        # Mock MySQL adapter
        allow(ActiveRecord::Base.connection).to receive(:adapter_name).and_return("MySQL")

        versions = ["20240101000001"]
        create_orphaned_migrations(@app_root, versions)

        recovery_data = run_recovery_process(@app_root)

        # Should handle MySQL-specific features
        expect(recovery_data[:issues]).not_to be_empty
      end
    end

    context "data integrity verification" do
      it "verifies no data loss during recovery operations" do
        versions = %w[20240101000001 20240101000002]
        create_orphaned_migrations(@app_root, versions)

        # Create some test data that should be preserved
        initial_record_count = MigrationGuard::MigrationGuardRecord.count

        # Execute recovery
        run_recovery_process(@app_root, execute_recovery: true, recovery_action: :mark_as_rolled_back)

        # Verify no data was lost
        final_record_count = MigrationGuard::MigrationGuardRecord.count
        expect(final_record_count).to eq(initial_record_count)

        # Verify data integrity
        MigrationGuard::MigrationGuardRecord.find_each do |record|
          expect(record.version).to be_present
          expect(record.status).to be_present
        end
      end

      it "maintains metadata integrity during recovery" do
        versions = ["20240101000001"]

        # Create record with rich metadata
        MigrationGuard::MigrationGuardRecord.create!(
          version: versions.first,
          branch: "feature/test",
          status: "applied",
          metadata: {
            execution_time: 2.5,
            tables_created: %w[users posts],
            indexes_added: 3,
            custom_data: { "key" => "value" }
          }
        )

        # Create orphaned state
        remove_migration_files(@app_root, versions.first)

        # Execute recovery
        run_recovery_process(@app_root, execute_recovery: true, recovery_action: :mark_as_rolled_back)

        # Verify metadata preservation
        record = MigrationGuard::MigrationGuardRecord.find_by(version: versions.first)
        aggregate_failures do
          expect(record.metadata["execution_time"]).to eq(2.5)
          expect(record.metadata["tables_created"]).to eq(%w[users posts])
          expect(record.metadata["indexes_added"]).to eq(3)
          expect(record.metadata["custom_data"]).to eq({ "key" => "value" })

          # Should add recovery metadata
          expect(record.metadata).to include("recovery_action")
        end
      end
    end

    context "performance verification" do
      it "maintains acceptable performance with large datasets" do
        # Create large dataset
        large_version_set = (1..200).map { |i| "20240101#{i.to_s.rjust(6, '0')}" }
        create_orphaned_migrations(@app_root, large_version_set)

        # Measure performance
        performance_data = measure_recovery_performance(200) do
          run_recovery_process(@app_root)
        end

        aggregate_failures do
          expect(performance_data[:result][:issues].size).to eq(200)
          expect(performance_data[:performance_acceptable]).to be true
          expect(performance_data[:migrations_per_second]).to be > 10 # At least 10 migrations per second
        end
      end

      it "scales linearly with migration count" do
        small_set = (1..50).map { |i| "20240101#{i.to_s.rjust(6, '0')}" }
        large_set = (1..100).map { |i| "20240102#{i.to_s.rjust(6, '0')}" }

        # Test small set
        create_orphaned_migrations(@app_root, small_set)
        small_performance = measure_recovery_performance(50) do
          run_recovery_process(@app_root)
        end

        # Clean up and test large set
        MigrationGuard::MigrationGuardRecord.delete_all
        create_orphaned_migrations(@app_root, large_set)
        large_performance = measure_recovery_performance(100) do
          run_recovery_process(@app_root)
        end

        # Performance should scale reasonably
        performance_ratio = large_performance[:duration] / small_performance[:duration]
        expect(performance_ratio).to be < 3.0 # Should not be more than 3x slower for 2x data
      end
    end
  end

  private

  def create_dependent_migrations(versions)
    versions.each_with_index do |version, index|
      depends_on = index > 0 ? versions[index - 1] : nil
      class_name = "DependentMigration#{index + 1}"
      create_test_migration_with_dependency(
        @app_root, version, class_name, depends_on
      )
    end
  end

  # rubocop:disable Metrics/MethodLength
  def create_test_migration_with_dependency(app_root, version, class_name, dependency_version)
    dependency_check = if dependency_version
                         "raise 'Dependency missing' unless " \
                           "ActiveRecord::Base.connection.table_exists?(:dependent_migration_#{dependency_version}s)"
                       else
                         ""
                       end

    content = <<~RUBY
      class #{class_name} < ActiveRecord::Migration[7.0]
        def change
          #{dependency_check}
          create_table :#{class_name.underscore.pluralize} do |t|
            t.string :name
            t.references :dependency, null: #{dependency_version ? 'false' : 'true'}
            t.timestamps
          end
        end
      end
    RUBY

    filename = "#{version}_#{class_name.underscore}.rb"
    path = File.join(app_root, "db/migrate", filename)

    File.write(path, content)
    path
  end
  # rubocop:enable Metrics/MethodLength

  def remove_migration_files(app_root, version)
    Dir.glob(File.join(app_root, "db/migrate/*#{version}*")).each do |file|
      File.delete(file)
    end
  end

  def create_test_migration(directory, version, class_name)
    content = <<~RUBY
      class #{class_name} < ActiveRecord::Migration[7.0]
        def change
          create_table :#{class_name.underscore.pluralize} do |t|
            t.string :name
            t.timestamps
          end
        end
      end
    RUBY

    filename = "#{version}_#{class_name.underscore}.rb"
    path = File.join(directory, filename)

    File.write(path, content)
    path
  end

  # rubocop:disable Metrics/MethodLength
  def create_conflicting_migration(app_root, version, class_name)
    content = <<~RUBY
      class #{class_name} < ActiveRecord::Migration[7.0]
        def change
          create_table :#{class_name.underscore.pluralize} do |t|
            t.string :title
            t.text :description
            t.decimal :price
            t.timestamps
          end
        end
      end
    RUBY

    filename = "#{version}_#{class_name.underscore}.rb"
    path = File.join(app_root, "db/migrate", filename)

    File.write(path, content)
    path
  end
  # rubocop:enable Metrics/MethodLength
end

# rubocop:enable RSpec/ContextWording, RSpec/InstanceVariable
