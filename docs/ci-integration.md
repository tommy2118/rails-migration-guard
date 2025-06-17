# CI/CD Integration Guide

Rails Migration Guard provides robust CI/CD integration to prevent orphaned migrations from reaching production. This guide covers how to integrate migration checks into your continuous integration pipeline.

## Quick Start

Add this to your CI pipeline to check for migration issues:

```bash
# Basic CI check
bundle exec rails db:migration:ci

# Strict mode (fails on any issues)
bundle exec rails db:migration:ci STRICT=true

# JSON output for machine processing
bundle exec rails db:migration:ci FORMAT=json
```

### GitHub Actions

For GitHub Actions users, see our [dedicated GitHub Actions guide](./github-actions.html) for:
- Ready-to-use workflow files
- Reusable composite action
- PR comment integration
- Matrix build examples

## The `rails db:migration:ci` Command

The CI command is specifically designed for automated environments. It:

- ✅ Returns appropriate exit codes (0=success, 1=warnings, 2=errors)
- ✅ Supports both human-readable and machine-readable output
- ✅ Works in all Rails environments (even when MigrationGuard is disabled)
- ✅ Provides detailed issue reports and recommended fixes
- ✅ Handles errors gracefully

### Exit Codes

| Exit Code | Meaning | Description |
|-----------|---------|-------------|
| 0 | Success | No migration issues found |
| 1 | Warning | Issues found but not critical (default behavior) |
| 2 | Error | Critical issues found or strict mode triggered |

### Strictness Levels

Control how the CI command responds to migration issues:

| Level | Orphaned Migrations | Missing Migrations | Exit Code |
|-------|-------------------|-------------------|-----------|
| `permissive` | Warning (1) | Warning (1) | 1 |
| `warning` (default) | Warning (1) | Warning (1) | 1 |
| `strict` | Error (2) | Error (2) | 2 |

```bash
# Set strictness level
bundle exec rails db:migration:ci STRICTNESS=strict
bundle exec rails db:migration:ci STRICTNESS=warning
bundle exec rails db:migration:ci STRICTNESS=permissive

# Legacy strict flag (equivalent to STRICTNESS=strict)
bundle exec rails db:migration:ci STRICT=true
```

## Output Formats

### Text Format (Default)

Human-readable output perfect for logs and developer review:

```bash
$ bundle exec rails db:migration:ci
✅ Migration Guard CI Check (feature/user-profiles → main)

🔍 Orphaned Migrations Found:
  • 20240115123456 (feature/user-profiles) - alice@example.com

💡 Recommended Actions:
  1. Roll back orphaned migrations:
     rails db:migration:rollback_specific VERSION=20240115123456
  2. Or commit migration files if they should be included

📊 Summary:
   Orphaned: 1
   Missing: 0
   Strictness: warning
   Exit code: 1
```

### JSON Format

Machine-readable output for CI integration and tooling:

```bash
$ bundle exec rails db:migration:ci FORMAT=json
{
  "migration_guard": {
    "version": "0.1.0",
    "status": "warning",
    "summary": {
      "total_orphaned": 1,
      "total_missing": 0,
      "issues_found": 1,
      "main_branch": "main",
      "current_branch": "feature/user-profiles"
    },
    "orphaned_migrations": [
      {
        "version": "20240115123456",
        "file": "20240115123456_*.rb",
        "branch": "feature/user-profiles",
        "author": "alice@example.com",
        "created_at": "2024-01-15T12:34:56Z"
      }
    ],
    "missing_migrations": [],
    "branch_info": {
      "current": "feature/user-profiles",
      "main": "main",
      "ahead_count": 0,
      "behind_count": 0
    },
    "timestamp": "2024-01-15T13:00:00Z",
    "exit_code": 1,
    "strictness": "warning"
  }
}
```

## CI Platform Examples

### GitHub Actions

**📘 See our [comprehensive GitHub Actions guide](./github-actions.html) for detailed setup instructions, reusable actions, and advanced configurations.**

Basic example:

```yaml
# .github/workflows/migration_guard.yml
name: Migration Guard Check

on:
  pull_request:
    paths:
      - 'db/migrate/**'
      - 'db/schema.rb'

jobs:
  check-migrations:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:14
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for proper branch comparison
      
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      
      - name: Setup Database
        run: |
          bundle exec rails db:setup
        env:
          RAILS_ENV: test
          DATABASE_URL: postgresql://postgres:postgres@localhost/test
      
      - name: Check for migration issues
        run: |
          bundle exec rails db:migration:ci --strict
        env:
          RAILS_ENV: test
          DATABASE_URL: postgresql://postgres:postgres@localhost/test
```

### GitLab CI

```yaml
# .gitlab-ci.yml
stages:
  - test

migration_guard:
  stage: test
  image: ruby:3.1
  services:
    - postgres:14
  variables:
    POSTGRES_DB: test
    POSTGRES_USER: postgres
    POSTGRES_PASSWORD: postgres
    DATABASE_URL: postgresql://postgres:postgres@postgres/test
    RAILS_ENV: test
  before_script:
    - bundle install
    - bundle exec rails db:setup
  script:
    - bundle exec rails db:migration:ci STRICTNESS=strict FORMAT=json
  only:
    changes:
      - db/migrate/**/*
      - db/schema.rb
```

