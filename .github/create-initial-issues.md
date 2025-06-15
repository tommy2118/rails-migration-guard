# Creating Initial GitHub Issues

Use the GitHub CLI (`gh`) to create these initial issues. First, make sure you're in the repository directory and have `gh` installed and authenticated.

## Create Milestones

```bash
# Create milestones
gh api repos/:owner/:repo/milestones \
  --method POST \
  --field title="v0.2.0 - Enhanced Git Integration" \
  --field description="Improve git integration with support for multiple branches and hooks" \
  --field due_on="2024-03-01T00:00:00Z"

gh api repos/:owner/:repo/milestones \
  --method POST \
  --field title="v0.3.0 - Developer Experience" \
  --field description="Enhance CLI interface and developer workflow" \
  --field due_on="2024-04-01T00:00:00Z"

gh api repos/:owner/:repo/milestones \
  --method POST \
  --field title="v0.4.0 - Team Collaboration" \
  --field description="Add features for team collaboration and reporting" \
  --field due_on="2024-05-01T00:00:00Z"
```

## Create Labels

```bash
# Priority labels
gh label create "P0-critical" --description "Drop everything and fix" --color "FF0000"
gh label create "P1-high" --description "High priority" --color "FF6B6B"
gh label create "P2-medium" --description "Medium priority" --color "FFD93D"
gh label create "P3-low" --description "Low priority" --color "6BCB77"

# Status labels
gh label create "needs-triage" --description "Needs review and prioritization" --color "FFFFFF"
gh label create "ready" --description "Ready to be worked on" --color "0E8A16"
gh label create "in-progress" --description "Currently being worked on" --color "F9D71C"
gh label create "blocked" --description "Blocked by another issue" --color "B60205"
gh label create "needs-review" --description "PR ready for review" --color "5319E7"
gh label create "needs-testing" --description "Needs testing" --color "BFD4F2"

# Type labels (some may already exist)
gh label create "refactor" --description "Code improvement without changing functionality" --color "1D76DB"
gh label create "test" --description "Adding or improving tests" --color "0E8A16"
gh label create "performance" --description "Performance improvements" --color "F9D71C"
gh label create "security" --description "Security-related issues" --color "B60205"
```

## Create Initial Issues

```bash
# Issue 1: Multiple remote branches support
gh issue create \
  --title "[FEATURE] Add support for multiple remote branches" \
  --body "Currently, the gem only checks against a single main branch. Add support for checking against multiple remote branches (e.g., develop, staging, production).

## Acceptance Criteria
- [ ] Can configure multiple target branches
- [ ] Status report shows comparison against all configured branches  
- [ ] Can specify which branch to compare against in CLI commands

## Technical Details
- Update \`GitIntegration#main_branch\` to support multiple branches
- Modify configuration to accept branch mapping
- Update reporter to show multi-branch comparison" \
  --label "enhancement,P1-high,ready" \
  --milestone "v0.2.0"

# Issue 2: Git hooks installer
gh issue create \
  --title "[FEATURE] Implement git hooks installer generator" \
  --body "Create a Rails generator that installs git hooks for automatic migration checking.

## Acceptance Criteria
- [ ] Generator creates post-checkout hook
- [ ] Generator creates pre-push hook (optional)
- [ ] Hooks are configurable
- [ ] Clear installation instructions

## Implementation
\`\`\`bash
rails generate migration_guard:hooks
\`\`\`" \
  --label "enhancement,P1-high,ready,good-first-issue" \
  --milestone "v0.2.0"

# Issue 3: Colorized output
gh issue create \
  --title "[FEATURE] Add colorized output for better readability" \
  --body "Add color to CLI output for better readability.

## Acceptance Criteria
- [ ] Success messages in green
- [ ] Warnings in yellow
- [ ] Errors in red
- [ ] Can disable colors via configuration
- [ ] Respects NO_COLOR environment variable

## Technical Details
- Use \`colorize\` gem or \`Rainbow\`
- Add configuration option \`config.colorize_output = true\`" \
  --label "enhancement,P2-medium,ready,good-first-issue" \
  --milestone "v0.3.0"

# Issue 4: Slack integration
gh issue create \
  --title "[FEATURE] Add Slack notification integration" \
  --body "Send notifications to Slack when orphaned migrations are detected.

## Acceptance Criteria
- [ ] Can configure Slack webhook URL
- [ ] Sends notification on orphaned migration detection
- [ ] Configurable notification triggers
- [ ] Include migration details in notification

## Configuration Example
\`\`\`ruby
config.notifications = {
  slack: {
    webhook_url: ENV['SLACK_WEBHOOK_URL'],
    enabled: true,
    triggers: [:orphaned, :missing]
  }
}
\`\`\`" \
  --label "enhancement,P2-medium,ready" \
  --milestone "v0.4.0"

# Issue 5: Migration performance tracking
gh issue create \
  --title "[FEATURE] Track migration execution time" \
  --body "Add ability to track how long migrations take to run.

## Acceptance Criteria
- [ ] Record start and end time for each migration
- [ ] Show execution time in status report
- [ ] Warn about slow migrations
- [ ] Historical performance tracking

## Technical Details
- Add \`execution_time\` column to migration_guard_records
- Hook into migration execution callbacks
- Add performance report command" \
  --label "enhancement,P3-low,ready" \
  --milestone "v0.5.0"
```

