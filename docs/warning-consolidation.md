# Warning Consolidation

Rails Migration Guard can consolidate warnings when running multiple migrations to reduce console noise and improve developer experience.

## Overview

When running multiple migrations (e.g., `rails db:migrate`), Migration Guard can show warnings either:
- After each individual migration (default in development)
- Once at the end with a consolidated summary
- Smart mode that adapts based on the number of migrations

## Configuration

Configure the warning behavior in your initializer:

```ruby
MigrationGuard.configure do |config|
  # Options: :each, :once, :smart (default)
  config.warning_frequency = :smart
  
  # Maximum number of warnings to display (default: 10)
  config.max_warnings_display = 10
end
```

### Warning Frequency Options

#### `:each` - Show warnings after every migration
Best for development when you want immediate feedback:
```
== 20240101000001 CreateUsers: migrating ================
-- create_table(:users)
   -> 0.0012s
== 20240101000001 CreateUsers: migrated (0.0013s) =======

⚠️  Migration Guard Warning
==================================================

You have 1 migration that is not in the main branch:

  • 20240101000001 - feature/users

Suggestions:
  1. Commit these migrations to your branch before merging
  2. Run 'rails db:migration:rollback_orphaned' to remove them
  3. Run 'rails db:migration:status' for more details
```

#### `:once` - Show consolidated summary at the end
Best for CI/CD or when running many migrations:
```
== 20240101000001 CreateUsers: migrating ================
-- create_table(:users)
   -> 0.0012s
== 20240101000001 CreateUsers: migrated (0.0013s) =======

== 20240101000002 AddEmailToUsers: migrating ============
-- add_column(:users, :email, :string)
   -> 0.0008s
== 20240101000002 AddEmailToUsers: migrated (0.0009s) ===

============================================================
⚠️  Migration Guard Summary
============================================================

✅ Successfully ran 2 migration(s) in 0.52 seconds

⚠️  You have 2 migrations that are not in the main branch:

  • 20240101000001 - feature/users
  • 20240101000002 - feature/users

Suggestions:
  1. Commit these migrations to your branch before merging
  2. Run 'rails db:migration:rollback_orphaned' to remove them
  3. Run 'rails db:migration:status' for more details
```

#### `:smart` - Adaptive behavior (default)
- Shows warnings immediately for single migrations
- Shows consolidated summary for multiple migrations
- Best for most use cases

## Use Cases

### Development Workflow
```ruby
# Show warnings immediately in development
config.warning_frequency = :each
```

### CI/CD Pipeline
```ruby
# Reduce noise in CI logs
config.warning_frequency = :once
```

### Team Preference
```ruby
# Let the gem decide based on context
config.warning_frequency = :smart  # default
```

## Disabling Warnings

To completely disable post-migration warnings:
```ruby
config.warn_after_migration = false
```

## Implementation Details

The warning consolidation is handled by:
- `MigrationGuard::WarningCollector` - Collects and consolidates warnings
- `MigrationGuard::MigratorExtension` - Detects batch migrations
- `MigrationGuard::MigrationExtension` - Tracks individual migrations

The system automatically detects when Rails is running multiple migrations and adjusts the warning behavior accordingly.