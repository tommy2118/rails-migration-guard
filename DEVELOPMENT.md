# Development Guide

This guide is for developers working on the Rails Migration Guard gem itself.

## Setup

```bash
git clone https://github.com/tommy2118/rails-migration-guard.git
cd rails-migration-guard
bundle install
```

## Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/lib/migration_guard/reporter_spec.rb

# Run with specific Rails version
RAILS_VERSION=7.2 bundle exec rspec
```

## Running Rake Tasks

The gem's rake tasks are available in the development environment:

```bash
# List all available tasks
bundle exec rake -T

# Run specific tasks
bundle exec rake db:migration:status
bundle exec rake db:migration:doctor
```

Note: When running in the gem development environment, some tasks may report missing tables or database connections. This is expected behavior as the gem development environment doesn't have a full Rails application setup.

## Testing Against Multiple Rails Versions

The gem is tested against Rails 6.1, 7.0, 7.1, 7.2, and 8.0:

```bash
# Test against all supported Rails versions
bundle exec rake test_all

# Test against specific version
RAILS_VERSION=7.2 bundle exec rspec
```

## Code Style

We use RuboCop for code style enforcement:

```bash
# Check code style
bundle exec rubocop

# Auto-fix style issues
bundle exec rubocop -A
```

## Known Issues

### Ruby 3.4.1 Compatibility

When using Ruby 3.4.1, you may see ActiveSupport warnings. These are expected and don't affect functionality. See the README for more details.