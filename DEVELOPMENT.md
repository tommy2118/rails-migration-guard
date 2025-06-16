# Development Guide

This guide is for developers working on the Rails Migration Guard gem itself.

## Table of Contents

1. [Setup](#setup)
2. [Interactive Console](#interactive-console)
3. [Running Tests](#running-tests)
4. [Development Workflow](#development-workflow)
5. [Testing Rake Tasks](#testing-rake-tasks)
6. [Manual Testing](#manual-testing)
7. [Debugging](#debugging)
8. [Code Style](#code-style)
9. [Contributing](#contributing)

## Setup

```bash
git clone https://github.com/tommy2118/rails-migration-guard.git
cd rails-migration-guard
bundle install
```

### Ruby Version Management

The gem supports Ruby 3.0+. We recommend using a Ruby version manager:

```bash
# Using rbenv
rbenv install 3.4.1
rbenv local 3.4.1

# Using rvm
rvm install 3.4.1
rvm use 3.4.1
```

## Development Tools

### Development Helper Script

The gem includes a development helper script that provides quick access to common tasks:

```bash
# Show available commands
bin/dev help

# Start interactive console
bin/dev console

# Run tests
bin/dev test
bin/dev test spec/lib/migration_guard/reporter_spec.rb  # Run specific test

# Run linter
bin/dev lint

# Run demo
bin/dev demo

# Run diagnostics
bin/dev doctor

# Clean up test artifacts
bin/dev clean
```

### Interactive Console

The gem provides an interactive console for testing and exploration:

```bash
# Launch the console with pre-loaded test data
bin/console
# Or use the dev helper
bin/dev console
```

In the console, you can:
- Test gem functionality interactively
- Inspect migration records
- Run reporters and diagnostics
- Test git integration

Example console session:
```ruby
# Check migration status
reporter = MigrationGuard::Reporter.new
puts reporter.format_status_output

# Track a new migration
tracker = MigrationGuard::Tracker.new
tracker.track_migration('20240201000001', :up)

# Run diagnostics
diagnostic = MigrationGuard::DiagnosticRunner.new
diagnostic.run_all_checks

# Test git integration
git = MigrationGuard::GitIntegration.new
puts "Current branch: #{git.current_branch}"
puts "Main branch: #{git.main_branch}"
```

## Running Tests

### Full Test Suite

```bash
# Run all tests
bundle exec rspec

# Run with documentation format
bundle exec rspec --format doc

# Run with coverage report
COVERAGE=true bundle exec rspec
```

### Specific Tests

```bash
# Run specific test file
bundle exec rspec spec/lib/migration_guard/reporter_spec.rb

# Run specific test by line number
bundle exec rspec spec/lib/migration_guard/reporter_spec.rb:42

# Run tests matching a pattern
bundle exec rspec -e "orphaned migrations"
```

### Testing Against Multiple Rails Versions

The gem is tested against Rails 6.1, 7.0, 7.1, 7.2, and 8.0:

```bash
# Test against all supported Rails versions
bundle exec rake test_all

# Test against specific version
RAILS_VERSION=7.2 bundle exec rspec

# Test against Rails 8.0
RAILS_VERSION=8.0 bundle exec rspec
```

## Development Workflow

### 1. Create Feature Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Write Tests First (TDD)

Create or modify tests in the appropriate spec file:

```ruby
# spec/lib/migration_guard/your_feature_spec.rb
RSpec.describe MigrationGuard::YourFeature do
  it "does something useful" do
    # Write your test
  end
end
```

### 3. Implement Feature

Add your implementation in the appropriate file under `lib/migration_guard/`.

### 4. Run Tests

```bash
# Run your specific tests
bundle exec rspec spec/lib/migration_guard/your_feature_spec.rb

# Run full suite
bundle exec rspec
```

### 5. Check Code Style

```bash
# Check for style violations
bundle exec rubocop

# Auto-fix safe violations
bundle exec rubocop -A
```

### 6. Test Manually

Use the console or create a test script:

```ruby
# test_script.rb
require_relative "lib/rails_migration_guard"

# Your test code here
```

Run it:
```bash
ruby test_script.rb
```

## Testing Rake Tasks

The gem provides several rake tasks. To test them in development:

### List Available Tasks

```bash
# Show all migration guard tasks
bundle exec rake -T db:migration
```

### Run Tasks in Development

```bash
# Check migration status
bundle exec rake db:migration:status

# Run diagnostics
bundle exec rake db:migration:doctor

# Clean up old records
bundle exec rake db:migration:cleanup FORCE=true
```

Note: Some tasks may show warnings about missing tables in the development environment. This is expected.

### Testing Task Loading

To verify rake tasks are properly loaded:

```bash
# Run the rake task availability spec
bundle exec rspec spec/rake_tasks_availability_spec.rb
```

## Manual Testing

### Using Development Rake Tasks

The gem provides several rake tasks for manual testing:

```bash
# Create test migrations and environment
bundle exec rake test:manual

# Generate fixture migrations for testing
bundle exec rake test:fixtures

# Clean up test artifacts
bundle exec rake test:clean
```

### Test Helpers

The gem includes test helpers for creating test scenarios:

```ruby
# In tests or console
include TestHelpers

# Create a test migration file
create_migration("20240115123456", "CreateTestTable")

# Create a migration record
create_migration_record("20240115123456", status: "orphaned")

# Mock git integration
mock_git_integration(
  current_branch: "feature/test",
  migration_versions_in_trunk: ["20240101000001", "20240102000001"]
)
```

### Creating a Test Rails App

For comprehensive testing, you can create a minimal Rails app:

```bash
# In a separate directory
rails new test_app --minimal
cd test_app

# Add the gem using local path
echo "gem 'rails_migration_guard', path: '../rails-migration-guard'" >> Gemfile
bundle install

# Install the gem
rails generate migration_guard:install
rails db:migrate

# Create test migrations
rails generate migration AddTestTable
rails generate migration AddAnotherTable
```

### Testing Git Integration

```bash
# Initialize git repo if needed
git init
git add .
git commit -m "Initial commit"

# Create branches for testing
git checkout -b feature/test-branch
rails generate migration AddFeatureTable
rails db:migrate

# Check status
rails db:migration:status
```

### Demo Mode

Run the interactive demo to see the gem's features:

```bash
# Run the demo
bin/dev demo

# This will:
# - Set up an in-memory database
# - Create sample migrations
# - Show tracking in action
# - Display status reports
# - Run diagnostics
```

## Debugging

### Enable Debug Logging

```bash
# Set environment variable
MIGRATION_GUARD_DEBUG=true bundle exec rspec

# Or in Ruby
ENV['MIGRATION_GUARD_DEBUG'] = 'true'
```

### Using Pry for Debugging

The development dependencies include pry:

```ruby
# Add breakpoint in your code
require 'pry'
binding.pry
```

### Inspecting Database State

```ruby
# In console or tests
MigrationGuard::MigrationGuardRecord.all
MigrationGuard::MigrationGuardRecord.where(status: 'orphaned')

# Check schema
ActiveRecord::Base.connection.tables
ActiveRecord::Base.connection.columns(:migration_guard_records)
```

## Code Style

We use RuboCop with Rails-specific cops:

### Check Style

```bash
# Run all cops
bundle exec rubocop

# Run specific cop
bundle exec rubocop --only Layout/LineLength

# Check specific file
bundle exec rubocop lib/migration_guard/reporter.rb
```

### Auto-fix Issues

```bash
# Safe auto-fixes only
bundle exec rubocop -a

# All auto-fixes (use with caution)
bundle exec rubocop -A
```

### Configuration

RuboCop configuration is in `.rubocop.yml`. Key settings:
- Line length: 100 characters
- Ruby version: 3.0+
- Rails cops enabled

## Contributing

### Before Submitting a PR

1. **Run full test suite**: `bundle exec rspec`
2. **Check code style**: `bundle exec rubocop`
3. **Test multiple Rails versions**: `bundle exec rake test_all`
4. **Update documentation** if needed
5. **Add CHANGELOG entry** for user-facing changes

### Writing Good Tests

```ruby
RSpec.describe MigrationGuard::Feature do
  # Use let for test data
  let(:feature) { described_class.new }
  
  # Use contexts for different scenarios
  context "when enabled" do
    before do
      allow(MigrationGuard).to receive(:enabled?).and_return(true)
    end
    
    it "performs the action" do
      expect(feature.perform).to eq(expected_result)
    end
  end
  
  context "when disabled" do
    # ...
  end
end
```

### Commit Messages

Follow conventional commits:
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `test:` Test additions/changes
- `refactor:` Code refactoring
- `chore:` Maintenance tasks

Example:
```bash
git commit -m "feat: add multi-branch migration tracking

- Track migrations across multiple target branches
- Add configuration for target branches
- Update reporter to show branch-specific status"
```

## Known Issues

### Ruby 3.4.1 Compatibility

When using Ruby 3.4.1, you may see ActiveSupport warnings:
```
warning: method redefined; discarding old to_s
```

These are from ActiveSupport 7.0.x and don't affect functionality. They're resolved in Rails 7.1+.

### Test Environment Setup

If you see "no such table" errors in tests, ensure:
1. You're requiring `rails_helper` not `spec_helper`
2. The test database is properly migrated
3. You're not loading models before database setup

## Useful Resources

- [Rails Migration Guide](https://guides.rubyonrails.org/active_record_migrations.html)
- [RSpec Best Practices](https://rspec.rubystyle.guide/)
- [Git Hooks Documentation](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)
- [ActiveRecord Callbacks](https://guides.rubyonrails.org/active_record_callbacks.html)