# Rails Migration Guard

[![Gem Version](https://badge.fury.io/rb/rails-migration-guard.svg)](https://badge.fury.io/rb/rails-migration-guard)
[![Build Status](https://github.com/tommy2118/rails-migration-guard/workflows/CI/badge.svg)](https://github.com/tommy2118/rails-migration-guard/actions)
[![GitHub issues](https://img.shields.io/github/issues/tommy2118/rails-migration-guard)](https://github.com/tommy2118/rails-migration-guard/issues)
[![GitHub license](https://img.shields.io/github/license/tommy2118/rails-migration-guard)](https://github.com/tommy2118/rails-migration-guard/blob/master/MIT-LICENSE)

Rails Migration Guard helps prevent orphaned database migrations in development and staging environments. It tracks migration state across git branches, identifies migrations that exist only locally, and provides tools for cleanup and prevention.

📚 **[View Full Documentation](https://tommy2118.github.io/rails-migration-guard/)** | 🎯 **[Examples & Tutorials](https://tommy2118.github.io/rails-migration-guard/examples/)** | 🔧 **[API Reference](https://tommy2118.github.io/rails-migration-guard/docs/#api-reference)**

## Compatibility

Rails Migration Guard supports:

- **Ruby**: 3.0.0 and higher
- **Rails**: 6.1.0 through 8.0+ (tested up to Rails 8.0.2)
- **Databases**: SQLite, PostgreSQL, MySQL
- **Git**: 2.0 and higher

## The Problem

When working on feature branches, developers often:
- Create and run migrations locally that never make it to the main branch
- Switch between branches with different migration states
- End up with database schemas that don't match any branch
- Experience confusing errors when migrations reference tables/columns that don't exist

Rails Migration Guard solves these issues by tracking which migrations belong to which branches and warning you about potential problems.

## Features

- 🔍 **Track migrations** across git branches automatically
- ⚠️ **Warn about orphaned migrations** when switching branches
- 🧹 **Clean up migrations** that didn't make it to main/master
- 🚂 **Sandbox mode** to test migrations without applying them
- 📊 **Status reports** showing migration state relative to trunk
- 🚫 **Production safe** - automatically disabled in production
- ⚙️ **Highly configurable** with sensible defaults
- 🤖 **CI/CD integration** with exit codes and JSON output
- 🔄 **GitHub Actions support** with PR comments and status checks
- 🐳 **Docker & CI ready** - automatic TTY detection and non-interactive modes

## Installation

Add this line to your application's Gemfile:

```ruby
group :development, :staging do
  gem 'rails_migration_guard'
end
```

Or install directly from GitHub:

```ruby
group :development, :staging do
  gem 'rails_migration_guard', github: 'tommy2118/rails-migration-guard'
end
```

Then execute:

```bash
$ bundle install
$ rails generate migration_guard:install
$ rails db:migrate
```

This will:
1. Create an initializer at `config/initializers/migration_guard.rb`
2. Generate a migration to create the `migration_guard_records` table
3. Set up the gem with sensible defaults

### Optional: Install Git Hooks

To automatically check migration status when switching branches:

```bash
$ rails generate migration_guard:hooks
```

This installs a post-checkout hook that runs migration status checks when switching branches.

For additional protection, install a pre-push hook:

```bash
$ rails generate migration_guard:hooks --pre-push
```

This prevents pushing when orphaned migrations are detected.

## Usage

### Basic Commands

```bash
# Check migration status
$ rails db:migration:status

═══════════════════════════════════════════════════════
Migration Status (main branch)
═══════════════════════════════════════════════════════
✓ Synced:    15 migrations
⚠ Orphaned:   2 migrations (local only)
✗ Missing:    0 migrations (in trunk, not local)

Orphaned Migrations:
  20240115123456 AddUserPreferences
    Branch: feature/user-prefs
    Author: developer@example.com
    Age: 3 days
    
Run `rails db:migration:rollback_orphaned` to clean up

# Roll back orphaned migrations interactively
$ rails db:migration:rollback_orphaned

# Check for issues (useful in CI/CD)
$ rails db:migration:check

# View migration history with filtering
$ rails db:migration:history                    # All recent migrations
$ rails db:migration:history BRANCH=main        # Filter by branch
$ rails db:migration:history DAYS=7             # Last 7 days
$ rails db:migration:history AUTHOR=dev@example # Filter by author
$ rails db:migration:history FORMAT=json        # JSON output

# View author statistics and contributions
$ rails db:migration:authors                    # Author report

# Recover from inconsistent migration states
$ rails db:migration:recover                     # Interactive recovery
$ AUTO=true rails db:migration:recover           # Automatic recovery
```

### Migration Recovery

Rails Migration Guard includes powerful recovery tools to help fix inconsistent migration states:

```bash
# Analyze migration inconsistencies
$ rails db:migration:recover

⚠️  Detected migration inconsistencies:

1. Partial rollback
   Version: 20240115123456
   Migration appears to be stuck in rollback state
   Severity: HIGH
   Branch: feature/user-prefs
   Last updated: 2024-01-15 14:30:45
   Recovery options: complete_rollback, restore_migration, mark_as_rolled_back

2. Orphaned schema
   Version: 20240116789012
   Schema contains migration not tracked by Migration Guard
   Severity: MEDIUM
   Recovery options: track_migration, remove_from_schema

Select option (0-3): 1
✓ Rollback completed for 20240115123456
```

Recovery features include:
- **Automatic database backups** before recovery operations
- **Multiple recovery strategies** for each type of issue
- **Interactive mode** for careful review of each issue
- **Automatic mode** for CI/CD pipelines
- **Safe rollback** of partially completed migrations
- **Git integration** to restore missing migration files

Common recovery scenarios:
- Migrations stuck in `rolling_back` state
- Schema entries without tracking records
- Missing migration files
- Duplicate tracking records
- Migrations applied but missing from schema

### Automatic Tracking

Migrations are automatically tracked when you run:

```bash
$ rails db:migrate    # Tracks as 'applied'
$ rails db:rollback   # Tracks as 'rolled_back'
```

### Author Tracking

Rails Migration Guard automatically captures author information from git when tracking migrations:

```bash
# View author statistics
$ rails db:migration:authors

👥 Migration Authors Report (main)
Author                           Total    Applied  Orphaned  Rolled Back  Latest Migration    
-----------------------------------------------------------------------------------------------
alice@example.com                    12        8         2            2    2024-06-15 14:23
bob@example.com                       7        5         1            1    2024-06-14 09:15
charlie@example.com                   3        3         0            0    2024-06-13 16:42
-----------------------------------------------------------------------------------------------

📊 Authors Summary:
  Total authors: 3
  Total tracked migrations: 22
  Most active: alice@example.com (12 migrations)
  Average per author: 7.3
  Your rank: #1 (12 migrations)

# Filter history by author
$ rails db:migration:history AUTHOR=alice
```

Author tracking helps teams:
- Identify who created specific migrations
- Track migration patterns per developer
- Find the right person to ask about a migration
- Monitor team migration activity

### Docker & CI/CD Support

Rails Migration Guard automatically detects non-TTY environments (Docker, CI) and switches to non-interactive mode:

```bash
# In Docker containers - automatically non-interactive
docker exec -it myapp rails db:migration:rollback_orphaned

# Force non-interactive mode
FORCE=true rails db:migration:rollback_orphaned
NON_INTERACTIVE=true rails db:migration:recover

# CI/CD automation
AUTO=true rails db:migration:recover  # Auto-apply first recovery option
```

See [Docker & CI/CD Documentation](docs/docker-ci-support.md) for detailed examples.

### Sandbox Mode

Test migrations without applying them:

```ruby
# config/initializers/migration_guard.rb
MigrationGuard.configure do |config|
  config.sandbox_mode = true
end
```

## Configuration

```ruby
# config/initializers/migration_guard.rb
MigrationGuard.configure do |config|
  # Environments where MigrationGuard is active
  config.enabled_environments = [:development, :staging]

  # Git integration level
  # :off - No git integration
  # :warning - Warn about orphaned migrations
  # :auto_rollback - Automatically suggest rollback
  config.git_integration_level = :warning

  # Track additional information
  config.track_branch = true
  config.track_author = true      # Captures git user.email
  config.track_timestamp = true

  # Behavior options
  config.warn_on_switch = true             # Warn when switching branches
  config.block_deploy_with_orphans = false # Block deploys with orphaned migrations

  # Cleanup policies
  config.auto_cleanup = false              # Automatically clean up old records
  config.cleanup_after_days = 30           # Days before cleanup

  # Main branch names to check against
  config.main_branch_names = %w[main master trunk]
  
  # Target branches to compare migrations against (optional)
  # When set, migrations will be compared against all specified branches
  # instead of just the main branch. Useful for teams with multiple
  # long-lived branches (e.g., develop, staging, production)
  # config.target_branches = %w[main develop staging]
  
  # Git integration settings (see TROUBLESHOOTING.md for edge cases)
  # config.git_timeout = 5.seconds
  # config.handle_git_errors = true  # Continue without git on errors
  # config.sanitize_git_input = true  # Clean branch names automatically
  
  # Logging configuration
  # config.log_level = :info  # :debug, :info, :warn, :error, :fatal
  # config.logger = Rails.logger  # or Logger.new('log/migration_guard.log')
  
  # Enable debug logging via environment variable
  # ENV['MIGRATION_GUARD_DEBUG'] = 'true'
end
```

## CI/CD Integration

Rails Migration Guard provides comprehensive CI/CD support with dedicated commands and integrations.

### Quick Start

```bash
# CI-specific command with proper exit codes
bundle exec rails db:migration:ci

# Strict mode - fail on any issues
bundle exec rails db:migration:ci STRICT=true

# JSON output for parsing
bundle exec rails db:migration:ci FORMAT=json
```

### GitHub Actions

Rails Migration Guard includes native GitHub Actions support with:
- 🔄 Ready-to-use workflow files
- 💬 Automatic PR comments
- ✅ Status checks
- 📊 Job summaries

```yaml
# .github/workflows/migration-check.yml
name: Migration Check
on: pull_request

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      
      - name: Setup test database
        run: bundle exec rails db:test:prepare
      
      - uses: ./.github/actions/migration-guard
        with:
          strict: false
          comment-on-pr: true
```

**📘 See the [GitHub Actions guide](docs/github-actions.md) for detailed setup and advanced configurations.**

### Other CI Platforms

See the [CI Integration guide](docs/ci-integration.md) for examples with:
- GitLab CI
- CircleCI
- Jenkins
- Travis CI

### Staging Protection

```ruby
# config/initializers/migration_guard.rb
MigrationGuard.configure do |config|
  config.block_deploy_with_orphans = true if Rails.env.staging?
end
```

## How It Works

1. **Tracking**: When migrations run, MigrationGuard records the version, branch, author, and status
2. **Comparison**: It compares local migrations against those in your main branch
3. **Detection**: Identifies migrations that exist locally but not in trunk (orphaned)
4. **Cleanup**: Provides tools to safely roll back orphaned migrations

## Best Practices

1. **Review before merging**: Check `rails db:migration:status` before creating PRs
2. **Clean up regularly**: Roll back orphaned migrations when switching contexts
3. **Use sandbox mode**: Test complex migrations before applying them
4. **Configure for your workflow**: Adjust settings based on team size and branch strategy

## Debug Logging

MigrationGuard includes comprehensive logging to help diagnose issues in production:

```bash
# Enable debug logging temporarily
MIGRATION_GUARD_DEBUG=true rails db:migration:status

# Or configure in your initializer
MigrationGuard.configure do |config|
  config.log_level = :debug
  config.logger = Logger.new('log/migration_guard.log')
end
```

Debug logs include:
- Git operations and branch detection
- Migration tracking and status changes
- Performance timing for database operations
- Detailed error messages with context

## Troubleshooting

For comprehensive troubleshooting information, see our [Troubleshooting Guide](TROUBLESHOOTING.md).

Common issues:
- **"Migration not found" errors**: Usually means you have orphaned migrations. Run `rails db:migration:status` to identify them.
- **Git integration not working**: Ensure you're in a git repository and have git installed. See [Git Integration Edge Cases](TROUBLESHOOTING.md#git-integration-edge-cases) for advanced scenarios.
- **Special branch names**: Branch names with spaces, special characters, or unicode may need special handling. See the troubleshooting guide.
- **Performance concerns**: The gem has minimal overhead. Set `git_integration_level: :off` to disable git operations if needed.

## Development

After checking out the repo:

```bash
$ bundle install
$ bundle exec rspec        # Run tests
$ bundle exec rubocop      # Check code style
$ bundle exec rake         # Run default tasks
```

## Known Issues

### Ruby 3.4.1 Compatibility

When using Ruby 3.4.1 with Rails 7.0.x, you may see warnings like:

```
warning: method redefined; discarding old to_s
warning: previous definition of to_s was here
```

These warnings come from ActiveSupport 7.0.x itself and do not affect the functionality of Rails Migration Guard. The warnings are resolved in Rails 7.1+ and Rails 8.0+. If the warnings are bothersome, consider:

1. Upgrading to Rails 7.1 or later
2. Using Ruby 3.3.x until you can upgrade Rails
3. Suppressing warnings with `RUBYOPT="-W0"` (not recommended for development)

## Contributing

1. Fork it (https://github.com/tommy2118/rails-migration-guard/fork)
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Write tests for your changes
4. Make your changes and ensure tests pass
5. Commit your changes (`git commit -am 'Add some feature'`)
6. Push to the branch (`git push origin feature/my-new-feature`)
7. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Credits

Created and maintained by Tommy A. Caruso.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a history of changes.