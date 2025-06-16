# GitHub Actions Integration Test Plan

This document outlines how to test the GitHub Actions integration for Rails Migration Guard.

## Test Scenarios

### 1. Basic Workflow Test

**Scenario**: PR with no migration issues
- **Expected**: Check passes, no PR comment
- **Exit Code**: 0

### 2. Orphaned Migration Detection

**Scenario**: PR with orphaned migrations
- **Expected**: 
  - Check fails with warning (exit code 1)
  - PR comment posted with details
  - Job summary shows orphaned migrations
- **Verification**:
  ```bash
  # Create orphaned migration
  rails generate migration AddTestField
  rails db:migrate
  rm db/migrate/*add_test_field.rb
  git add -A
  git commit -m "Remove migration file"
  ```

### 3. Missing Migration Detection

**Scenario**: PR missing migrations from main branch
- **Expected**:
  - Check fails with warning (exit code 1)
  - PR comment posted with missing migrations
- **Verification**:
  ```bash
  # On main branch
  rails generate migration AddMainField
  git add -A
  git commit -m "Add migration"
  git push origin main
  
  # On feature branch (without pulling)
  # Run CI check - should detect missing migration
  ```

### 4. Strict Mode

**Scenario**: Run with STRICT=true
- **Expected**: 
  - Any issues cause exit code 2
  - Workflow fails immediately
- **Test**: Set `strict: true` in action inputs

### 5. JSON Output Format

**Scenario**: Use JSON format
- **Expected**: 
  - Valid JSON output
  - Proper parsing in PR comment script
- **Verification**:
  ```bash
  bundle exec rails db:migration:ci FORMAT=json | jq .
  ```

### 6. Matrix Build Compatibility

**Scenario**: Multiple Ruby/Rails versions
- **Expected**: 
  - Check runs on all matrix combinations
  - Appropriate handling of version differences

### 7. PR Comment Updates

**Scenario**: Fix issues and re-run
- **Expected**: 
  - Existing comment updated (not duplicated)
  - Success status when issues resolved

### 8. Monorepo Support

**Scenario**: Multiple Rails apps
- **Expected**: 
  - Each app checked independently
  - Correct working directory used

## Manual Testing Steps

### Setup Test Repository

1. Fork the rails-migration-guard repository
2. Enable GitHub Actions in the fork
3. Create a test Rails app with the gem installed

### Test Workflow

1. **Create test branch**:
   ```bash
   git checkout -b test/github-actions
   ```

2. **Add workflow file**:
   ```bash
   cp .github/workflows/migration_guard.yml .github/workflows/
   git add .github/workflows/migration_guard.yml
   git commit -m "Add migration check workflow"
   git push origin test/github-actions
   ```

3. **Create PR and verify**:
   - Check runs automatically
   - Status check appears on PR
   - Job summary is generated

### Test Composite Action

1. **Use in workflow**:
   ```yaml
   - uses: ./.github/actions/migration-guard
     with:
       strict: false
       comment-on-pr: true
   ```

2. **Verify outputs**:
   ```yaml
   - name: Check results
     run: |
       echo "Status: ${{ steps.check.outputs.status }}"
       echo "Orphaned: ${{ steps.check.outputs.orphaned-count }}"
       echo "Missing: ${{ steps.check.outputs.missing-count }}"
   ```

## Automated Testing

### Action Test Workflow

Create `.github/workflows/test-action.yml`:

```yaml
name: Test Migration Guard Action

on:
  push:
    paths:
      - '.github/actions/migration-guard/**'
      - '.github/workflows/test-action.yml'

jobs:
  test-success:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      
      - name: Setup clean database
        run: |
          bundle exec rails db:create
          bundle exec rails db:schema:load
        env:
          RAILS_ENV: test
      
      - name: Test success case
        id: check-success
        uses: ./.github/actions/migration-guard
        with:
          strict: false
      
      - name: Verify success
        run: |
          if [ "${{ steps.check-success.outputs.status }}" != "success" ]; then
            echo "Expected success status"
            exit 1
          fi
          if [ "${{ steps.check-success.outputs.exit-code }}" != "0" ]; then
            echo "Expected exit code 0"
            exit 1
          fi

  test-orphaned:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      
      - name: Create orphaned migration
        run: |
          bundle exec rails generate migration TestOrphaned
          bundle exec rails db:migrate
          rm db/migrate/*test_orphaned.rb
        env:
          RAILS_ENV: test
      
      - name: Test orphaned detection
        id: check-orphaned
        uses: ./.github/actions/migration-guard
        with:
          strict: false
        continue-on-error: true
      
      - name: Verify detection
        run: |
          if [ "${{ steps.check-orphaned.outputs.status }}" != "warning" ]; then
            echo "Expected warning status"
            exit 1
          fi
          if [ "${{ steps.check-orphaned.outputs.orphaned-count }}" -lt "1" ]; then
            echo "Expected at least 1 orphaned migration"
            exit 1
          fi
```

## Debugging

### Enable Debug Output

```yaml
- uses: ./.github/actions/migration-guard
  env:
    ACTIONS_STEP_DEBUG: true
    ACTIONS_RUNNER_DEBUG: true
```

### Check Raw Output

```yaml
- name: Debug output
  if: always()
  run: |
    echo "=== Raw output ==="
    cat migration_guard_results.json || true
    echo "=== Environment ==="
    env | grep -E "(RAILS|DATABASE|GITHUB)" | sort
```

### Common Issues

1. **No PR comment appearing**:
   - Check permissions: `pull-requests: write`
   - Verify `GITHUB_TOKEN` is available
   - Check if bot comments are allowed

2. **Database connection errors**:
   - Ensure service is healthy before running
   - Check DATABASE_URL format
   - Verify Rails environment

3. **Git history issues**:
   - Always use `fetch-depth: 0`
   - Check branch comparison logic

## Performance Testing

Monitor workflow execution time:

```yaml
- name: Time migration check
  run: |
    start=$(date +%s)
    bundle exec rails db:migration:ci
    end=$(date +%s)
    echo "Check took $((end-start)) seconds"
```

Expected times:
- Small app: < 5 seconds
- Medium app: < 15 seconds
- Large app: < 30 seconds

## Security Testing

1. **Token permissions**:
   - Verify minimal permissions used
   - Test with restricted tokens

2. **Secret handling**:
   - Ensure DATABASE_URL not logged
   - Check for credential leaks in output

3. **PR comment injection**:
   - Test with malicious branch names
   - Verify proper escaping in comments