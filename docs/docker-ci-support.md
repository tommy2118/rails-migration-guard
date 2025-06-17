# Docker and CI/CD Support

Rails Migration Guard now provides full support for Docker containers and CI/CD environments through automatic TTY detection and environment variable overrides.

> **Related Documentation:**
> - [CI Integration Guide](ci-integration.html) - Detailed CI/CD setup
> - [Troubleshooting Guide](troubleshooting.md) - Common issues and solutions
> - [Configuration Reference](configuration.md) - All configuration options

## Automatic TTY Detection

When running in environments without TTY support (like Docker containers or CI systems), Rails Migration Guard automatically switches to non-interactive mode:

```bash
# In Docker container
docker exec -it myapp rails db:migration:rollback_orphaned
# Automatically runs in non-interactive mode
```

## Environment Variable Overrides

### Force Non-Interactive Mode

Use these environment variables to force non-interactive behavior:

```bash
# Using FORCE flag
FORCE=true rails db:migration:rollback_orphaned

# Using NON_INTERACTIVE flag
NON_INTERACTIVE=true rails db:migration:recover

# For recovery with AUTO flag
AUTO=true rails db:migration:recover
```

### CI/CD Examples

#### GitHub Actions
```yaml
- name: Rollback orphaned migrations
  run: FORCE=true bundle exec rails db:migration:rollback_orphaned
```

#### GitLab CI
```yaml
rollback:
  script:
    - NON_INTERACTIVE=true bundle exec rails db:migration:recover
```

#### Docker Compose
```yaml
services:
  app:
    environment:
      - MIGRATION_GUARD_AUTO_APPROVE=1
      - NON_INTERACTIVE=true
```

## Command Reference

### Rollback Commands

```bash
# Interactive (default in TTY)
rails db:migration:rollback_orphaned

# Non-interactive (automatic in Docker/CI or with flags)
FORCE=true rails db:migration:rollback_orphaned
NON_INTERACTIVE=true rails db:migration:rollback_orphaned

# Rollback all without prompts
rails db:migration:rollback_all_orphaned
```

### Recovery Commands

```bash
# Interactive recovery (default in TTY)
rails db:migration:recover

# Automatic recovery (first option for each issue)
AUTO=true rails db:migration:recover
FORCE=true rails db:migration:recover
NON_INTERACTIVE=true rails db:migration:recover
```

### Cleanup Commands

```bash
# With confirmation (default)
rails db:migration:cleanup

# Without confirmation
FORCE=true rails db:migration:cleanup
```

## Docker-Specific Usage

### Dockerfile Example
```dockerfile
# Run migration checks in build
RUN FORCE=true bundle exec rails db:migration:rollback_orphaned
```

### Docker Entrypoint Script
```bash
#!/bin/bash
# entrypoint.sh

# Auto-cleanup old records
FORCE=true bundle exec rails db:migration:cleanup

# Check for issues in non-interactive mode
NON_INTERACTIVE=true bundle exec rails db:migration:recover
```

### Docker Compose Exec
```bash
# Run commands in existing container
docker-compose exec -T app rails db:migration:rollback_orphaned
# The -T flag disables TTY allocation, triggering auto non-interactive mode
```

## CI/CD Pipeline Integration

### Pre-deployment Checks
```bash
#!/bin/bash
# ci-check.sh

set -e

# Check for orphaned migrations
bundle exec rails db:migration:ci

# Auto-rollback if needed
if [ $? -ne 0 ]; then
  FORCE=true bundle exec rails db:migration:rollback_orphaned
fi
```

### Automated Recovery
```bash
# Auto-fix migration issues
AUTO=true bundle exec rails db:migration:recover

# Verify fix
bundle exec rails db:migration:doctor
```

## Behavior Differences

### Interactive Mode (TTY available)
- Prompts for confirmation
- Shows options for recovery
- Waits for user input
- Displays colored output (when enabled)

### Non-Interactive Mode (No TTY or forced)
- Skips all prompts
- Proceeds with default actions
- Uses first recovery option
- Suitable for automation
- Color output depends on NO_COLOR environment variable

## Terminal Colors in Docker

Rails Migration Guard respects terminal color settings:

### Enabling Colors in Docker
```bash
# Colors enabled by default if TTY is allocated
docker run -it myapp rails db:migration:status

# Force colors in non-TTY environments
docker exec -T -e FORCE_COLOR=1 myapp rails db:migration:status
```

### Disabling Colors
```bash
# Disable colors globally
NO_COLOR=1 rails db:migration:status

# Or via configuration
# config/initializers/migration_guard.rb
MigrationGuard.configure do |config|
  config.colorize_output = false
end
```

### CI/CD Color Support
Most CI systems support ANSI colors:
- **GitHub Actions**: Colors enabled by default
- **GitLab CI**: Set `FORCE_COLOR=1` for color output
- **CircleCI**: Colors enabled by default
- **Jenkins**: May require ANSI Color plugin

## Best Practices

1. **Always test in non-interactive mode** before deploying to CI/CD
2. **Use FORCE sparingly** - it bypasses safety checks
3. **Prefer AUTO over FORCE** for recovery operations
4. **Log output** in CI/CD for debugging:
   ```bash
   FORCE=true rails db:migration:rollback_orphaned 2>&1 | tee migration.log
   ```

## Troubleshooting

### "undefined method 'chomp' for nil"
This error occurs when the gem tries to read input in a non-TTY environment. Update to the latest version which includes automatic TTY detection.

### Commands produce no output
Some commands now show messages when no data is found:
- `rails db:migration:history` - "No migration history found matching the specified criteria."
- `rails db:migration:authors` - "No migration author data found."

### Docker exec hangs
Use the `-T` flag to disable TTY allocation:
```bash
docker exec -T myapp rails db:migration:rollback_orphaned
```