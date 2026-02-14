# Troubleshooting Guide for Rails Migration Guard

This guide helps you resolve common issues when using the rails-migration-guard gem.

## Table of Contents

1. [Git Command Not Found](#git-command-not-found)
2. [Git Integration Edge Cases](#git-integration-edge-cases)
3. [Permission Issues](#permission-issues)
4. [Database Connection Errors](#database-connection-errors)
5. [Migration Version Conflicts](#migration-version-conflicts)
6. [Performance Issues](#performance-issues)
7. [Rails Version Compatibility](#rails-version-compatibility)
8. [Common Error Messages](#common-error-messages)

## Git Command Not Found

### Problem
You see errors like:
```
MigrationGuard::GitError: Git command not found
```

### Solution
1. **Verify Git is installed:**
   ```bash
   which git
   # Should output something like: /usr/bin/git
   ```

2. **Install Git if missing:**
   - macOS: `brew install git`
   - Ubuntu/Debian: `sudo apt-get install git`
   - CentOS/RHEL: `sudo yum install git`

3. **Check PATH environment variable:**
   ```bash
   echo $PATH
   # Ensure it includes the directory containing git
   ```

4. **For deployment environments:**
   - Ensure Git is available in your Docker image or deployment environment
   - Consider disabling MigrationGuard in production if Git isn't available:
   ```ruby
   # config/initializers/migration_guard.rb
   MigrationGuard.configure do |config|
     config.enabled_environments = [:development, :staging]
     # Explicitly exclude production
   end
   ```

## Git Integration Edge Cases

Rails Migration Guard relies heavily on Git for tracking migrations across branches. Here's how to handle various edge cases and special scenarios.

### Special Branch Names

#### Branch Names with Special Characters

Rails Migration Guard uses shell commands to interact with Git, which can cause issues with certain branch names.

**Problem:**
```bash
# Branch with spaces
git checkout -b "feature/my new feature"
$ rails db:migration:status
sh: syntax error near unexpected token `new'
```

**Solutions:**

1. **Best practice - avoid special characters:**
   ```bash
   # Use hyphens instead of spaces
   git checkout -b feature/my-new-feature
   
   # Use underscores
   git checkout -b feature/my_new_feature
   ```

2. **Escape branch names in Git commands:**
   The gem automatically quotes branch names in Git commands, but extreme cases may still fail.

### Git Configuration Edge Cases

#### Empty or Missing Git Config

**Problem:**
```bash
$ git config user.email
# Returns nothing
$ rails db:migration:status
MigrationGuard::GitError: Git user email not configured
```

**Solutions:**

1. **Disable author tracking:**
   ```ruby
   MigrationGuard.configure do |config|
     config.track_author = false
   end
   ```

#### Author Tracking Issues

**Problem: Author not showing in reports**
```bash
$ rails db:migration:authors
# Shows empty or missing authors
```

**Solutions:**

1. **Verify git configuration:**
   ```bash
   $ git config user.email
   $ git config user.name
   ```

2. **Check if author tracking is enabled:**
   ```ruby
   # In rails console
   MigrationGuard.configuration.track_author
   # Should return true
   ```

3. **For CI/CD environments, set git config:**
   ```bash
   git config user.email "ci@example.com"
   git config user.name "CI System"
   ```

**Problem: Author filtering not working**
```bash
$ rails db:migration:history AUTHOR=alice
# Returns no results despite having migrations by alice
```

**Solutions:**

1. **Use partial matching:**
   ```bash
   $ rails db:migration:history AUTHOR=alice
   # This will match alice@example.com, alice.smith@company.com, etc.
   ```

2. **Check exact author values in database:**
   ```ruby
   # In rails console
   MigrationGuard::MigrationGuardRecord.pluck(:author).uniq
   ```

#### Detached HEAD State

**Problem:**
```bash
$ git checkout abc123def
Note: switching to 'abc123def'.
You are in 'detached HEAD' state...

$ rails db:migration:status
Current branch: HEAD
```

**Solution:**

The gem records `HEAD` as the branch name in detached HEAD state. This is expected behavior and won't cause errors. If you need a more meaningful identifier, consider checking out a named branch instead.

### Repository State Issues

#### Shallow Clones

**Problem:** CI/CD systems often use shallow clones
```bash
$ git clone --depth 1 repo.git
$ rails db:migration:status
# May not see all migrations in history
```

**Solution:**

Unshallow the clone before running migration checks:
```bash
git fetch --unshallow
rails db:migration:status
```

Or configure your CI to use a full clone:
```yaml
# GitHub Actions example
- uses: actions/checkout@v4
  with:
    fetch-depth: 0  # Full clone
```

#### Submodules and Worktrees

**Problem:** Complex Git setups may confuse the gem
```bash
# In a git worktree
$ git worktree add ../feature-branch feature/new-thing
$ cd ../feature-branch
$ rails db:migration:status
# May reference wrong repository
```

**Solution:**

Ensure you run migration commands from the correct working directory. If using worktrees, the gem should detect the git repository automatically. If it doesn't, consider disabling git integration in that environment:
```ruby
MigrationGuard.configure do |config|
  config.git_integration_level = :off
end
```

#### Large Repositories

**Problem:** Git operations timeout in very large repositories
```
MigrationGuard::GitError: Git command timed out
```

**Solutions:**

1. **Optimize your Git repository:**
   ```bash
   git gc --aggressive
   git repack -a -d
   ```

2. **Disable git integration** if git operations are too slow:
   ```ruby
   MigrationGuard.configure do |config|
     config.git_integration_level = :off
   end
   ```

3. **Limit branches checked:**
   ```ruby
   MigrationGuard.configure do |config|
     config.target_branches = ['main']  # Only check against main branch
   end
   ```

### Branch Switching Issues

#### Uncommitted Changes

**Problem:**
```bash
$ git checkout main
error: Your local changes to the following files would be overwritten by checkout:
  db/migrate/20240115_add_users.rb
```

**Solution:**

Stash or commit your migration changes before switching branches:
```bash
git stash
git checkout main
# Later:
git checkout feature-branch
git stash pop
```

#### Missing Remote Branches

**Problem:**
```bash
$ rails db:migration:status
Failed to list migrations in branch origin/main: fatal: ambiguous argument
```

**Solutions:**

1. **Fetch before checking:**
   ```bash
   git fetch --all
   rails db:migration:status
   ```

2. **Use local branches only:**
   ```ruby
   MigrationGuard.configure do |config|
     config.target_branches = ['main']  # Local branches only
   end
   ```

### Non-Standard Git Setups

#### Multiple Remotes

**Problem:** Ambiguous branch references with multiple remotes
```bash
$ git remote -v
origin  git@github.com:company/app.git (fetch)
upstream git@github.com:original/app.git (fetch)
```

**Solution:**

Use fully qualified branch names in your configuration:
```ruby
MigrationGuard.configure do |config|
  config.main_branch_names = %w[origin/main upstream/main]
end
```

#### Git Hooks Interference

**Problem:** Existing git hooks may interfere with MigrationGuard operations

**Solution:**

If MigrationGuard's git hooks conflict with existing hooks, you can remove them:
```bash
rm .git/hooks/post-checkout  # Remove the post-checkout hook
```

Or disable git integration entirely:
```ruby
MigrationGuard.configure do |config|
  config.git_integration_level = :off
end
```

### Best Practices for Git Integration

1. **Environment-specific configuration:**
   ```ruby
   MigrationGuard.configure do |config|
     case Rails.env
     when 'development'
       config.git_integration_level = :warning
     when 'production'
       config.git_integration_level = :off
     end
   end
   ```

2. **Use sensible branch names** - avoid spaces, unicode, and special characters in branch names.

## Permission Issues

### Problem
Errors accessing migration files or the migration_guard_records table:
```
Errno::EACCES: Permission denied @ rb_sysopen - db/migrate/...
```

### Solution
1. **Check file permissions:**
   ```bash
   ls -la db/migrate/
   # Files should be readable by the Rails process
   ```

2. **Fix migration directory permissions:**
   ```bash
   chmod 755 db/migrate
   chmod 644 db/migrate/*.rb
   ```

3. **Database table permissions:**
   ```sql
   -- Grant permissions to your Rails database user
   GRANT ALL PRIVILEGES ON migration_guard_records TO your_rails_user;
   ```

4. **For shared hosting environments:**
   - Ensure the web server user has read access to the Rails root directory
   - Check with your hosting provider about file permission requirements

## Database Connection Errors

### Problem
```
ActiveRecord::ConnectionNotEstablished
Could not find migration_guard_records table
```

### Solution
1. **Run the installation generator:**
   ```bash
   rails generate migration_guard:install
   rails db:migrate
   ```

2. **Verify the table exists:**
   ```bash
   rails console
   > ActiveRecord::Base.connection.tables.include?('migration_guard_records')
   # Should return true
   ```

3. **For multiple databases:**
   ```ruby
   # Ensure MigrationGuard uses the correct database
   class MigrationGuardRecord < ApplicationRecord
     establish_connection :primary # or your specific database
   end
   ```

4. **Connection pool issues:**
   ```ruby
   # config/database.yml
   development:
     pool: 10  # Increase if you see connection timeouts
   ```

## Migration Version Conflicts

### Problem
```
ActiveRecord::RecordNotUnique: Duplicate entry '20240101000001' for key 'index_migration_guard_records_on_version'
```

### Solution
1. **Clean up duplicate records:**
   ```ruby
   # In rails console
   duplicates = MigrationGuard::MigrationGuardRecord
     .group(:version)
     .having('COUNT(*) > 1')
     .pluck(:version)
   
   duplicates.each do |version|
     records = MigrationGuard::MigrationGuardRecord.where(version: version)
     records.offset(1).destroy_all  # Keep the first, remove others
   end
   ```

2. **Reset migration tracking:**
   ```bash
   rails db:migration:cleanup FORCE=true
   ```

3. **Prevent future conflicts:**
   - Always use Rails generators for migrations: `rails g migration AddFieldToModel`
   - Avoid manually creating migration files
   - Use timestamp-based migration versions (Rails default)

## Performance Issues

### Problem
Status checks or rollback operations are slow with large migration histories.

### Solution
1. **Add database indexes (if missing):**
   ```ruby
   class AddIndexesToMigrationGuardRecords < ActiveRecord::Migration[7.0]
     def change
       add_index :migration_guard_records, :status, unless_exists: true
       add_index :migration_guard_records, :created_at, unless_exists: true
       add_index :migration_guard_records, [:branch, :status], unless_exists: true
     end
   end
   ```

2. **Enable auto-cleanup:**
   ```ruby
   MigrationGuard.configure do |config|
     config.auto_cleanup = true
     config.cleanup_after_days = 30  # Remove old rolled_back records
   end
   ```

3. **Optimize Git operations:**
   ```bash
   # Ensure your Git repository is optimized
   git gc --aggressive
   git repack -a -d
   ```

4. **For very large projects:**
   - Consider limiting the branches checked:
   ```ruby
   config.target_branches = ['main']  # Only check against main branch
   ```

## Rails Version Compatibility

### Known Issues by Rails Version

#### Rails 6.1
- Minimum supported version
- All features work as expected

#### Rails 7.0+
- Fully compatible
- Supports multiple databases
- Works with async migrations

#### Rails 8.0+
- Requires sqlite3 gem version 2.1.0 or higher
- Compatible with new migration versioning

### Solution for Version Issues
1. **Check your Rails version:**
   ```bash
   rails --version
   ```

2. **Update the gem if needed:**
   ```ruby
   # Gemfile
   gem 'rails_migration_guard'
   ```
   Rails 6.1 is the minimum supported version.

## Common Error Messages

### "No main branch found"
```
MigrationGuard::GitError: No main branch found. Tried: main, master, trunk
```

**Solution:**
```ruby
# Configure your main branch name
MigrationGuard.configure do |config|
  config.main_branch_names = %w[develop production custom-main]
end
```

### "Orphaned migrations detected"
This is a warning, not an error. It means you have migrations that exist locally but not in your main branch.

**Solutions:**
1. Review the orphaned migrations: `rails db:migration:status`
2. Roll them back if not needed: `rails db:migration:rollback_orphaned`
3. Or commit and push them to your main branch

### "Git user email not configured"
```
MigrationGuard::GitError: Git user email not configured
```

**Solution:**
```bash
git config --global user.email "you@example.com"
git config --global user.name "Your Name"
```

### "Migration file not found in branch"
This occurs when checking for migrations across branches.

**Solution:**
1. Fetch latest branches: `git fetch --all`
2. Ensure branches are up to date: `git pull origin main`
3. Check if migration was renamed or deleted

## Getting Help

If you're still experiencing issues:

1. **Run the diagnostic tool:**
   ```bash
   rails db:migration:doctor
   ```

2. **Check the gem version:**
   ```bash
   bundle show rails_migration_guard
   ```

3. **Enable debug logging:**
   ```ruby
   # In Rails console
   MigrationGuard.logger.level = Logger::DEBUG
   ```

4. **Report issues:**
   - GitHub Issues: https://github.com/tommy2118/rails-migration-guard/issues
   - Include output from `rails db:migration:doctor`
   - Provide Rails version, Ruby version, and database type

## Prevention Tips

1. **Regular maintenance:**
   - Run `rails db:migration:status` before deploying
   - Clean up old migrations periodically
   - Keep your branches synchronized

2. **Team practices:**
   - Always create migrations on feature branches
   - Merge migration changes promptly
   - Communicate about migration conflicts

3. **CI/CD integration:**
   - Add migration checks to your CI pipeline
   - Block deployments with orphaned migrations
   - Automate cleanup in staging environments