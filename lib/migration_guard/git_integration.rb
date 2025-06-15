# frozen_string_literal: true

require "English"
module MigrationGuard
  class GitIntegration
    def current_branch
      output = `git rev-parse --abbrev-ref HEAD 2>&1`

      raise GitError, "Failed to determine current branch: #{output}" unless $CHILD_STATUS.success?

      output.strip
    rescue Errno::ENOENT
      raise GitError, "Git command not found"
    end

    def main_branch
      MigrationGuard.configuration.main_branch_names.each do |branch_name|
        `git rev-parse --verify #{branch_name} >/dev/null 2>&1`
        return branch_name if $CHILD_STATUS.success?
      end

      raise GitError, "No main branch found. Tried: #{MigrationGuard.configuration.main_branch_names.join(', ')}"
    end

    def migrations_in_branch(branch)
      output = `git ls-tree -r #{branch} --name-only db/migrate/ 2>&1`

      raise GitError, "Failed to list migrations in branch #{branch}: #{output}" unless $CHILD_STATUS.success?

      output.split("\n").map { |path| File.basename(path) }.grep(/^\d+_.*\.rb$/)
    end

    def migration_versions_in_trunk
      migrations_in_branch(main_branch).map { |filename| filename.split("_").first }
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
