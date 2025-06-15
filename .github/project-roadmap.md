# Rails Migration Guard - Project Roadmap

This document outlines the project management structure using GitHub Issues, Milestones, and Projects.

## Milestones

### v0.1.0 - Initial Release (Completed) ✅
Core functionality for tracking and managing orphaned migrations.

### v0.2.0 - Enhanced Git Integration
- [ ] #1 Add support for multiple remote branches
- [ ] #2 Implement git hooks installer generator
- [ ] #3 Add branch switching warnings
- [ ] #4 Support for detecting migrations in unmerged PRs
- [ ] #5 Add git stash integration for safer rollbacks

### v0.3.0 - Developer Experience
- [ ] #6 Add interactive CLI with menu options
- [ ] #7 Implement migration conflict detection
- [ ] #8 Add migration diff viewer
- [ ] #9 Create VS Code extension for status bar integration
- [ ] #10 Add colorized output for better readability

### v0.4.0 - Team Collaboration
- [ ] #11 Add team notification integrations (Slack, Discord)
- [ ] #12 Implement migration ownership tracking
- [ ] #13 Add migration review workflow
- [ ] #14 Create web dashboard for team overview
- [ ] #15 Add export functionality for reports

### v0.5.0 - Advanced Features
- [ ] #16 Add machine learning for migration pattern detection
- [ ] #17 Implement auto-fix suggestions
- [ ] #18 Add migration performance tracking
- [ ] #19 Support for multi-database setups
- [ ] #20 Add migration dependency resolution

### v1.0.0 - Production Ready
- [ ] #21 Complete security audit
- [ ] #22 Performance optimization for large codebases
- [ ] #23 Add comprehensive integration test suite
- [ ] #24 Create migration guard best practices guide
- [ ] #25 Implement telemetry (opt-in)

## Issue Labels

### Type Labels
- `bug` - Something isn't working
- `enhancement` - New feature or request
- `documentation` - Improvements or additions to documentation
- `refactor` - Code improvement without changing functionality
- `test` - Adding or improving tests
- `performance` - Performance improvements
- `security` - Security-related issues

### Priority Labels
- `P0-critical` - Drop everything and fix
- `P1-high` - High priority
- `P2-medium` - Medium priority
- `P3-low` - Low priority

### Status Labels
- `needs-triage` - Needs review and prioritization
- `ready` - Ready to be worked on
- `in-progress` - Currently being worked on
- `blocked` - Blocked by another issue
- `needs-review` - PR ready for review
- `needs-testing` - Needs testing

### Other Labels
- `good-first-issue` - Good for newcomers
- `help-wanted` - Extra attention is needed
- `wontfix` - This will not be worked on
- `duplicate` - This issue or pull request already exists
- `question` - Further information is requested

## Initial Issues to Create

### High Priority Issues

```markdown
# Issue #1: Add support for multiple remote branches
**Labels:** enhancement, P1-high, ready
**Milestone:** v0.2.0

Currently, the gem only checks against a single main branch. Add support for checking against multiple remote branches (e.g., develop, staging, production).

**Acceptance Criteria:**
- [ ] Can configure multiple target branches
- [ ] Status report shows comparison against all configured branches
- [ ] Can specify which branch to compare against in CLI commands

**Technical Details:**
- Update `GitIntegration#main_branch` to support multiple branches
- Modify configuration to accept branch mapping
- Update reporter to show multi-branch comparison
```

```markdown
# Issue #2: Implement git hooks installer generator
**Labels:** enhancement, P1-high, ready, good-first-issue
**Milestone:** v0.2.0

Create a Rails generator that installs git hooks for automatic migration checking.

**Acceptance Criteria:**
- [ ] Generator creates post-checkout hook
- [ ] Generator creates pre-push hook (optional)
- [ ] Hooks are configurable
- [ ] Clear installation instructions

