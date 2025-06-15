#!/usr/bin/env ruby
# Script to create GitHub issues for all user stories

require 'json'

# Epic definitions
EPICS = {
  core: {
    title: "[EPIC] Core Tracking Functionality",
    description: "Foundation for tracking migration execution across branches",
    stories: [
      {
        title: "Track Migration Execution",
        body: "As a developer, I want migrations to be automatically tracked when I run them so that the system knows which migrations were executed on my branch\n\n## Acceptance Criteria\n- [ ] Migrations are tracked when run via `rails db:migrate`\n- [ ] Branch information is captured\n- [ ] Timestamp is recorded\n- [ ] Works in development and staging environments",
        labels: ["type: feature", "priority: high"],
        estimate: 3
      },
      {
        title: "View Migration Status",
        body: "As a developer, I want to see which migrations have been run on my current branch so that I understand my database state\n\n## Acceptance Criteria\n- [ ] Command shows all migrations run on current branch\n- [ ] Shows migration version, name, and execution time\n- [ ] Indicates if migration is in main branch or branch-specific",
        labels: ["type: feature", "priority: high"],
        estimate: 2
      },
      {
        title: "Identify Orphaned Migrations",
        body: "As a developer, I want to see migrations that exist in my database but not in the main branch so that I can identify branch-specific migrations\n\n## Acceptance Criteria\n- [ ] Clearly identifies orphaned migrations\n- [ ] Shows which branch introduced the migration\n- [ ] Provides actionable information",
        labels: ["type: feature", "priority: high"],
        estimate: 3
      },
      {
        title: "View Migration History",
        body: "As a developer, I want to see a history of migration executions with timestamps and branches so that I can debug migration-related issues\n\n## Acceptance Criteria\n- [ ] Shows chronological history of migrations\n- [ ] Includes branch information for each execution\n- [ ] Filterable by date range or branch",
        labels: ["type: feature", "priority: medium"],
        estimate: 2
      }
    ]
  },
  dx: {
    title: "[EPIC] Developer Experience",
    description: "Making the tool intuitive and pleasant to use",
    stories: [
      {
        title: "Clear Status Command",
        body: "As a developer, I want a simple command to check migration status so that I can quickly understand my database state\n\n## Acceptance Criteria\n- [ ] Single command shows comprehensive status\n- [ ] Output is clear and well-formatted\n- [ ] Highlights issues requiring attention",
        labels: ["type: feature", "priority: high"],
        estimate: 2
      },
      {
        title: "Colored Output",
        body: "As a developer, I want color-coded output in the terminal so that I can quickly identify issues and status\n\n## Acceptance Criteria\n- [ ] Errors shown in red\n- [ ] Warnings in yellow\n- [ ] Success in green\n- [ ] Respects NO_COLOR environment variable",
        labels: ["type: enhancement", "priority: medium"],
        estimate: 1
      },
      {
        title: "IDE Integration",
        body: "As a developer, I want my IDE to show migration warnings so that I'm aware of issues without running commands\n\n## Acceptance Criteria\n- [ ] VS Code extension shows migration status\n- [ ] RubyMine plugin available\n- [ ] Shows warnings for orphaned migrations",
        labels: ["type: feature", "priority: low"],
        estimate: 5
      },
      {
        title: "Rails Console Helpers",
        body: "As a developer, I want helper methods in Rails console so that I can quickly check migration status while debugging\n\n## Acceptance Criteria\n- [ ] `MigrationGuard.status` shows current status\n- [ ] `MigrationGuard.orphaned` lists orphaned migrations\n- [ ] `MigrationGuard.rollback(version)` rolls back specific migration",
        labels: ["type: feature", "priority: medium"],
        estimate: 2
      }
    ]
  },
  safety: {
    title: "[EPIC] Safety & Recovery",
    description: "Protecting developers from migration conflicts and providing recovery options",
    stories: [
      {
        title: "Branch Switch Warnings",
        body: "As a developer, I want to be warned when switching branches with different migrations so that I can prepare my database appropriately\n\n## Acceptance Criteria\n- [ ] Git hook detects branch switches\n- [ ] Warns about migration differences\n- [ ] Suggests appropriate actions\n- [ ] Can be disabled via config",
        labels: ["type: feature", "priority: high"],
        estimate: 3
      },
      {
        title: "Automatic Rollback",
        body: "As a developer, I want orphaned migrations to be automatically rolled back when safe so that my database matches the code\n\n## Acceptance Criteria\n- [ ] Detects safe rollback scenarios\n- [ ] Confirms before rolling back\n- [ ] Creates backup before rollback\n- [ ] Reports rollback success/failure",
        labels: ["type: feature", "priority: high"],
        estimate: 5
      },
      {
        title: "Migration Backup",
        body: "As a developer, I want migration files to be backed up before rollback so that I don't lose work\n\n## Acceptance Criteria\n- [ ] Creates .backup directory\n- [ ] Preserves original migration files\n- [ ] Includes metadata about rollback\n- [ ] Easy restore process",
        labels: ["type: feature", "priority: high"],
        estimate: 3
      },
      {
        title: "Conflict Detection",
        body: "As a developer, I want to be warned about migration version conflicts before they cause problems so that I can resolve them early\n\n## Acceptance Criteria\n- [ ] Detects version conflicts across branches\n- [ ] Warns during migration creation\n- [ ] Suggests next safe version number\n- [ ] Integrates with Rails generators",
        labels: ["type: feature", "priority: medium"],
        estimate: 3
      }
    ]
  },
  collaboration: {
    title: "[EPIC] Team Collaboration",
    description: "Features that help teams work together on database changes",
    stories: [
      {
        title: "Shared Migration Status",
        body: "As a team lead, I want to see migration status across all developer branches so that I can identify potential conflicts\n\n## Acceptance Criteria\n- [ ] Central dashboard for team migration status\n- [ ] Shows migrations by developer/branch\n- [ ] Highlights conflicts\n- [ ] Optional Slack integration",
        labels: ["type: feature", "priority: medium"],
        estimate: 5
      },
      {
        title: "Migration Comments",
        body: "As a developer, I want to add notes to migrations so that my team understands their purpose and any special considerations\n\n## Acceptance Criteria\n- [ ] Add comments via CLI\n- [ ] Comments stored with migration tracking\n- [ ] Visible in status output\n- [ ] Searchable",
        labels: ["type: feature", "priority: low"],
        estimate: 2
      },
      {
        title: "PR Integration",
        body: "As a reviewer, I want to see migration impact in pull requests so that I can properly review database changes\n\n## Acceptance Criteria\n- [ ] GitHub Action posts migration summary\n- [ ] Shows migrations added/removed\n- [ ] Warns about conflicts with main\n- [ ] Suggests review checklist",
        labels: ["type: feature", "priority: medium"],
        estimate: 3
      },
      {
        title: "Team Notifications",
        body: "As a team member, I want to be notified when migrations are added to main so that I can update my local database\n\n## Acceptance Criteria\n- [ ] Configurable notifications\n- [ ] Slack/Discord webhooks\n- [ ] Email option\n- [ ] Includes migration details",
        labels: ["type: feature", "priority: low"],
        estimate: 3
      }
    ]
  },
  advanced: {
    title: "[EPIC] Advanced Features",
    description: "Power features for complex scenarios",
    stories: [
      {
        title: "Multi-Database Support",
        body: "As a developer working with multiple databases, I want to track migrations per database so that each database state is managed correctly\n\n## Acceptance Criteria\n- [ ] Tracks migrations per database\n- [ ] Separate status for each database\n- [ ] Handles database-specific rollbacks\n- [ ] Works with Rails 6+ multi-DB",
        labels: ["type: feature", "priority: low"],
        estimate: 5
      },
      {
        title: "Custom Strategies",
        body: "As a team lead, I want to configure custom migration strategies so that the tool fits our workflow\n\n## Acceptance Criteria\n- [ ] Configurable rollback strategies\n- [ ] Custom branch patterns\n- [ ] Hook system for extensions\n- [ ] Strategy templates",
        labels: ["type: feature", "priority: low"],
        estimate: 3
      },
      {
        title: "Migration Analytics",
        body: "As a team lead, I want to see analytics on migration patterns so that I can identify process improvements\n\n## Acceptance Criteria\n- [ ] Migration frequency reports\n- [ ] Rollback statistics\n- [ ] Conflict frequency\n- [ ] Developer migration patterns",
        labels: ["type: feature", "priority: low"],
        estimate: 3
      },
      {
        title: "Data Migration Tracking",
        body: "As a developer, I want to track data migrations separately so that I can manage schema and data changes independently\n\n## Acceptance Criteria\n- [ ] Separate tracking for data migrations\n- [ ] Different rollback rules\n- [ ] Data integrity checks\n- [ ] Progress tracking for long migrations",
        labels: ["type: feature", "priority: low"],
        estimate: 5
      }
    ]
  }
}

