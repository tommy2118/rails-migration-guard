# CLAUDE.md - Rails Migration Guard Development Guidelines

## Project Philosophy

This gem solves a specific developer pain point with minimal intrusion. Follow Rails conventions, prioritize developer experience, and maintain high code quality throughout.

## Development Process

- We need to use PRs for code changes

## Ruby & Rails Best Practices

### 1. Follow the Ruby Style Guide

```ruby
# Good - Ruby style guide compliant
class MigrationGuard::Tracker
  def track_migration(version, direction)
    return unless enabled?

    MigrationGuardRecord.create!(
      version: version,
      branch: current_branch,
      status: direction.to_s
    )
  end

  private

  def enabled?
    MigrationGuard.enabled?
  end
end

# Bad - Style violations
class MigrationGuard::Tracker
  def TrackMigration(version,direction)
    if(enabled?())
      MigrationGuardRecord.create!({:version=>version,:branch=>current_branch(),:status=>direction.to_s()})
    end
  end
end
```

[... rest of the existing content remains unchanged ...]