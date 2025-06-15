# Rails Migration Guard - Development Prompt

## Project Overview

Create a Ruby gem called `rails-migration-guard` that helps Rails developers manage database migrations in development and staging environments. The gem tracks migration state, identifies orphaned migrations (migrations run locally but not in trunk), and provides tools for cleanup and prevention.

## Core Problem Statement

Developers often create and run migrations locally that never make it back to the main branch (trunk). This causes:
- Database schema divergence between developers
- Confusion when switching branches
- Potential deployment issues
- Difficult-to-debug inconsistencies

## Key Requirements

### 1. Environment Restrictions
- MUST only operate in development and staging environments
- MUST be completely inert in production
- MUST be configurable per environment

### 2. Migration Tracking
- Track migrations in a separate table (`migration_guard_records`)
- Record: version, branch, author, status, timestamps, metadata
- Compare local migrations against trunk (main/master branch)
- Identify orphaned migrations (local-only)

### 3. Configuration System
- Flexible configuration via Rails initializer
- Options for:
  - Git integration level (off/warning/auto_rollback)
  - Tracking detail (branch/author/timestamp)
  - Behavior (sandbox mode, warnings, deploy blocks)
  - Cleanup policies (age-based, manual)

### 4. Core Features
- `rails db:migration:status` - Show migration state relative to trunk
- `rails db:migrate:sandbox` - Run migrations with automatic tracking
- `rails db:migration:rollback_orphaned` - Interactive cleanup tool
- Git hooks for branch switching warnings
- CI/CD integration for staging deployment checks

### 5. Integration Points
- Extend ActiveRecord::Migration with tracking
- Rake task integration
- Optional git hooks
- Rails generator for initial setup

## Technical Constraints

1. **Ruby Version**: Support Ruby 3.0+
2. **Rails Version**: Support Rails 6.1+
3. **Dependencies**: Minimize external dependencies
4. **Performance**: Zero impact when disabled
5. **Database**: Support PostgreSQL, MySQL, SQLite

## Architecture Guidelines

1. **Modular Design**
   - Separate concerns: tracking, git integration, UI
   - Use Rails engines/railtie for integration
   - Strategy pattern for different git integration levels

2. **Configuration First**
   - All behavior should be configurable
   - Sensible defaults for common use cases
   - Environment-specific overrides

3. **Safety First**
   - Never modify production databases
   - Always require confirmation for destructive actions
   - Comprehensive logging of all operations

4. **Testing Strategy**
   - Full RSpec coverage
   - Test against multiple Rails versions
   - Mock git operations
   - Database-agnostic tests

## Success Criteria

1. Zero-configuration basic usage
2. Clear, actionable output
3. Prevents orphaned migration issues
4. Easy to disable/remove
5. Well-documented with examples

## Deliverables

1. Gem structure with proper namespacing
2. Comprehensive test suite (RSpec)
3. README with installation and usage
4. CHANGELOG following Keep a Changelog format
5. Configuration examples
6. CI/CD integration examples

## Example Usage Vision

```bash
# Developer creates migration on feature branch
$ bin/rails generate migration AddUserPreferences
$ bin/rails db:migrate
✓ Migration tracked on branch 'feature/user-prefs'

# Developer switches branches without merging
$ git checkout main
⚠️  Warning: Orphaned migration detected!
   20240115123456_add_user_preferences.rb (not in main)
   Run `rails db:migration:rollback_orphaned` to clean up

# Check status anytime
$ bin/rails db:migration:status
═══════════════════════════════════════════════════════
Migration Status (main branch)
═══════════════════════════════════════════════════════
✓ Synced:    15 migrations
⚠ Orphaned:   1 migration (local only)
✗ Missing:    0 migrations (in trunk, not local)

Orphaned Migrations:
  20240115123456 AddUserPreferences
    Branch: feature/user-prefs
    Author: developer@example.com
    Age: 3 days
    
Run `rails db:migration:rollback_orphaned` to clean up
```

## Development Approach

1. Start with core tracking functionality
2. Add status reporting
3. Implement rollback tools
4. Add git integration
5. Polish with configuration options
6. Document thoroughly

Focus on solving the core problem elegantly before adding advanced features.