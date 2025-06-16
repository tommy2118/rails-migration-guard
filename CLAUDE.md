# CLAUDE.md - Rails Migration Guard Development Guidelines

## Project Philosophy

This gem solves a specific developer pain point with minimal intrusion. Follow Rails conventions, prioritize developer experience, and maintain high code quality throughout.

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

### 2. Rails Conventions

- Use Rails naming conventions (models singular, tables plural)
- Leverage Rails' built-in functionality (validations, callbacks, scopes)
- Follow RESTful principles where applicable
- Use Rails concerns for shared behavior

```ruby
# Good - Rails conventions
class MigrationGuardRecord < ApplicationRecord
  validates :version, presence: true, uniqueness: true
  
  scope :orphaned, -> { where(status: 'orphaned') }
  scope :recent, -> { where('created_at > ?', 7.days.ago) }
  
  before_save :set_branch_info
  
  def orphaned?
    status == 'orphaned' && !version_in_trunk?
  end
end
```

### 3. SOLID Principles

**Single Responsibility**
```ruby
# Good - Each class has one responsibility
class MigrationGuard::Tracker
  # Only handles tracking migrations
end

class MigrationGuard::Reporter
  # Only handles reporting status
end

class MigrationGuard::Rollbacker
  # Only handles rollback operations
end
```

**Dependency Injection**
```ruby
# Good - Dependencies injected
class MigrationGuard::StatusChecker
  def initialize(git_adapter: GitAdapter.new, record_store: MigrationGuardRecord)
    @git_adapter = git_adapter
    @record_store = record_store
  end
end
```

## Test-Driven Development with RSpec

### 1. Write Tests First

```ruby
# spec/lib/migration_guard/tracker_spec.rb
require 'rails_helper'

RSpec.describe MigrationGuard::Tracker do
  describe '#track_migration' do
    subject(:tracker) { described_class.new }
    
    context 'when enabled in development' do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        allow(MigrationGuard).to receive(:enabled?).and_return(true)
      end
      
      it 'creates a tracking record' do
        expect {
          tracker.track_migration('20240115123456', :up)
        }.to change(MigrationGuardRecord, :count).by(1)
      end
      
      it 'records the current branch' do
        allow(tracker).to receive(:current_branch).and_return('feature/new-stuff')
        
        tracker.track_migration('20240115123456', :up)
        
        record = MigrationGuardRecord.last
        expect(record.branch).to eq('feature/new-stuff')
      end
    end
    
    context 'when disabled' do
      before do
        allow(MigrationGuard).to receive(:enabled?).and_return(false)
      end
      
      it 'does not create a tracking record' do
        expect {
          tracker.track_migration('20240115123456', :up)
        }.not_to change(MigrationGuardRecord, :count)
      end
    end
  end
end
```

### 2. Test Structure

```ruby
# Use proper RSpec structure
RSpec.describe MigrationGuard::Configuration do
  # Use let for test data
  let(:config) { described_class.new }
  let(:rails_config) { ActiveSupport::OrderedOptions.new }
  
  # Group related tests
  describe '#enabled_environments' do
    it 'defaults to development and staging' do
      expect(config.enabled_environments).to eq([:development, :staging])
    end
  end
  
  # Use contexts for different scenarios
  context 'with custom configuration' do
    before do
      config.enabled_environments = [:development]
    end
    
    it 'respects custom settings' do
      expect(config.enabled_environments).to eq([:development])
    end
  end
end
```

### 3. Testing Best Practices

