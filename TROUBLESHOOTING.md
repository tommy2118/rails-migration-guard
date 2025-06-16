# Troubleshooting Guide for Rails Migration Guard

This guide helps you resolve common issues when using the rails-migration-guard gem.

## Table of Contents

1. [Git Command Not Found](#git-command-not-found)
2. [Permission Issues](#permission-issues)
3. [Database Connection Errors](#database-connection-errors)
4. [Migration Version Conflicts](#migration-version-conflicts)
5. [Performance Issues](#performance-issues)
6. [Rails Version Compatibility](#rails-version-compatibility)
7. [Common Error Messages](#common-error-messages)

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
   gem 'rails-migration-guard', '~> 2.0'  # Check latest version
   ```

3. **For older Rails versions:**
   ```ruby
   # Use an older version of the gem
   gem 'rails-migration-guard', '~> 1.0'  # For Rails < 6.1
   ```

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
   bundle show rails-migration-guard
   ```

3. **Enable debug logging:**
   ```ruby
   # In Rails console
   MigrationGuard.logger.level = Logger::DEBUG
   ```

4. **Report issues:**
   - GitHub Issues: https://github.com/your-org/rails-migration-guard/issues
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