def create_epic_issue(epic_key, epic_data)
  puts "Creating epic: #{epic_data[:title]}"
  
  cmd = [
    "gh issue create",
    "--title \"#{epic_data[:title]}\"",
    "--label epic",
    "--body \"#{epic_data[:description]}\\n\\n## Stories\\n#{epic_data[:stories].map { |s| "- [ ] #{s[:title]}" }.join("\\n")}\""
  ].join(" ")
  
  result = `#{cmd}`
  if $?.success?
    issue_number = result.strip.split("/").last
    puts "  Created epic ##{issue_number}"
    issue_number
  else
    puts "  Failed to create epic: #{result}"
    nil
  end
end

def create_story_issue(story, epic_key, epic_number)
  puts "  Creating story: #{story[:title]}"
  
  labels = (story[:labels] + ["epic: #{epic_key}"]).join(",")
  body = story[:body] + "\n\n**Epic:** ##{epic_number}\n**Story Points:** #{story[:estimate]}"
  
  cmd = [
    "gh issue create",
    "--title \"#{story[:title]}\"",
    "--label \"#{labels}\"",
    "--body \"#{body}\""
  ].join(" ")
  
  result = `#{cmd}`
  if $?.success?
    issue_number = result.strip.split("/").last
    puts "    Created story ##{issue_number}"
  else
    puts "    Failed to create story: #{result}"
  end
