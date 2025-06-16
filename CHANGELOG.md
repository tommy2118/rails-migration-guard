# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
- Rails 8.0 compatibility documentation and testing
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