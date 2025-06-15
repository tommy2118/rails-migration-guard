# CI/CD Integration Examples

This document provides examples of integrating Rails Migration Guard into your CI/CD pipeline.

## GitHub Actions

### Basic Check

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [ main ]

jobs:
  check-migrations:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      
      - name: Check for orphaned migrations
        run: bundle exec rails db:migration:check
        env:
          RAILS_ENV: staging
```

### With Deployment Gate

```yaml
# .github/workflows/staging-deploy.yml
name: Deploy to Staging

on:
  push:
    branches: [ staging ]

jobs:
  pre-deploy-checks:
    runs-on: ubuntu-latest
    outputs:
      migration-status: ${{ steps.check.outputs.status }}
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      
      - name: Setup database
        run: |
          bundle exec rails db:create
          bundle exec rails db:schema:load
        env:
          RAILS_ENV: test
      
      - id: check
        name: Check migration status
        run: |
          if bundle exec rails db:migration:check; then
            echo "status=clean" >> $GITHUB_OUTPUT
          else
            echo "status=orphaned" >> $GITHUB_OUTPUT
            exit 1
          fi
        env:
          RAILS_ENV: staging

  deploy:
    needs: pre-deploy-checks
    if: needs.pre-deploy-checks.outputs.migration-status == 'clean'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to staging
        run: echo "Deploying..."
```

## GitLab CI

```yaml
# .gitlab-ci.yml
stages:
  - test
  - deploy

check_migrations:
  stage: test
  script:
    - bundle exec rails db:migration:check
  environment:
    name: staging
  only:
    - staging
    - main

deploy_staging:
  stage: deploy
  script:
    - bundle exec cap staging deploy
  environment:
    name: staging
  dependencies:
    - check_migrations
  only:
    - staging
```

## CircleCI

```yaml
# .circleci/config.yml
version: 2.1

jobs:
  check-migrations:
    docker:
      - image: cimg/ruby:3.2
    steps:
      - checkout
      - restore_cache:
          keys:
            - gem-cache-v1-{{ checksum "Gemfile.lock" }}
      - run:
          name: Bundle Install
          command: bundle check || bundle install
      - save_cache:
          key: gem-cache-v1-{{ checksum "Gemfile.lock" }}
          paths:
            - vendor/bundle
      - run:
          name: Check for orphaned migrations
          command: bundle exec rails db:migration:check
          environment:
            RAILS_ENV: staging

workflows:
  version: 2
  test-and-deploy:
    jobs:
      - check-migrations
      - deploy:
          requires:
            - check-migrations
```

## Jenkins

```groovy
// Jenkinsfile
pipeline {
    agent any
    
    stages {
        stage('Setup') {
            steps {
                sh 'bundle install'
            }
        }
        
        stage('Check Migrations') {
            steps {
                script {
                    def migrationStatus = sh(
                        script: 'bundle exec rails db:migration:check',
                        returnStatus: true
                    )
                    
                    if (migrationStatus != 0) {
                        error("Orphaned migrations detected! Check the logs.")
                    }
                }
            }
        }
        
        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                sh 'bundle exec cap production deploy'
            }
        }
    }
}
```

## Configuration for CI/CD

Add this to your staging environment configuration:

```ruby
# config/environments/staging.rb
Rails.application.configure do
  # ... other configuration ...
  
  # Block deployment if orphaned migrations are detected
  config.migration_guard.block_deploy_with_orphans = true
end
```

Or configure via initializer:

```ruby
# config/initializers/migration_guard.rb
MigrationGuard.configure do |config|
  if ENV['CI'] || ENV['GITHUB_ACTIONS']
    # Stricter settings for CI/CD
    config.block_deploy_with_orphans = true
    config.git_integration_level = :warning
  end
end
```

## Slack Notifications

```yaml
# GitHub Actions example with Slack notification
- name: Check migrations and notify
  run: |
    if ! bundle exec rails db:migration:check; then
      curl -X POST -H 'Content-type: application/json' \
        --data '{"text":"⚠️ Orphaned migrations detected in staging deployment!"}' \
        ${{ secrets.SLACK_WEBHOOK_URL }}
      exit 1
    fi
```

## Docker Integration

```dockerfile
# Dockerfile
FROM ruby:3.2

# ... other setup ...

# Run migration check as part of build
RUN bundle exec rails db:migration:check || \
    echo "Warning: Orphaned migrations detected"
```

## Best Practices

1. **Run checks early**: Check for orphaned migrations before running tests
2. **Use different severity levels**: Warning for staging, error for production deploys
3. **Clean up regularly**: Add a scheduled job to clean old migration records
4. **Monitor trends**: Track how often orphaned migrations occur
5. **Educate the team**: Include migration status in PR templates