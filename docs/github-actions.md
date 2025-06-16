# GitHub Actions Integration

Rails Migration Guard provides seamless integration with GitHub Actions to automatically check for migration issues in your CI/CD pipeline.

## Quick Start

### Basic Setup

1. Add the workflow file to your repository:

```yaml
# .github/workflows/migration-check.yml
name: Migration Check

on:
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Required for branch comparison
      
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      
      - run: |
          bundle exec rails db:create
          bundle exec rails db:schema:load
        env:
          RAILS_ENV: test
      
      - uses: rails-migration-guard/migration-guard-action@v1
```

### Using the Built-in Action

For projects using Rails Migration Guard, you can use the built-in action:

```yaml
- name: Check migrations
  uses: ./.github/actions/migration-guard
  with:
    strict: false               # Only fail on errors, not warnings
    comment-on-pr: true        # Add comments to PRs
    format: json               # Use JSON output for parsing
```

## Configuration Options

### Action Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `working-directory` | Rails app directory | `.` | No |
| `rails-env` | Rails environment | `test` | No |
| `database-url` | Database connection URL | - | No |
| `strict` | Fail on warnings | `false` | No |
| `format` | Output format (`text`/`json`) | `json` | No |
| `comment-on-pr` | Comment on PR with results | `true` | No |
| `github-token` | GitHub token for PR comments | `github.token` | No |

### Action Outputs

| Output | Description |
|--------|-------------|
| `status` | Check result: `success`, `warning`, or `error` |
| `exit-code` | Exit code from the check (0, 1, or 2) |
| `orphaned-count` | Number of orphaned migrations found |
| `missing-count` | Number of missing migrations found |
| `results-file` | Path to the JSON results file |

## Advanced Configurations

### Database Services

#### PostgreSQL

```yaml
services:
  postgres:
    image: postgres:14
    env:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    options: >-
      --health-cmd pg_isready
      --health-interval 10s
      --health-timeout 5s
      --health-retries 5
    ports:
      - 5432:5432

# In your steps:
env:
  DATABASE_URL: postgresql://postgres:postgres@localhost:5432/test_db
```

#### MySQL

```yaml
services:
  mysql:
    image: mysql:8
    env:
      MYSQL_ROOT_PASSWORD: password
      MYSQL_DATABASE: test_db
    options: >-
      --health-cmd="mysqladmin ping"
      --health-interval=10s
      --health-timeout=5s
      --health-retries=3
    ports:
      - 3306:3306

# In your steps:
env:
  DATABASE_URL: mysql2://root:password@localhost:3306/test_db
```

### Conditional Checks

Only run on migration changes:

```yaml
on:
  pull_request:
    paths:
      - 'db/migrate/**'
      - 'db/schema.rb'
      - 'db/structure.sql'
```

### Matrix Builds

Test across multiple versions:

```yaml
strategy:
  matrix:
    ruby: ['3.1', '3.2', '3.3']
    rails: ['7.0', '7.1', '7.2']

steps:
  - uses: ruby/setup-ruby@v1
    with:
      ruby-version: ${{ matrix.ruby }}
  
  - uses: ./.github/actions/migration-guard
    with:
      strict: ${{ matrix.rails == '7.2' }}  # Strict for latest only
```

### Monorepo Support

For multiple Rails apps:

```yaml
- name: Check API migrations
  uses: ./.github/actions/migration-guard
  with:
    working-directory: apps/api
    database-url: ${{ secrets.API_DATABASE_URL }}

- name: Check Admin migrations
  uses: ./.github/actions/migration-guard
  with:
    working-directory: apps/admin
    database-url: ${{ secrets.ADMIN_DATABASE_URL }}
```

## PR Comments

The action automatically comments on PRs when issues are found:

![PR Comment Example](./images/pr-comment-example.png)

### Comment Format

```markdown
## ⚠️ Migration Guard Check

Found issues with migrations in this PR:

### Orphaned Migrations Detected
The following migrations exist in the database but not in the target branch:

- `20240115123456_add_user_profiles.rb` - Created on branch: feature/user-profiles

### Suggested Actions
1. **For orphaned migrations**: Roll them back or commit the migration files
2. **For missing migrations**: Pull latest changes and run `rails db:migrate`

---
_This comment will be updated when issues are resolved._
```

### Disabling Comments

```yaml
- uses: ./.github/actions/migration-guard
  with:
    comment-on-pr: false
```

## Scheduled Checks

Monitor for migration drift:

```yaml
on:
  schedule:
    - cron: '0 9 * * 1-5'  # 9 AM UTC weekdays

jobs:
  check-drift:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: main
      
      - uses: ./.github/actions/migration-guard
        with:
          rails-env: staging
          database-url: ${{ secrets.STAGING_DATABASE_URL }}
```

## Status Checks

### Branch Protection

1. Go to Settings → Branches
2. Add branch protection rule for `main`
3. Enable "Require status checks to pass"
4. Add "Migration Guard Check" to required checks

### Status Badge

Add to your README:

```markdown
![Migration Check](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/migration-check.yml/badge.svg)
```

## Integration with Other Tools

### Slack Notifications

```yaml
- name: Notify Slack on failure
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    payload: |
      {
        "text": "Migration check failed for PR #${{ github.event.pull_request.number }}",
        "blocks": [{
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": "Orphaned: ${{ steps.check.outputs.orphaned-count }}\nMissing: ${{ steps.check.outputs.missing-count }}"
          }
        }]
      }
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

### Jira Integration

```yaml
- name: Create Jira issue for critical drift
  if: steps.check.outputs.orphaned-count > 5
  uses: atlassian/gajira-create@master
  with:
    project: PROJ
    issuetype: Bug
    summary: "Critical migration drift detected"
    description: |
      Orphaned migrations: ${{ steps.check.outputs.orphaned-count }}
      Missing migrations: ${{ steps.check.outputs.missing-count }}
```

## Troubleshooting

### Common Issues

#### "fetch-depth: 0 is required"

The action needs full git history to compare branches:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0  # Don't use shallow clone
```

#### Database connection errors

Ensure your database service is healthy:

```yaml
- name: Wait for PostgreSQL
  run: |
    until pg_isready -h localhost -p 5432; do
      echo "Waiting for PostgreSQL..."
      sleep 1
    done
```

#### Permission denied for PR comments

The default `GITHUB_TOKEN` needs write permission:

```yaml
permissions:
  contents: read
  pull-requests: write
```

### Debug Mode

Enable debug output:

```yaml
- uses: ./.github/actions/migration-guard
  with:
    format: text  # More readable debug output
  env:
    ACTIONS_STEP_DEBUG: true
```

## Best Practices

1. **Start with warnings**: Use `strict: false` initially
2. **Gradual enforcement**: Move to strict mode once stable
3. **Monitor scheduled checks**: Catch drift early
4. **Cache dependencies**: Use `bundler-cache: true`
5. **Parallel jobs**: Run migration checks alongside tests
6. **Fail fast**: Use `continue-on-error: false` for critical apps

## Security Considerations

### Database Credentials

Always use secrets for database URLs:

```yaml
env:
  DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

Never commit credentials in workflow files.

### Token Permissions

Limit token permissions:

```yaml
permissions:
  contents: read        # Read code
  pull-requests: write  # Comment on PRs
  issues: write        # Create issues (if needed)
```

### Third-party Actions

Pin action versions:

```yaml
- uses: actions/checkout@8ade135a41bc03ea155e62e844d188df1ea18608  # v4.1.0
```

### Minimum Permissions

The following permissions are required for different features:

```yaml
permissions:
  contents: read        # Required: Read repository code
  pull-requests: write  # Required only if comment-on-pr is true
  issues: write        # Optional: Only if creating issues
  actions: read        # Optional: For workflow status checks
```

For read-only operations (no PR comments):

```yaml
permissions:
  contents: read
```

## Migration to GitHub Actions

From other CI systems:

### From CircleCI

```yaml
# CircleCI
- run:
    name: Check migrations
    command: bundle exec rails migration_guard:check

# GitHub Actions
- name: Check migrations
  run: bundle exec rails db:migration:ci
```

### From GitLab CI

```yaml
# GitLab CI
migration_check:
  script:
    - bundle exec rails migration_guard:check
  only:
    - merge_requests

# GitHub Actions
on:
  pull_request:
jobs:
  check:
    steps:
      - run: bundle exec rails db:migration:ci
```

## Examples

See the [examples directory](./.github/workflows/examples/) for:

- [Simple setup](../.github/workflows/examples/simple.yml)
- [Matrix builds](../.github/workflows/examples/matrix.yml)
- [Monorepo setup](../.github/workflows/examples/monorepo.yml)
- [Scheduled checks](../.github/workflows/examples/scheduled.yml)

## Support

- [Report issues](https://github.com/rails-migration-guard/rails-migration-guard/issues)
- [GitHub Actions documentation](https://docs.github.com/actions)
- [Rails Migration Guard documentation](./README.md)