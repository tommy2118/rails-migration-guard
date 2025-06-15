# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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