**Implementation:**
```bash
rails generate migration_guard:hooks
```
```

```markdown
# Issue #3: Add colorized output
**Labels:** enhancement, P2-medium, ready, good-first-issue
**Milestone:** v0.3.0

Add color to CLI output for better readability.

**Acceptance Criteria:**
- [ ] Success messages in green
- [ ] Warnings in yellow
- [ ] Errors in red
- [ ] Can disable colors via configuration
- [ ] Respects NO_COLOR environment variable

**Technical Details:**
- Use `colorize` gem or `Rainbow`
- Add configuration option `config.colorize_output = true`
```

### Bug Reports

```markdown
# Issue #4: Migration rollback fails with namespaced migrations
**Labels:** bug, P1-high, needs-triage
**Milestone:** v0.1.1

When trying to rollback migrations that are namespaced (e.g., `Reporting::CreateReports`), the rollback fails with an error.

**Steps to Reproduce:**
1. Create a namespaced migration
2. Run the migration
3. Try to rollback using `rails db:migration:rollback_orphaned`

**Expected:** Migration rolls back successfully
**Actual:** Error: "uninitialized constant CreateReports"

**Environment:**
- Rails 7.1.0
- Ruby 3.2.0
```

### Documentation Issues

```markdown
# Issue #5: Add troubleshooting guide
**Labels:** documentation, P2-medium, ready, good-first-issue
**Milestone:** v0.1.1

Create a comprehensive troubleshooting guide for common issues.

**Sections to include:**
- [ ] Git command not found errors
- [ ] Permission issues with migration files
- [ ] Database connection errors
- [ ] Migration version conflicts
- [ ] Performance issues with large migration histories
```

## GitHub Projects Board Structure

### Board: Rails Migration Guard Development

**Columns:**
1. **Backlog** - All new issues
2. **Ready** - Triaged and ready to work on
3. **In Progress** - Currently being worked on
4. **In Review** - PR submitted, needs review
5. **Testing** - Needs testing/verification
6. **Done** - Completed and merged

### Automation Rules
- New issues → Backlog
- Issues with `ready` label → Ready column
- Issues with `in-progress` label → In Progress column
- PRs created → In Review column
- PRs merged → Done column

## Issue Templates for Team

### Daily Standup Template
```markdown
**Date:** YYYY-MM-DD

**Yesterday:**
- Completed #XX: [Issue title]
- Progress on #YY: [Issue title]

**Today:**
- Working on #ZZ: [Issue title]
- Review PR #AA

**Blockers:**
- [Any blockers]
```

### Sprint Planning Template
```markdown
**Sprint:** X (Start: YYYY-MM-DD, End: YYYY-MM-DD)

**Goals:**
1. Complete v0.2.0 milestone
2. Fix critical bugs

**Issues:**
- [ ] #1 - Add support for multiple remote branches (5 pts)
- [ ] #2 - Implement git hooks installer (3 pts)
- [ ] #3 - Fix namespaced migration bug (2 pts)

**Total Points:** 10
```

## Contribution Guidelines Issue Template

```markdown
# Contributing to Rails Migration Guard

## How to Contribute

1. **Find an Issue**
   - Look for issues labeled `good-first-issue` or `help-wanted`
   - Comment on the issue to claim it

2. **Fork and Branch**
   ```bash
   git checkout -b feature/issue-number-description
   ```

3. **Make Changes**
   - Follow Ruby style guide
   - Add tests for new functionality
   - Update documentation

4. **Submit PR**
   - Reference the issue number
   - Include screenshots if UI changes
   - Ensure all tests pass

## Code Review Process
- All PRs need at least one approval
- CI must pass
- Documentation must be updated
```

## Metrics to Track

1. **Issue Velocity**
   - Issues created vs closed per week
   - Average time to close

2. **PR Metrics**
   - Time from PR creation to merge
   - Number of comments per PR

3. **Bug Metrics**
   - Bug discovery rate
   - Time to fix critical bugs

4. **Community Metrics**
   - Number of contributors
   - First-time contributor rate