## Create Bug Reports

```bash
# Known issue with namespaced migrations
gh issue create \
  --title "[BUG] Migration rollback fails with namespaced migrations" \
  --body "When trying to rollback migrations that are namespaced (e.g., \`Reporting::CreateReports\`), the rollback fails with an error.

## Steps to Reproduce
1. Create a namespaced migration
2. Run the migration  
3. Try to rollback using \`rails db:migration:rollback_orphaned\`

## Expected
Migration rolls back successfully

## Actual
Error: \"uninitialized constant CreateReports\"

## Environment
- Rails 7.1.0
- Ruby 3.2.0
- rails-migration-guard 0.1.0" \
  --label "bug,P1-high,needs-triage"
```

## Create Documentation Issues

```bash
# Troubleshooting guide
gh issue create \
  --title "[DOCS] Add comprehensive troubleshooting guide" \
  --body "Create a troubleshooting guide for common issues.

## Sections to include
- [ ] Git command not found errors
- [ ] Permission issues with migration files
- [ ] Database connection errors
- [ ] Migration version conflicts
- [ ] Performance issues with large migration histories
- [ ] Rails version compatibility issues" \
  --label "documentation,P2-medium,ready,good-first-issue"

# Video tutorials
gh issue create \
  --title "[DOCS] Create video tutorials" \
  --body "Create video tutorials for common workflows.

## Videos to create
- [ ] Installation and setup (5 min)
- [ ] Basic usage workflow (10 min)
- [ ] Team collaboration features (10 min)
- [ ] CI/CD integration (15 min)
- [ ] Troubleshooting common issues (10 min)" \
  --label "documentation,P3-low,help-wanted"
```

## Create Project Board

```bash
# Create a project (if using GitHub Projects v2)
gh project create --title "Rails Migration Guard Development" \
  --body "Development tracking for Rails Migration Guard gem"

# Note: Column creation and automation need to be done via GitHub UI
```

## Create Issue Templates via CLI

```bash
# Create the issue template directory and files as shown above
mkdir -p .github/ISSUE_TEMPLATE

# Then commit and push
git add .github/
git commit -m "Add GitHub issue templates and project management structure"
git push origin main
```

## Quick Issue Creation Script

Create a file `create_issue.sh`:

```bash
#!/bin/bash

echo "Rails Migration Guard - Quick Issue Creator"
echo "=========================================="

PS3="Select issue type: "
options=("Bug" "Feature" "Documentation" "Question" "Quit")

select opt in "${options[@]}"
do
    case $opt in
        "Bug")
            gh issue create --template bug_report.md
            break
            ;;
        "Feature")
            gh issue create --template feature_request.md
            break
            ;;
        "Documentation")
            gh issue create --template documentation.md
            break
            ;;
        "Question")
            gh issue create --title "[QUESTION] " --label "question"
            break
            ;;
        "Quit")
            break
            ;;
        *) echo "Invalid option";;
    esac
done
```

Make it executable: `chmod +x create_issue.sh`