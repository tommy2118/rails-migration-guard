# frozen_string_literal: true

require "English"
module MigrationGuard
  class GitIntegration
    def current_branch
      MigrationGuard::Logger.debug("Getting current git branch")
      output = `git rev-parse --abbrev-ref HEAD 2>&1`

      unless $CHILD_STATUS.success?
        MigrationGuard::Logger.error("Failed to determine current branch", output: output)
        raise GitError, "Failed to determine current branch: #{output}"
      end

      branch = output.strip
      MigrationGuard::Logger.debug("Current branch", branch: branch)
      branch
    rescue Errno::ENOENT
      MigrationGuard::Logger.error("Git command not found")
      raise GitError, "Git command not found"
    end

    def main_branch
      MigrationGuard::Logger.debug("Searching for main branch")
      
      MigrationGuard.configuration.main_branch_names.each do |branch_name|
        MigrationGuard::Logger.debug("Checking branch", branch: branch_name)
        `git rev-parse --verify #{branch_name} >/dev/null 2>&1`
        
        if $CHILD_STATUS.success?
          MigrationGuard::Logger.debug("Found main branch", branch: branch_name)
          return branch_name
        end
      end

      branches_tried = MigrationGuard.configuration.main_branch_names.join(', ')
      MigrationGuard::Logger.error("No main branch found", branches_tried: branches_tried)
      raise GitError, "No main branch found. Tried: #{branches_tried}"
    end

    def migrations_in_branch(branch)
      output = `git ls-tree -r #{branch} --name-only db/migrate/ 2>&1`

      raise GitError, "Failed to list migrations in branch #{branch}: #{output}" unless $CHILD_STATUS.success?

      output.split("\n").map { |path| File.basename(path) }.grep(/^\d+_.*\.rb$/)
    end

    def migration_versions_in_trunk
      migrations_in_branch(main_branch).map { |filename| filename.split("_").first }
    end

    def target_branches
      MigrationGuard.configuration.effective_target_branches
    end

    def migrations_in_branches(branches = target_branches)
      branches.each_with_object({}) do |branch, result|
        result[branch] = migrations_in_branch(branch)
      rescue GitError => e
        result[branch] = { error: e.message }
      end
    end

    def migration_versions_in_branches(branches = target_branches)
      branch_migrations = migrations_in_branches(branches)

      branches.index_with do |branch|
        if branch_migrations[branch].is_a?(Array)
          branch_migrations[branch].map { |filename| filename.split("_").first }
        else
          branch_migrations[branch]
        end
      end
    end

    def author_email
      output = `git config user.email 2>&1`

      raise GitError, "Git user email not configured" unless $CHILD_STATUS.success? && !output.strip.empty?

      output.strip
    end

    def file_exists_in_branch?(branch, file_path)
      `git cat-file -e #{branch}:#{file_path} 2>&1`
      $CHILD_STATUS.success?
    end

    def uncommitted_changes?
      output = `git status --porcelain 2>&1`

      raise GitError, "Failed to check git status: #{output}" unless $CHILD_STATUS.success?

      !output.strip.empty?
    end

    def stash_required?
      output = `git status --porcelain db/migrate/ 2>&1`

      raise GitError, "Failed to check migration status: #{output}" unless $CHILD_STATUS.success?

      !output.strip.empty?
    end
  end
end