end

# Create labels first
puts "Creating labels..."
labels_to_create = [
  { name: "epic", desc: "Epic level story", color: "5319E7" },
  { name: "priority: high", desc: "High priority", color: "D93F0B" },
  { name: "priority: medium", desc: "Medium priority", color: "FBCA04" },
  { name: "priority: low", desc: "Low priority", color: "0E8A16" },
  { name: "type: feature", desc: "New feature", color: "0052CC" },
  { name: "type: enhancement", desc: "Enhancement", color: "1D76DB" },
  { name: "type: bugfix", desc: "Bug fix", color: "E4E669" },
  { name: "epic: core", desc: "Core functionality epic", color: "7057ff" },
  { name: "epic: dx", desc: "Developer experience epic", color: "008672" },
  { name: "epic: safety", desc: "Safety & recovery epic", color: "e99695" },
  { name: "epic: collaboration", desc: "Team collaboration epic", color: "fef2c0" },
  { name: "epic: advanced", desc: "Advanced features epic", color: "bfd4f2" }
]

labels_to_create.each do |label|
  cmd = "gh label create \"#{label[:name]}\" --description \"#{label[:desc]}\" --color \"#{label[:color]}\" --force"
  puts "Creating label: #{label[:name]}"
  `#{cmd}`
end

puts "\nCreating issues..."
puts "Note: This will create #{EPICS.count} epics and #{EPICS.values.sum { |e| e[:stories].count }} stories"
print "Continue? (y/n): "
exit unless gets.chomp.downcase == 'y'

# Create epics and their stories
EPICS.each do |epic_key, epic_data|
  epic_number = create_epic_issue(epic_key, epic_data)
  
  if epic_number
    epic_data[:stories].each do |story|
      create_story_issue(story, epic_key, epic_number)
    end
  end
  
  puts "" # Empty line between epics
end

puts "\nDone! Check your GitHub issues at: https://github.com/tommy2118/rails-migration-guard/issues"
puts "\nNext steps:"
puts "1. Create the project board manually at: https://github.com/tommy2118/rails-migration-guard/projects"
puts "2. Add all created issues to the board"
puts "3. Organize by epic and priority"
puts "4. Start development!"