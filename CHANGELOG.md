# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Interactive Setup Assistant for New Developers** (#22) - Comprehensive onboarding experience:
  - New `rails db:migration:setup` command for development environment analysis
  - Checks Migration Guard installation and configuration status
  - Analyzes database connection and git repository setup
  - Detects orphaned and missing migrations with explanations
  - Provides actionable recommendations for environment setup
  - Offers interactive command execution for suggested fixes
  - Shows helpful commands and usage patterns for new team members
  - Colorized output with clear status indicators (✓/⚠/✗)
  - Comprehensive validation of schema consistency
  - Guides new developers through proper environment setup

### Fixed
- **Warning Consolidation** (#105, #127) - Fixed warning spam during multiple migrations:
  - `:smart` mode now properly consolidates warnings for batch migrations
  - Added new `:summary` mode that always shows consolidated format
  - Single migrations in smart mode show regular warnings
  - Multiple migrations show a summary at the end
  - Reduces noise and improves UX during migration runs

### Added
- **Enhanced Doctor Command** (#86) - Doctor now detects stuck migrations:
  - Detects migrations stuck in "rolling_back" status 
  - Configurable timeout (default: 10 minutes) via `config.stuck_migration_timeout`
  - Reports the number of stuck migrations and how long they've been stuck
  - Shows time in minutes or hours for better readability
  - Recommends running `rails db:migration:recover` to fix stuck migrations
  - Both doctor and recovery system use the same configurable timeout

- **Rails 8.0 Compatibility** (#72) - Full support for Rails 8.0:
  - Updated test suite to run on Rails 8.0.2
  - Fixed timezone deprecation warnings with `config.active_support.to_time_preserves_timezone = :zone`
  - Confirmed compatibility with Rails 8.0 migration APIs
  - CI matrix includes Ruby 3.2+ with Rails 8.0 (Rails 8.0 requires Ruby 3.2+)
  - All tests passing without deprecation warnings

### Added
- **Migration Recovery Tools** (#29) - Comprehensive tools for recovering from failed rollbacks:
  - New `rails db:migration:recover` rake task for analyzing and fixing inconsistent migration states
  - Detects four types of migration inconsistencies:
    - Partial rollbacks stuck in `rolling_back` state
    - Orphaned schema changes (migrations in schema_migrations but not tracked)
    - Missing migration files for applied migrations
    - Version conflicts (duplicate tracking records)
  - Interactive recovery mode with multiple options per issue type:
    - Complete rollback operations
    - Restore migrations to applied state
    - Track untracked migrations
    - Remove duplicates and consolidate records
    - Manual SQL intervention guidance
  - Automatic mode for CI/CD pipelines: `AUTO=true rails db:migration:recover`
  - Database backup functionality before recovery operations:
    - PostgreSQL support via pg_dump
    - MySQL support via mysqldump
    - SQLite support via file copy
    - Automatic skip for in-memory databases
  - Safe command execution using Open3 to prevent injection attacks
  - Colorized output with severity levels (CRITICAL, HIGH, MEDIUM)
  - Comprehensive test coverage for all recovery scenarios
- **Migration History Feature** (#28) - Comprehensive migration history tracking and reporting:
  - New `rails db:migration:history` rake task for viewing migration execution history
  - Multiple output formats: table (default), JSON, and CSV
  - Advanced filtering options:
    - `BRANCH=main` - Filter by git branch
    - `DAYS=7` - Show migrations from last N days
    - `VERSION=20240101000001` - Search for specific migration version
    - `LIMIT=50` - Limit number of results (default: 50)
    - `FORMAT=json` - Change output format (table/json/csv)
  - Enhanced migration tracking with metadata:
    - Direction tracking (UP/DOWN) for rollback visibility
    - Execution time recording for performance analysis
    - Detailed timestamps for all migration operations
    - Branch and author information for team coordination
  - Colorized status indicators with emoji support:
    - ✅ Applied/Synced migrations (green)
    - ⤺ Rolled back migrations (yellow)
    - ⚠️ Orphaned migrations (red)
  - Comprehensive summary statistics:
    - Total migration counts by status
    - Branch distribution analysis
    - Date range coverage
    - Execution performance insights
  - New model scopes and helper methods:
    - `MigrationGuardRecord.history_ordered` - Chronological ordering
    - `MigrationGuardRecord.within_days(n)` - Recent migrations
    - `MigrationGuardRecord.for_version(v)` - Version search
    - `#migration_file_name` - Smart file name detection
    - `#display_status` - Human-readable status with icons
    - `#execution_time` - Formatted timing information
- **Comprehensive Author Tracking** (#21) - Enhanced migration authorship features:
  - New `rails db:migration:authors` rake task for author statistics:
    - Shows total, applied, orphaned, and rolled back counts per author
    - Ranks authors by activity level and latest migration
    - Displays current user's rank and contribution summary
    - Colorized output with smart truncation for long names
  - Author filtering for migration history:
    - `rails db:migration:history AUTHOR=email` - Filter by author email
    - Supports partial matching for flexible searches
  - New `AuthorReporter` class for dedicated author analysis
  - Enhanced `GitIntegration` with non-throwing `current_author` method
  - Graceful handling when git user.email is not configured
- **Developer Experience Improvements** (#54):
  - Interactive console (`bin/console`) with pre-loaded test data and helper functions
  - Development helper script (`bin/dev`) with commands for testing, linting, and demos
  - Enhanced development documentation in `DEVELOPMENT.md`
  - Development-specific rake tasks:
    - `test:manual` - Set up manual testing environment
    - `test:fixtures` - Generate sample migration files
    - `test:clean` - Clean up test artifacts
  - Live demo mode showing gem features in action
- **Documentation and Website Enhancements**:
  - Beautiful GitHub Pages site with Apple and Steve Schoger-inspired design
  - Comprehensive documentation with interactive examples and terminal demos
  - Tailwind CSS styling with custom animations and responsive layouts
  - Complete API reference with code examples and usage patterns
  - Installation guides and troubleshooting resources
  - Multi-page navigation with clean Jekyll structure
- **Rails 8.0 Compatibility**:
  - Full support for Rails 8.0 (tested with 8.0.2)
  - Updated CI matrix to test against Rails 8.0
  - Fixed deprecated `connection_config` method (now using `connection_db_config`)
  - Added Rails 8 compatibility test suite
  - Updated dependencies for Rails 8.x support
- Debug logging enhancements with visible output options
- Initial release of Rails Migration Guard
- Core migration tracking functionality
- Automatic tracking of migration up/down operations
- Git integration to compare against main/master branch
- Orphaned migration detection
- Interactive rollback tools for orphaned migrations
- Comprehensive status reporting
- Sandbox mode for testing migrations
- Configurable behavior per environment
- Rails generator for easy setup
- Colorized CLI output for better readability:
  - Success messages in green
  - Warnings in yellow
  - Errors in red
  - Respects NO_COLOR environment variable
  - Configurable via `config.colorize_output`
- Git hooks generator for automatic migration checking:
  - `rails generate migration_guard:hooks` - Install post-checkout hook
  - `rails generate migration_guard:hooks --pre-push` - Also install pre-push hook
- Rake tasks for migration management:
  - `db:migration:status` - Show migration status
  - `db:migration:rollback_orphaned` - Roll back orphaned migrations
  - `db:migration:check` - Check for issues (CI/CD friendly)
  - `db:migration:cleanup` - Clean up old records
- Automatic cleanup policies for old records
- Branch and author tracking
- Console helpers for quick status checks
- Production safety (automatically disabled in production)
- Support for Rails 6.1+ and Ruby 3.0+

### Improved
- **Enhanced Migration Tracking**: Now records direction (UP/DOWN), execution time, and detailed metadata
- **Better Error Handling**: Graceful degradation when CSV gem is unavailable in Ruby 3.4+
- **Test Infrastructure**: Comprehensive test coverage with aggregate_failures for better debugging
- **Code Quality**: RuboCop compliant with appropriate disable comments for complex reporting methods
- **Performance**: Optimized database queries with proper indexing and scoping

### Fixed
- **CI/CD Integration**: Resolved failing tests in rake task integration by improving test flexibility
- **Ruby 3.4 Compatibility**: Fixed CSV gem loading and improved ActiveRecord compatibility
- **Git Integration**: Better handling of missing git repositories and branch detection
- **Database Support**: Improved JSON field handling across PostgreSQL, MySQL, and SQLite

### Changed
- **Migration Tracking Schema**: Enhanced with new metadata fields for direction and execution time
  - Existing installations will need to run `rails db:migrate` after updating
  - Previous migration records remain compatible and functional
- **Tracker API**: `track_migration` method now accepts optional `execution_time` parameter
  - Backward compatible - existing calls continue to work without changes

### Security
- All operations are restricted to non-production environments
- No automatic destructive operations without confirmation

## [0.1.0] - 2024-01-15

### Added
- Initial gem structure and configuration
- Basic tracking functionality
- Test suite with 94%+ coverage

[Unreleased]: https://github.com/tommy2118/rails-migration-guard/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/tommy2118/rails-migration-guard/releases/tag/v0.1.0