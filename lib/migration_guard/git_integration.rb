# frozen_string_literal: true

module MigrationGuard
  class GitIntegration
    def current_branch
      output = `git rev-parse --abbrev-ref HEAD 2>&1`
      
      if $?.success?
        output.strip
      else
        raise GitError, "Failed to determine current branch: #{output}"
      end
    rescue Errno::ENOENT
      raise GitError, "Git command not found"
    end

    def main_branch
      MigrationGuard.configuration.main_branch_names.each do |branch_name|
        `git rev-parse --verify #{branch_name} >/dev/null 2>&1`
        return branch_name if $?.success?
      end
      
      raise GitError, "No main branch found. Tried: #{MigrationGuard.configuration.main_branch_names.join(', ')}"
    end

    def migrations_in_branch(branch)
      output = `git ls-tree -r #{branch} --name-only db/migrate/ 2>&1`
      
      if $?.success?
        output.split("\n").map { |path| File.basename(path) }.select { |f| f.match?(/^\d+_.*\.rb$/) }
      else
        raise GitError, "Failed to list migrations in branch #{branch}: #{output}"
      end
    end

    def migration_versions_in_trunk
      migrations_in_branch(main_branch).map { |filename| filename.split("_").first }
    end

    def author_email
      output = `git config user.email 2>&1`
      
      if $?.success? && !output.strip.empty?
        output.strip
      else
        raise GitError, "Git user email not configured"
      end
    end

    def file_exists_in_branch?(branch, file_path)
      `git cat-file -e #{branch}:#{file_path} 2>&1`
      $?.success?
    end

    def uncommitted_changes?
      output = `git status --porcelain 2>&1`
      
      if $?.success?
        !output.strip.empty?
      else
        raise GitError, "Failed to check git status: #{output}"
      end
    end

    def stash_required?
      output = `git status --porcelain db/migrate/ 2>&1`
      
      if $?.success?
        !output.strip.empty?
      else
        raise GitError, "Failed to check migration status: #{output}"
      end
    end
  end
end