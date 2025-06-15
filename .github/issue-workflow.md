# GitHub Issues Workflow - Quick Reference

## For Contributors

### Finding Work
```bash
# List all open issues labeled as ready
gh issue list --label "ready"

# Find good first issues
gh issue list --label "good-first-issue"

# Find high priority issues
gh issue list --label "P1-high"
```

### Claiming an Issue
```bash
# Comment on an issue to claim it
gh issue comment 123 --body "I'd like to work on this!"

# Self-assign if you have permissions
gh issue edit 123 --add-assignee @me
```

### Working on Issues
```bash
# Create a branch for your issue
git checkout -b feature/123-add-colorized-output

# When ready, create a PR that references the issue
gh pr create --title "[Issue #123] Add colorized output" \
  --body "Closes #123"
```

## For Maintainers

### Triaging Issues
```bash
# Add labels to an issue
gh issue edit 123 --add-label "P2-medium,ready"

# Assign to a milestone
gh issue edit 123 --milestone "v0.2.0"

# Move to a project column (requires project ID)
gh project item-add PROJECT_ID --owner tommy2118 --issue 123
```

### Quick Status Check
```bash
# Count open issues by label
gh issue list --label "bug" --json number --jq '. | length'

# List issues in current milestone
gh issue list --milestone "v0.2.0"

# Find stale issues (no activity in 30 days)
gh issue list --search "updated:<$(date -d '30 days ago' '+%Y-%m-%d')"
```

### Bulk Operations
```bash
# Close multiple issues
gh issue close 123 124 125 --comment "Fixed in v0.2.0"

# Add label to all bugs
gh issue list --label "bug" --json number \
  --jq '.[].number' | xargs -I {} gh issue edit {} --add-label "needs-triage"
```

## Automation Scripts

### Daily Standup Report
```bash
#!/bin/bash
# standup.sh - Generate daily standup from GitHub issues

echo "=== Daily Standup $(date +%Y-%m-%d) ==="
echo ""
echo "In Progress:"
gh issue list --assignee @me --label "in-progress" --json number,title \
  --jq '.[] | "- #\(.number): \(.title)"'

echo ""
echo "Completed Recently:"
gh issue list --assignee @me --state closed \
  --search "closed:>$(date -d '1 day ago' '+%Y-%m-%d')" \
  --json number,title --jq '.[] | "- #\(.number): \(.title)"'

echo ""
echo "Blocked:"
gh issue list --assignee @me --label "blocked" --json number,title \
  --jq '.[] | "- #\(.number): \(.title)"'
```

### Weekly Report
```bash
#!/bin/bash
# weekly-report.sh - Generate weekly metrics

echo "=== Weekly Report ($(date -d '7 days ago' '+%Y-%m-%d') to $(date '+%Y-%m-%d')) ==="

echo "Issues Created:"
gh issue list --search "created:>$(date -d '7 days ago' '+%Y-%m-%d')" \
  --json number --jq '. | length'

echo "Issues Closed:"
gh issue list --state closed \
  --search "closed:>$(date -d '7 days ago' '+%Y-%m-%d')" \
  --json number --jq '. | length'

echo "PRs Merged:"
gh pr list --state merged \
  --search "merged:>$(date -d '7 days ago' '+%Y-%m-%d')" \
  --json number --jq '. | length'
```

## GitHub CLI Aliases

Add these to your shell config:

```bash
# ~/.bashrc or ~/.zshrc

# Quick issue creation
alias ghi-bug='gh issue create --template bug_report.md'
alias ghi-feat='gh issue create --template feature_request.md'
alias ghi-docs='gh issue create --template documentation.md'

# Quick issue listing
alias ghi-mine='gh issue list --assignee @me'
alias ghi-ready='gh issue list --label ready'
alias ghi-urgent='gh issue list --label P0-critical,P1-high'

# Quick PR creation
alias ghpr='gh pr create --fill'
alias ghpr-draft='gh pr create --draft --fill'
```

## Project Board Management

### Moving Issues Between Columns
```bash
# Requires GitHub CLI extension for projects
gh extension install github/gh-projects

# Move issue to "In Progress"
gh project item-edit --id ITEM_ID --field-id STATUS_FIELD_ID --project-id PROJECT_ID --value "In Progress"
```

### Bulk Update Project Items
```bash
# Move all ready issues to "Ready" column
gh issue list --label "ready" --json number | \
  jq -r '.[].number' | \
  xargs -I {} gh project item-add PROJECT_ID --issue {}
```

## Integration with Git Hooks

Create `.git/hooks/prepare-commit-msg`:

```bash
#!/bin/bash
# Automatically add issue reference to commit message

BRANCH_NAME=$(git branch --show-current)
ISSUE_NUMBER=$(echo $BRANCH_NAME | grep -oE '[0-9]+' | head -n1)

if [ -n "$ISSUE_NUMBER" ]; then
  sed -i.bak "1s/^/[#$ISSUE_NUMBER] /" $1
fi
```

## VSCode Integration

Add to `.vscode/tasks.json`:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Create Bug Issue",
      "type": "shell",
      "command": "gh issue create --template bug_report.md",
      "problemMatcher": []
    },
    {
      "label": "List My Issues",
      "type": "shell",
      "command": "gh issue list --assignee @me",
      "problemMatcher": []
    },
    {
      "label": "Create PR for Current Branch",
      "type": "shell",
      "command": "gh pr create --fill",
      "problemMatcher": []
    }
  ]
}
```

## Useful Searches

```bash
# Find issues with no assignee
gh issue list --search "no:assignee"

# Find old PRs that need review
gh pr list --search "review:required created:<$(date -d '7 days ago' '+%Y-%m-%d')"

# Find issues with lots of comments (likely need attention)
gh issue list --search "comments:>10"

# Find recently updated high-priority issues
gh issue list --search "label:P1-high updated:>$(date -d '2 days ago' '+%Y-%m-%d')"
```

## Quick Links

- [All Open Issues](https://github.com/tommy2118/rails-migration-guard/issues)
- [Project Board](https://github.com/users/tommy2118/projects/1)
- [Milestones](https://github.com/tommy2118/rails-migration-guard/milestones)
- [Good First Issues](https://github.com/tommy2118/rails-migration-guard/labels/good-first-issue)