```ruby
# Stub external dependencies
RSpec.describe MigrationGuard::GitIntegration do
  let(:git_integration) { described_class.new }
  
  describe '#current_branch' do
    it 'returns the current git branch' do
      allow(git_integration).to receive(:`)
        .with('git rev-parse --abbrev-ref HEAD')
        .and_return("feature/my-branch\n")
      
      expect(git_integration.current_branch).to eq('feature/my-branch')
    end
  end
  
  describe '#migrations_in_trunk' do
    it 'lists migrations in the main branch' do
      allow(git_integration).to receive(:`)
        .with('git ls-tree -r main --name-only db/migrate/')
        .and_return("db/migrate/001_create_users.rb\ndb/migrate/002_add_email.rb\n")
      
      expect(git_integration.migrations_in_trunk).to eq([
        '001_create_users.rb',
        '002_add_email.rb'
      ])
    end
  end
end
```

### 4. Integration Tests

```ruby
# spec/integration/migration_workflow_spec.rb
require 'rails_helper'

RSpec.describe 'Migration workflow', type: :integration do
  before do
    # Setup test database
    MigrationGuardRecord.delete_all
  end
  
  it 'tracks migrations through their lifecycle' do
    # Simulate running a migration
    migration = TestMigration.new
    migration.version = '20240115123456'
    
    # Run migration
    expect {
      migration.migrate(:up)
    }.to change(MigrationGuardRecord, :count).by(1)
    
    # Check status
    status_reporter = MigrationGuard::StatusReporter.new
    report = status_reporter.generate
    
    expect(report[:orphaned]).to include('20240115123456')
    
    # Rollback
    rollbacker = MigrationGuard::Rollbacker.new
    rollbacker.rollback_migration('20240115123456')
    
    expect(MigrationGuardRecord.find_by(version: '20240115123456').status).to eq('rolled_back')
  end
end
```

## Code Organization

### 1. Gem Structure

```
rails-migration-guard/
├── lib/
│   ├── rails-migration-guard.rb
│   ├── migration_guard/
│   │   ├── version.rb
│   │   ├── configuration.rb
│   │   ├── tracker.rb
│   │   ├── reporter.rb
│   │   ├── rollbacker.rb
│   │   ├── git_integration.rb
│   │   └── railtie.rb
│   └── generators/
│       └── migration_guard/
│           └── install_generator.rb
├── spec/
│   ├── spec_helper.rb
│   ├── rails_helper.rb
│   ├── lib/
│   │   └── migration_guard/
│   │       ├── tracker_spec.rb
│   │       ├── reporter_spec.rb
│   │       └── configuration_spec.rb
│   └── integration/
│       └── migration_workflow_spec.rb
├── Gemfile
├── rails-migration-guard.gemspec
├── README.md
├── CHANGELOG.md
└── Rakefile
```

### 2. Namespace Everything

```ruby
# Good - Properly namespaced
module MigrationGuard
  class Tracker
    # ...
  end
  
  class Configuration
    # ...
  end
  
  module GitIntegration
    class Adapter
      # ...
    end
  end
end

# Bad - Pollutes global namespace
class Tracker
  # ...
end
```

## Database Considerations

### 1. Support Multiple Databases

```ruby
# Use database-agnostic ActiveRecord
class CreateMigrationGuardRecords < ActiveRecord::Migration[6.1]
  def change
    create_table :migration_guard_records do |t|
      t.string :version, null: false
      t.string :branch
      t.string :author
      t.string :status
      t.json :metadata  # Works across PostgreSQL, MySQL (5.7+), SQLite (with JSON1)
      t.timestamps
      
      t.index :version, unique: true
      t.index :status
      t.index :created_at
    end
  end
end
```

### 2. Handle JSON Gracefully

```ruby
class MigrationGuardRecord < ApplicationRecord
  # Serialize for databases without native JSON
  serialize :metadata, JSON if !connection.adapter_name.match?(/PostgreSQL|MySQL/)
  
  def add_metadata(key, value)
    self.metadata ||= {}
    self.metadata[key] = value
    save!
  end
end
```

## Error Handling

```ruby
module MigrationGuard
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class GitError < Error; end
  
  class GitIntegration
    def current_branch
      output = `git rev-parse --abbrev-ref HEAD 2>&1`
      
      if $?.success?
        output.strip
      else
        raise GitError, "Failed to determine current branch: #{output}"
      end
    rescue Errno::ENOENT
      raise GitError, "Git command not found"
    end
  end
end
```

## Performance Considerations

1. **Lazy Loading**: Don't load the gem unless needed
2. **Minimal Queries**: Use includes/joins to avoid N+1
3. **Caching**: Cache git operations when possible
4. **Async Operations**: Consider background jobs for cleanup

```ruby
class MigrationGuard::Reporter
  def orphaned_migrations
    @orphaned_migrations ||= begin
      MigrationGuardRecord
        .includes(:metadata)
        .where(status: 'applied')
        .select { |record| !migration_in_trunk?(record.version) }
    end
  end
  
  private
  
  def migration_in_trunk?(version)
    migrations_in_trunk.include?(version)
  end
  
  def migrations_in_trunk
    @migrations_in_trunk ||= GitIntegration.new.migrations_in_trunk
  end
end
```

## Documentation Standards

1. **YARD Documentation**: Document all public methods
2. **Examples**: Provide usage examples in comments
3. **README**: Keep it concise but complete
4. **CHANGELOG**: Follow Keep a Changelog format

```ruby
# Good documentation
module MigrationGuard
  class Tracker
    # Tracks a migration execution in the database
    #
    # @param version [String] the migration version number
    # @param direction [Symbol] :up or :down
    # @return [MigrationGuardRecord, nil] the created record or nil if tracking is disabled
    #
    # @example Track a migration going up
    #   tracker.track_migration('20240115123456', :up)
    #
    def track_migration(version, direction)
      return unless enabled?
      
      MigrationGuardRecord.create!(
        version: version,
        direction: direction.to_s,
        branch: current_branch
      )
    end
  end
end
```

## Development Workflow

1. **Write failing test** - Red
2. **Implement minimum code** - Green
3. **Refactor** - Refactor
4. **Document** - Add YARD docs
5. **Commit** - Small, focused commits

```bash
# Example workflow
$ bundle exec rspec spec/lib/migration_guard/tracker_spec.rb
# See failure

$ # Implement feature

$ bundle exec rspec spec/lib/migration_guard/tracker_spec.rb
# See success

$ bundle exec rubocop lib/migration_guard/tracker.rb
# Fix any style issues

$ git add -p
$ git commit -m "feat: add migration tracking functionality

- Tracks migrations with version, branch, and direction
- Only active in configured environments
- Integrates with ActiveRecord::Migration"
```

## Key Principles

1. **Fail Safe**: Never break the user's app
2. **Zero Config**: Work out of the box with sensible defaults
3. **Progressive Enhancement**: Advanced features are optional
4. **Clear Feedback**: Always provide actionable information
5. **Respect Rails**: Follow Rails patterns and conventions

Remember: This gem enhances the developer experience. Every decision should make developers' lives easier without adding complexity.

## Author Tracking Implementation

### Overview
Author tracking captures and displays migration authorship information to help teams coordinate and track migration ownership.

### Key Components

1. **AuthorReporter** - Dedicated class for author statistics and reports
   - Shows contribution breakdown by status (applied/orphaned/rolled back)
   - Ranks authors by activity level
   - Displays current user's rank when available

2. **Enhanced Filtering** - Author-based queries across the system
   - `MigrationGuardRecord.for_author(email)` scope with LIKE matching
   - AUTHOR environment variable support in rake tasks
   - Partial email matching for flexible searches

3. **Git Integration** - Safe author detection
   - `current_author` method that returns nil instead of raising
   - Graceful handling when git user.email is not configured

### Usage Examples

```bash
# View author statistics
$ rails db:migration:authors

# Filter history by author
$ rails db:migration:history AUTHOR=alice@example.com

# Partial matching works too
$ rails db:migration:history AUTHOR=alice
```

### Testing Author Features

```ruby
RSpec.describe MigrationGuard::AuthorReporter do
  # Always use aggregate_failures for multiple expectations
  it "displays correct migration counts" do
    aggregate_failures do
      expect(output).to match(/developer2@example\.com.*3.*1.*0.*1/)
      expect(output).to match(/developer1@example\.com.*2.*1.*1.*0/)
    end
  end
end
```