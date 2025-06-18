# Sandbox Mode Guide

Sandbox mode is a powerful feature in Rails Migration Guard that allows you to test migrations without permanently applying changes to your database. This guide covers everything you need to know about using sandbox mode effectively.

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Configuration](#configuration)
- [Visual Feedback](#visual-feedback)
- [Use Cases](#use-cases)
- [Environment Variables](#environment-variables)
- [Limitations](#limitations)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

Sandbox mode wraps your migrations in a database transaction that is automatically rolled back after execution. This allows you to:

- ✅ Test migration behavior without permanent changes
- ✅ Preview schema.rb changes before committing
- ✅ Debug failing migrations safely
- ✅ Review migrations during code reviews
- ✅ Validate migration logic in CI/CD pipelines

## How It Works

When sandbox mode is enabled, the migration process follows these steps:

1. **Transaction Start**: A new database transaction begins
2. **Migration Execution**: Your migration runs normally
3. **Schema Update**: `db/schema.rb` is updated with the changes
4. **Automatic Rollback**: The transaction is rolled back
5. **Result**: You can inspect schema.rb, but database remains unchanged

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Start Migration │ --> │ Apply Changes   │ --> │ Update Schema   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                           │
                                                           v
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Migration Done  │ <-- │ Rollback DB     │ <-- │ Keep schema.rb  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Configuration

### Basic Setup

Enable sandbox mode in your Rails Migration Guard initializer:

```ruby
# config/initializers/migration_guard.rb
MigrationGuard.configure do |config|
  config.sandbox_mode = true
end
```

### Conditional Configuration

Enable sandbox mode based on environment or conditions:

```ruby
MigrationGuard.configure do |config|
  # Only in development
  config.sandbox_mode = Rails.env.development?
  
  # Or based on environment variable
  config.sandbox_mode = ENV['SANDBOX_MIGRATIONS'] == 'true'
  
  # Or for specific developers
  config.sandbox_mode = ENV['USER'] == 'new_developer'
end
```

### Runtime Toggle

You can toggle sandbox mode at runtime:

```ruby
# Enable temporarily
MigrationGuard.configuration.sandbox_mode = true

# Check current status
puts "Sandbox mode: #{MigrationGuard.configuration.sandbox_mode ? 'ON' : 'OFF'}"

# Disable when done
MigrationGuard.configuration.sandbox_mode = false
```

## Visual Feedback

Sandbox mode provides clear visual indicators during migration:

### Standard Output

```bash
$ rails db:migrate

🧪 SANDBOX MODE ACTIVE - Database changes will be rolled back
== 20240617123456 CreateUsers: migrating =====================================
-- create_table(:users)
   -> 0.0010s
-- add_index(:users, :email)
   -> 0.0005s
== 20240617123456 CreateUsers: migrated (0.0020s) ============================
⚠️  SANDBOX: Database changes rolled back. Schema.rb updated for inspection.
```

### Log Output

Rails logger also captures sandbox mode activity:

```
[MigrationGuard] Running migration 20240617123456 in sandbox mode...
[MigrationGuard] Migration would succeed. Rolling back sandbox...
[MigrationGuard] Sandbox rollback complete. Run without sandbox to apply.
```

## Use Cases

### 1. Testing Complex Migrations

Before running a migration that modifies critical data:

```ruby
# Enable sandbox mode
MigrationGuard.configuration.sandbox_mode = true

# Test the migration
$ rails db:migrate

# Review schema changes
$ git diff db/schema.rb

# If everything looks good, run for real
MigrationGuard.configuration.sandbox_mode = false
$ rails db:migrate
```

### 2. Debugging Failed Migrations

When a migration fails, use sandbox mode to debug:

```ruby
class ProblematicMigration < ActiveRecord::Migration[7.0]
  def up
    # This might fail
    execute "ALTER TABLE users ADD CONSTRAINT unique_email UNIQUE (email)"
    
    # Add debugging
    User.where(email: nil).update_all(email: 'placeholder@example.com')
    
    # More operations...
  end
end
```

With sandbox mode, you can see exactly where it fails without corrupting your database.

### 3. Code Review Process

Add to your team's PR checklist:

```markdown
## Migration Review Checklist
- [ ] Tested in sandbox mode
- [ ] Schema.rb changes reviewed
- [ ] Rollback tested
- [ ] Performance impact assessed
```

Reviewers can checkout the branch and run:

```bash
# Enable sandbox mode for review
$ SANDBOX_MIGRATIONS=true rails db:migrate

# Check the schema changes
$ git diff db/schema.rb
```

### 4. CI/CD Pipeline Testing

Add a sandbox test step to your CI workflow:

```yaml
# .github/workflows/test.yml
- name: Test Migrations in Sandbox
  run: |
    export MIGRATION_GUARD_SANDBOX_QUIET=true
    bundle exec rails db:migrate
    git diff --exit-code db/schema.rb || echo "Schema changes detected"
```

### 5. Training New Developers

Sandbox mode is perfect for onboarding:

```ruby
# config/environments/development.rb
if ENV['NEW_DEVELOPER_MODE']
  Rails.application.configure do
    config.after_initialize do
      MigrationGuard.configuration.sandbox_mode = true
      puts "🎓 Sandbox mode enabled for safe learning!"
    end
  end
end
```

## Environment Variables

Control sandbox mode behavior with environment variables:

### `MIGRATION_GUARD_SANDBOX_QUIET`

Disable all sandbox mode output:

```bash
export MIGRATION_GUARD_SANDBOX_QUIET=true
rails db:migrate  # No sandbox messages shown
```

### `MIGRATION_GUARD_SANDBOX_VERBOSE`

Enable sandbox messages in test environment (normally suppressed):

```bash
export MIGRATION_GUARD_SANDBOX_VERBOSE=true
bundle exec rspec  # Sandbox messages visible in tests
```

### Custom Environment Variables

Create your own controls:

```ruby
# config/initializers/migration_guard.rb
MigrationGuard.configure do |config|
  # Custom sandbox control
  config.sandbox_mode = ENV.fetch('SAFE_MIGRATIONS', 'false') == 'true'
  
  # Team-specific settings
  if ENV['TEAM'] == 'backend'
    config.sandbox_mode = true  # Backend team always uses sandbox
  end
end
```

## Limitations

### Database-Specific Limitations

#### MySQL/MariaDB
- DDL operations (CREATE TABLE, ALTER TABLE) cannot be rolled back
- Schema changes may persist even in sandbox mode
- Use with caution for structural changes

#### PostgreSQL
- Most DDL operations are transactional and will roll back
- Some operations like `CREATE INDEX CONCURRENTLY` cannot be rolled back
- Large data migrations may hit transaction size limits

#### SQLite
- Full transactional DDL support
- All changes roll back properly
- Ideal for sandbox mode testing

### Operation Limitations

1. **Non-transactional Operations**
   - External API calls
   - File system changes
   - Cache modifications
   - Background job enqueuing

2. **Large Data Migrations**
   - Transaction size limits
   - Memory consumption
   - Lock timeout issues

3. **Down Migrations**
   - Sandbox mode only works with `up` migrations
   - Rollbacks (`down`) are not sandboxed

### Example of Limitations

```ruby
class UpdateMillionRecords < ActiveRecord::Migration[7.0]
  def up
    # This might hit transaction limits in sandbox mode
    User.find_in_batches(batch_size: 1000) do |users|
      users.each { |user| user.update!(processed: true) }
    end
    
    # This won't be rolled back
    Rails.cache.clear
    
    # This API call happens regardless
    NotificationService.send_update_complete
  end
end
```

## Best Practices

### 1. Always Test in Sandbox First

Make it a habit:

```ruby
# .bashrc or .zshrc
alias migrate-test='rails db:migrate MIGRATION_GUARD_SANDBOX=true'
alias migrate-real='rails db:migrate MIGRATION_GUARD_SANDBOX=false'
```

### 2. Document Sandbox Testing

In your migration files:

```ruby
# Tested in sandbox mode: ✅
# Schema changes reviewed: ✅
# Performance impact: Low (adds index on already-indexed column)
class AddIndexToUsers < ActiveRecord::Migration[7.0]
  def change
    add_index :users, :email, if_not_exists: true
  end
end
```

### 3. Use Sandbox Mode in Development by Default

```ruby
# config/environments/development.rb
Rails.application.configure do
  config.after_initialize do
    if ENV['DISABLE_SANDBOX'].blank?
      MigrationGuard.configuration.sandbox_mode = true
      puts "💡 Migrations run in sandbox mode by default in development"
      puts "   Set DISABLE_SANDBOX=true to apply migrations permanently"
    end
  end
end
```

### 4. Create Team Conventions

Add to your team's documentation:

```markdown
## Migration Development Process

1. Create migration with descriptive name
2. Test in sandbox mode first
3. Review schema.rb changes
4. Test rollback in sandbox mode
5. Run for real only after validation
6. Commit schema.rb with migration
```

### 5. Combine with Other Safety Features

```ruby
MigrationGuard.configure do |config|
  # Development safety configuration
  if Rails.env.development?
    config.sandbox_mode = true
    config.warning_frequency = :each
    config.git_integration_level = :warning
  end
end
```

## Troubleshooting

### Issue: Sandbox Mode Not Working

**Symptom**: Changes persist despite sandbox mode being enabled

**Solutions**:
1. Check your database type (MySQL might not support DDL rollback)
2. Verify configuration: `rails console` then `MigrationGuard.configuration.sandbox_mode`
3. Look for non-transactional operations in your migration
4. Check for explicit commits in your migration code

### Issue: Transaction Size Errors

**Symptom**: "Transaction is too large" or timeout errors

**Solutions**:
1. Break large migrations into smaller chunks
2. Use `disable_ddl_transaction!` for large data updates (note: this disables sandbox)
3. Consider running large data migrations outside of sandbox mode

### Issue: No Visual Feedback

**Symptom**: No sandbox messages appear

**Solutions**:
1. Check if `MIGRATION_GUARD_SANDBOX_QUIET` is set
2. Verify you're not in test environment without `MIGRATION_GUARD_SANDBOX_VERBOSE`
3. Ensure Migration Guard is enabled for your environment
4. Check log files for sandbox messages

### Issue: Schema.rb Not Updating

**Symptom**: Schema.rb doesn't reflect changes after sandbox migration

**Solutions**:
1. Check write permissions on db/schema.rb
2. Verify schema dump is not disabled in configuration
3. Look for errors in migration output
4. Try running `rails db:schema:dump` manually

## Advanced Usage

### Programmatic Control

```ruby
# lib/tasks/migration_tasks.rake
namespace :db do
  desc "Test all pending migrations in sandbox mode"
  task test_migrations: :environment do
    original = MigrationGuard.configuration.sandbox_mode
    
    begin
      MigrationGuard.configuration.sandbox_mode = true
      puts "Testing migrations in sandbox mode..."
      
      Rake::Task['db:migrate'].invoke
      
      puts "\nSchema changes preview:"
      system 'git diff db/schema.rb'
      
    ensure
      MigrationGuard.configuration.sandbox_mode = original
    end
  end
end
```

### Custom Sandbox Wrapper

```ruby
# lib/migration_guard/sandbox_helper.rb
module MigrationGuard
  module SandboxHelper
    def self.sandbox_run
      original = MigrationGuard.configuration.sandbox_mode
      MigrationGuard.configuration.sandbox_mode = true
      
      yield
      
    ensure
      MigrationGuard.configuration.sandbox_mode = original
    end
  end
end

# Usage
MigrationGuard::SandboxHelper.sandbox_run do
  # Your migration code here
end
```

### Integration Tests

```ruby
# spec/migrations/sandbox_mode_spec.rb
require 'rails_helper'

RSpec.describe "Sandbox Mode" do
  it "does not persist changes when enabled" do
    MigrationGuard.configuration.sandbox_mode = true
    
    expect {
      CreateTestTable.new.migrate(:up)
    }.not_to change { ActiveRecord::Base.connection.tables }
    
    # But schema.rb should be updated
    expect(File.read('db/schema.rb')).to include('test_table')
  end
end
```

## Summary

Sandbox mode is a powerful feature that makes migration development safer and more predictable. By following the practices in this guide, you can:

- Develop migrations with confidence
- Catch issues before they affect your database
- Improve team collaboration on database changes
- Create a safer development environment

Remember: **When in doubt, sandbox it out!** 🧪