### CircleCI

```yaml
# .circleci/config.yml
version: 2.1

jobs:
  migration_guard:
    docker:
      - image: cimg/ruby:3.1
      - image: cimg/postgres:14.0
        environment:
          POSTGRES_DB: test
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
    
    steps:
      - checkout
      - run:
          name: Install dependencies
          command: bundle install
      
      - run:
          name: Setup database
          command: |
            bundle exec rails db:setup
          environment:
            RAILS_ENV: test
            DATABASE_URL: postgresql://postgres@localhost/test
      
      - run:
          name: Check migrations
          command: |
            bundle exec rails db:migration:ci STRICT=true
          environment:
            RAILS_ENV: test
            DATABASE_URL: postgresql://postgres@localhost/test

workflows:
  version: 2
  test:
    jobs:
      - migration_guard:
          filters:
            branches:
              ignore: main
```

### Jenkins

```groovy
// Jenkinsfile
pipeline {
    agent any
    
    environment {
        RAILS_ENV = 'test'
        DATABASE_URL = 'postgresql://postgres:postgres@localhost/test'
    }
    
    stages {
        stage('Setup') {
            steps {
                sh 'bundle install'
                sh 'bundle exec rails db:setup'
            }
        }
        
        stage('Migration Guard Check') {
            steps {
                script {
                    def result = sh(
                        script: 'bundle exec rails db:migration:ci FORMAT=json STRICTNESS=strict',
                        returnStatus: true
                    )
                    
                    if (result != 0) {
                        error("Migration issues detected. Check logs for details.")
                    }
                }
            }
        }
    }
    
    post {
        always {
            // Archive migration check results
            archiveArtifacts artifacts: 'log/migration_guard.log', allowEmptyArchive: true
        }
    }
}
```

## Environment Variables

The CI command supports these environment variables:

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `FORMAT` | `text`, `json` | `text` | Output format |
| `STRICT` | `true`, `false` | `false` | Legacy strict mode flag |
| `STRICTNESS` | `permissive`, `warning`, `strict` | `warning` | Strictness level |

Case-insensitive variants are also supported (`format`, `strict`, `strictness`).

## Integration Tips

### 1. Run Only on Migration Changes

Configure your CI to run migration checks only when migration-related files change:

```yaml
# GitHub Actions
on:
  pull_request:
    paths:
      - 'db/migrate/**'
      - 'db/schema.rb'
      - 'Gemfile*'
```

### 2. Parallel Builds

The CI command is fast (typically < 5 seconds) and can run in parallel with other checks:

```yaml
jobs:
  tests:
    # ... your existing tests
  
  migration_guard:
    runs-on: ubuntu-latest
    # ... migration guard setup
```

### 3. Custom Strictness by Branch

Adjust strictness based on the target branch:

```bash
# Strict for main/production branches
if [[ "$TARGET_BRANCH" == "main" ]]; then
  bundle exec rails db:migration:ci STRICTNESS=strict
else
  bundle exec rails db:migration:ci STRICTNESS=warning
fi
```

### 4. Artifact Collection

Save migration check results for debugging:

```yaml
- name: Save migration check results
  if: failure()
  run: |
    bundle exec rails db:migration:ci FORMAT=json > migration_check.json
    
- uses: actions/upload-artifact@v3
  if: failure()
  with:
    name: migration-check-results
    path: migration_check.json
```

## Troubleshooting

### Common Issues

**Exit code 2 in CI but local tests pass:**
- Ensure your CI environment has the same database state as local
- Check that all migration files are committed
- Verify git history is complete (`fetch-depth: 0` in GitHub Actions)

**"MigrationGuard is not enabled" message:**
- This is normal and returns exit code 0
- MigrationGuard automatically disables in production and can be configured for other environments

**JSON parsing errors:**
- Ensure you're using `FORMAT=json` not `FORMAT=JSON`
- Check for mixed output (some gems may output to stdout)

### Debug Mode

For detailed debugging, enable verbose logging:

```bash
# Add to your CI environment
export MIGRATION_GUARD_LOG_LEVEL=debug
bundle exec rails db:migration:ci
```

## Best Practices

1. **Use appropriate strictness**: Start with `warning` and move to `strict` as your team adapts
2. **Run early in pipeline**: Catch issues before expensive test suites
3. **Cache dependencies**: Bundle and gem caching significantly speeds up CI
4. **Monitor trends**: Track migration issues over time to identify patterns
5. **Team education**: Ensure developers understand the migration workflow

## Next Steps

- [GitHub Actions Integration](github-actions.html) - Ready-to-use GitHub Actions workflow
- [Team Collaboration](team-collaboration.md) - Setting up shared configurations
- [Troubleshooting Guide](troubleshooting.md) - Common issues and solutions