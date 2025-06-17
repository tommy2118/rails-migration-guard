---
layout: default
title: Quick Start Guide
---

# Rails Migration Guard: Quick Start Guide

This guide will help you quickly get up and running with Rails Migration Guard and show you the most common workflows for managing your Rails migrations effectively.

## Installation in 60 Seconds

Add Rails Migration Guard to your Gemfile:

```ruby
# Gemfile
group :development, :staging do
  gem 'rails_migration_guard'
end
```

Then install and set up:

```bash
# Install the gem
bundle install

# Generate initializer and migration
rails generate migration_guard:install

# Run the migration to create tracking table
rails db:migrate

# Optional: Install Git hooks for automatic checks
rails generate migration_guard:hooks
```

That's it! Rails Migration Guard is now tracking your migrations and will alert you to potential issues.

## First Day Workflow

Here's what to do on your first day using Rails Migration Guard:

1. **Check Migration Status**: See the current state of migrations relative to your main branch:

   ```bash
   rails db:migration:status
   ```

2. **Generate a Migration**: Create migrations as usual with Rails:

   ```bash
   rails generate migration AddUserPreferences
   ```

3. **Run Migrations**: Use standard Rails commands - they're automatically tracked:

   ```bash
   rails db:migrate
   ```

4. **Check for Orphaned Migrations**: After switching branches or before committing:

   ```bash
   rails db:migration:status
   ```

5. **Clean Up if Needed**: Roll back orphaned migrations interactively:

   ```bash
   rails db:migration:rollback_orphaned
   ```

## Essential Commands

Here are the commands you'll use most frequently:

| Command | Purpose |
|---------|---------|
| `rails db:migration:status` | Check migration status relative to main branch |
| `rails db:migration:rollback_orphaned` | Interactively roll back orphaned migrations |
| `rails db:migration:history` | View migration history with filtering options |
| `rails db:migration:recover` | Fix inconsistent migration states |
| `rails db:migration:doctor` | Run diagnostics on your setup |
| `rails db:migration:authors` | See contribution statistics by developer |

## Branch Switching Workflow

When switching between feature branches, follow this workflow to avoid migration issues:

```bash
# Before switching branches
git stash     # Stash any changes if needed
rails db:migration:status   # Check for orphaned migrations

# If orphaned migrations are found
rails db:migration:rollback_orphaned

# Switch branches
git checkout other-branch

# After switching
rails db:migration:status   # Check if any migrations are missing
rails db:migrate            # Apply any missing migrations
```

With the Git hooks installed, you'll automatically be notified about migration changes when switching branches.

## Handling Orphaned Migrations

Orphaned migrations are those that exist on your local branch but not in the main branch. They can cause schema inconsistencies if not handled properly.

### Identifying Orphaned Migrations

```bash
rails db:migration:status
```

Look for migrations marked with "⚠ Orphaned" in the output.

### Options for Handling Orphaned Migrations

1. **Roll them back** (recommended if they're not needed):
   ```bash
   rails db:migration:rollback_orphaned
   ```

2. **Commit them** (if they should be part of your feature branch):
   ```bash
   git add db/migrate/20240601123456_add_user_preferences.rb
   git commit -m "Add migration for user preferences"
   ```

3. **Sandbox Test** (to see effects without applying):
   ```ruby
   # In config/initializers/migration_guard.rb
   MigrationGuard.configure do |config|
     config.sandbox_mode = true
   end
   ```

## Team Collaboration Tips

For effective team collaboration:

1. **Before Creating PRs**: Check and clean up orphaned migrations
   ```bash
   rails db:migration:status
   rails db:migration:rollback_orphaned  # If needed
   ```

2. **Use Author Tracking**: See who's creating migrations
   ```bash
   rails db:migration:authors
   ```

3. **Filter History by Author**: When helping teammates
   ```bash
   rails db:migration:history AUTHOR=alice@example.com
   ```

4. **Set Up CI Checks**: Add to your CI pipeline
   ```bash
   bundle exec rails db:migration:ci
   ```

## Troubleshooting Common Issues

### "Migration not found" Errors

This usually means you have orphaned migrations. Check status and roll back if needed:

```bash
rails db:migration:status
rails db:migration:rollback_orphaned
```

### Schema Inconsistencies

Use the recovery tool to fix database inconsistencies:

```bash
rails db:migration:recover
```

### Git Integration Issues

If git integration isn't working properly:

```bash
# Run diagnostics
rails db:migration:doctor

# Check your configuration
# In config/initializers/migration_guard.rb
MigrationGuard.configure do |config|
  config.main_branch_names = %w[main master trunk your-branch-name]
end
```

## Visual Example: Typical Workflow

```
┌─────────────────────────────────────────┐
│ 1. Create feature branch                │
│    git checkout -b feature/new-feature  │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│ 2. Generate and run migrations          │
│    rails generate migration AddNewTable │
│    rails db:migrate                     │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│ 3. Implement feature with the migration │
│    ... write code ...                   │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│ 4. Check status before commit/PR        │
│    rails db:migration:status            │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│ 5. Make sure migration is committed     │
│    git add db/migrate/20240601_*.rb     │
│    git commit -m "Add new feature"      │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│ 6. Create PR with the migration         │
│    gh pr create                         │
└─────────────────────────────────────────┘
```

## Next Steps

Now that you're up and running, check out:

- [Full Documentation](https://tommy2118.github.io/rails-migration-guard/docs/)
- [Configuration Options](https://tommy2118.github.io/rails-migration-guard/docs/#configuration)
- [Advanced Examples](https://tommy2118.github.io/rails-migration-guard/examples/)
- [CI/CD Integration](https://tommy2118.github.io/rails-migration-guard/ci-integration)
- [GitHub Actions](https://tommy2118.github.io/rails-migration-guard/github-actions)