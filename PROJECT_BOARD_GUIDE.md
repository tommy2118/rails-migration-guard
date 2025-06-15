# Rails Migration Guard - Project Board Setup Guide

## Overview
This guide provides instructions for setting up a GitHub Project Board for visual user story mapping and tracking the implementation of Rails Migration Guard features.

## Project Board Structure

### Board Name: "Rails Migration Guard - User Story Map"

### Columns Configuration

1. **Backlog** 
   - All new stories start here
   - Unsorted and unprioritized items
   - Color: Gray

2. **Ready for Development**
   - Prioritized and refined stories
   - Has acceptance criteria defined
   - Color: Blue

3. **In Progress**
   - Actively being worked on
   - Should have assignee
   - Color: Yellow

4. **In Review**
   - Code complete, in PR review
   - Links to PR
   - Color: Orange

5. **Done**
   - Merged and deployed
   - Color: Green

## Story Organization

### Epic Cards (Use Labels for Visual Hierarchy)
Create cards for each epic with the label "epic" and use these prefixes:

1. **[EPIC] Core Tracking Functionality**
2. **[EPIC] Developer Experience**
3. **[EPIC] Safety & Recovery**
4. **[EPIC] Team Collaboration**
5. **[EPIC] Advanced Features**

### User Story Cards
Each story should include:
- Title: "As a [role], I want [feature] so that [benefit]"
- Description with acceptance criteria
- Labels: feature type, priority, epic association
- Estimate (using GitHub's built-in fields or labels)

## Manual Setup Instructions

### Step 1: Create the Project Board

```bash
# If you have project scope:
gh project create --owner tommy2118 --title "Rails Migration Guard - User Story Map"

# Or create via GitHub UI:
# 1. Go to https://github.com/tommy2118/rails-migration-guard
# 2. Click "Projects" tab
# 3. Click "New project"
# 4. Select "Board" template
# 5. Name it "Rails Migration Guard - User Story Map"
```

### Step 2: Configure Columns

1. Delete default columns
2. Create new columns in this order:
   - Backlog
   - Ready for Development
   - In Progress
   - In Review
   - Done

### Step 3: Add Custom Fields

1. **Story Points** (Number field)
2. **Epic** (Single select with options: Core, DX, Safety, Collaboration, Advanced)
3. **Priority** (Single select: High, Medium, Low)
4. **Sprint** (Iteration field if using sprints)

### Step 4: Create Labels

```bash
# Create epic label
gh label create epic --description "Epic level story" --color "5319E7"

# Create priority labels
gh label create "priority: high" --description "High priority" --color "D93F0B"
gh label create "priority: medium" --description "Medium priority" --color "FBCA04" 
gh label create "priority: low" --description "Low priority" --color "0E8A16"

# Create type labels
gh label create "type: feature" --description "New feature" --color "0052CC"
gh label create "type: enhancement" --description "Enhancement" --color "1D76DB"
gh label create "type: bugfix" --description "Bug fix" --color "E4E669"
```

### Step 5: Add All Stories

## Complete Story List for Import

### Epic: Core Tracking Functionality

**[EPIC] Core Tracking Functionality**
- Description: Foundation for tracking migration execution across branches

**Stories:**

1. **Track Migration Execution**
   - As a developer, I want migrations to be automatically tracked when I run them so that the system knows which migrations were executed on my branch
   - Priority: High
   - Points: 3

2. **View Migration Status**
   - As a developer, I want to see which migrations have been run on my current branch so that I understand my database state
   - Priority: High
   - Points: 2

3. **Identify Orphaned Migrations**
   - As a developer, I want to see migrations that exist in my database but not in the main branch so that I can identify branch-specific migrations
   - Priority: High
   - Points: 3

4. **View Migration History**
   - As a developer, I want to see a history of migration executions with timestamps and branches so that I can debug migration-related issues
   - Priority: Medium
   - Points: 2

### Epic: Developer Experience

**[EPIC] Developer Experience**
- Description: Making the tool intuitive and pleasant to use

**Stories:**

1. **Clear Status Command**
   - As a developer, I want a simple command to check migration status so that I can quickly understand my database state
   - Priority: High
   - Points: 2

2. **Colored Output**
   - As a developer, I want color-coded output in the terminal so that I can quickly identify issues and status
   - Priority: Medium
   - Points: 1

3. **IDE Integration**
   - As a developer, I want my IDE to show migration warnings so that I'm aware of issues without running commands
   - Priority: Low
   - Points: 5

4. **Rails Console Helpers**
   - As a developer, I want helper methods in Rails console so that I can quickly check migration status while debugging
   - Priority: Medium
   - Points: 2

### Epic: Safety & Recovery

**[EPIC] Safety & Recovery**
- Description: Protecting developers from migration conflicts and providing recovery options

**Stories:**

1. **Branch Switch Warnings**
   - As a developer, I want to be warned when switching branches with different migrations so that I can prepare my database appropriately
   - Priority: High
   - Points: 3

2. **Automatic Rollback**
   - As a developer, I want orphaned migrations to be automatically rolled back when safe so that my database matches the code
   - Priority: High
   - Points: 5

3. **Migration Backup**
   - As a developer, I want migration files to be backed up before rollback so that I don't lose work
   - Priority: High
   - Points: 3

4. **Conflict Detection**
   - As a developer, I want to be warned about migration version conflicts before they cause problems so that I can resolve them early
   - Priority: Medium
   - Points: 3

### Epic: Team Collaboration

**[EPIC] Team Collaboration**
- Description: Features that help teams work together on database changes

**Stories:**

1. **Shared Migration Status**
   - As a team lead, I want to see migration status across all developer branches so that I can identify potential conflicts
   - Priority: Medium
   - Points: 5

2. **Migration Comments**
   - As a developer, I want to add notes to migrations so that my team understands their purpose and any special considerations
   - Priority: Low
   - Points: 2

3. **PR Integration**
   - As a reviewer, I want to see migration impact in pull requests so that I can properly review database changes
   - Priority: Medium
   - Points: 3

4. **Team Notifications**
   - As a team member, I want to be notified when migrations are added to main so that I can update my local database
   - Priority: Low
   - Points: 3

### Epic: Advanced Features

**[EPIC] Advanced Features**
- Description: Power features for complex scenarios

**Stories:**

1. **Multi-Database Support**
   - As a developer working with multiple databases, I want to track migrations per database so that each database state is managed correctly
   - Priority: Low
   - Points: 5

2. **Custom Strategies**
   - As a team lead, I want to configure custom migration strategies so that the tool fits our workflow
   - Priority: Low
   - Points: 3

3. **Migration Analytics**
   - As a team lead, I want to see analytics on migration patterns so that I can identify process improvements
   - Priority: Low
   - Points: 3

4. **Data Migration Tracking**
   - As a developer, I want to track data migrations separately so that I can manage schema and data changes independently
   - Priority: Low
   - Points: 5

## Using the Board for Story Mapping

### Visual Story Mapping Process

1. **Horizontal Axis (User Journey)**
   - Arrange epics left to right in order of user workflow
   - Core → DX → Safety → Collaboration → Advanced

2. **Vertical Axis (Priority)**
   - Within each epic column, arrange stories by priority
   - Higher priority stories at the top

3. **Release Planning**
   - Draw a horizontal line across the board to indicate release boundaries
   - Everything above the line is in the current release

### Best Practices

1. **Keep Stories Small**
   - If a story is more than 5 points, consider breaking it down
   - Each story should be completable in 1-3 days

2. **Regular Grooming**
   - Review backlog weekly
   - Move stories to "Ready" only when they have clear acceptance criteria

3. **WIP Limits**
   - Limit "In Progress" to 2-3 items per developer
   - Complete stories before starting new ones

4. **Link Everything**
   - Link stories to PRs
   - Link PRs to issues
   - Reference story numbers in commits

### Automation Ideas

```yaml
# .github/workflows/project-automation.yml
name: Project Board Automation

on:
  issues:
    types: [opened, closed]
  pull_request:
    types: [opened, review_requested, closed]

jobs:
  auto-move:
    runs-on: ubuntu-latest
    steps:
      - uses: alex-page/github-project-automation-plus@v0.8.1
        with:
          project: Rails Migration Guard - User Story Map
          column: Backlog
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Success Metrics

Track these metrics to measure progress:

1. **Velocity**: Average story points completed per week
2. **Cycle Time**: Average time from "In Progress" to "Done"
3. **WIP**: Average number of items in progress
4. **Blocked Time**: How long items stay in review

## Getting Started Checklist

- [ ] Create project board
- [ ] Set up columns
- [ ] Create labels
- [ ] Add custom fields
- [ ] Import all epics
- [ ] Import all user stories
- [ ] Organize by priority
- [ ] Set up automation
- [ ] Share with team
- [ ] Schedule first grooming session