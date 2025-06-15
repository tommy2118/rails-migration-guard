# Contributing to Rails Migration Guard

First off, thank you for considering contributing to Rails Migration Guard! It's people like you that make Rails Migration Guard such a great tool.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Process](#development-process)
- [Style Guides](#style-guides)
- [Project Management](#project-management)

## Code of Conduct

This project and everyone participating in it is governed by our Code of Conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to [project email].

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally
   ```bash
   git clone https://github.com/tommy2118/rails-migration-guard.git
   cd rails-migration-guard
   ```
3. **Set up development environment**
   ```bash
   bundle install
   bundle exec rspec  # Run tests to ensure setup is correct
   ```

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues as you might find out that you don't need to create one. When you are creating a bug report, please use the bug report template and include as many details as possible.

**To report a bug:**
1. Go to [Issues](https://github.com/tommy2118/rails-migration-guard/issues)
2. Click "New Issue"
3. Select "Bug report" template
4. Fill in all the required information

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. Use the feature request template when creating an enhancement suggestion.

**To suggest an enhancement:**
1. Go to [Issues](https://github.com/tommy2118/rails-migration-guard/issues)
2. Click "New Issue"
3. Select "Feature request" template
4. Provide a clear description of the feature

### Finding Issues to Work On

Looking for issues to work on? Check out these labels:

- [`good-first-issue`](https://github.com/tommy2118/rails-migration-guard/labels/good-first-issue) - Good for newcomers
- [`help-wanted`](https://github.com/tommy2118/rails-migration-guard/labels/help-wanted) - Issues that need extra attention
- [`ready`](https://github.com/tommy2118/rails-migration-guard/labels/ready) - Issues that are ready to be worked on

### Working on Issues

1. **Find an issue** you want to work on
2. **Comment on the issue** to let others know you're working on it
3. **Create a branch** for your work:
   ```bash
   git checkout -b feature/issue-123-add-amazing-feature
   ```
4. **Make your changes** following our style guides
5. **Write/update tests** for your changes
6. **Run the test suite** to ensure nothing is broken:
   ```bash
   bundle exec rspec
   bundle exec rubocop
   ```
7. **Commit your changes** using descriptive commit messages
8. **Push to your fork** and submit a pull request

## Development Process

### 1. Issue Creation and Assignment

- All work should be tracked via GitHub Issues
- Check if an issue already exists before creating a new one
- Use appropriate issue templates
- Wait for issue to be triaged and labeled before starting work

### 2. Branch Naming

Use descriptive branch names following this pattern:
- `feature/issue-number-brief-description` for features
- `fix/issue-number-brief-description` for bug fixes
- `docs/issue-number-brief-description` for documentation

Examples:
- `feature/42-add-slack-integration`
- `fix/13-namespaced-migration-rollback`
- `docs/7-troubleshooting-guide`

### 3. Commit Messages

Follow these commit message guidelines:

```
type(scope): subject

body

footer
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Example:**
```
feat(reporter): add colorized output support

- Add Rainbow gem for cross-platform color support
- Make colors configurable via config.colorize_output
- Respect NO_COLOR environment variable
- Add specs for color output

Closes #3
```

### 4. Pull Request Process

1. **Update documentation** for any changed functionality
2. **Add tests** for new functionality
3. **Ensure all tests pass** locally
4. **Update CHANGELOG.md** with your changes under "Unreleased"
5. **Reference the issue** in your PR description using "Closes #issue-number"
6. **Request review** from maintainers

**PR Title Format:**
```
[Issue #123] Brief description of changes
```

### 5. Code Review

- All PRs require at least one approval
- Address all feedback comments
- Keep PRs focused on a single issue
- Be open to suggestions and feedback

## Style Guides

### Ruby Style Guide

We follow the [Ruby Style Guide](https://rubystyle.guide/) with these specifications:

- Use 2 spaces for indentation
- Use double quotes for strings
- Add frozen string literal comment to all Ruby files
- Keep methods under 15 lines
- Keep classes under 150 lines

Run RuboCop to check your code:
```bash
bundle exec rubocop
```

### RSpec Style Guide

- Use `describe` for methods and `context` for conditions
- Use `let` and `let!` instead of instance variables
- Include both positive and negative test cases
- Aim for >90% test coverage

Example:
```ruby
RSpec.describe MigrationGuard::Reporter do
  let(:reporter) { described_class.new }
  
  describe "#orphaned_migrations" do
    context "when migrations exist only locally" do
      it "identifies migrations not in trunk" do
        # test implementation
      end
    end
  end
end
```

### Documentation Style Guide

- Use YARD documentation for all public methods
- Include usage examples in documentation
- Keep README concise but comprehensive
- Update documentation in the same PR as code changes

## Project Management

### Issue Labels

Familiarize yourself with our [label system](.github/project-roadmap.md#issue-labels):

- **Type**: `bug`, `enhancement`, `documentation`, etc.
- **Priority**: `P0-critical`, `P1-high`, `P2-medium`, `P3-low`
- **Status**: `needs-triage`, `ready`, `in-progress`, etc.

### Milestones

Check our [milestones](https://github.com/tommy2118/rails-migration-guard/milestones) to see what we're working toward.

### Project Board

View our [project board](https://github.com/users/tommy2118/projects/1) to see the current status of all issues.

## Testing

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/lib/migration_guard/reporter_spec.rb

# Run with coverage report
COVERAGE=true bundle exec rspec
```

### Writing Tests

- Write tests before implementing features (TDD)
- Test edge cases and error conditions
- Use factories or fixtures for test data
- Keep tests focused and readable

## Release Process

1. Update version in `lib/migration_guard/version.rb`
2. Update CHANGELOG.md
3. Create a PR with version bump
4. After merge, create and push a tag:
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```
5. GitHub Actions will automatically publish to RubyGems

## Questions?

If you have questions about contributing:

1. Check existing [issues](https://github.com/tommy2118/rails-migration-guard/issues) and [discussions](https://github.com/tommy2118/rails-migration-guard/discussions)
2. Create a [new discussion](https://github.com/tommy2118/rails-migration-guard/discussions/new)
3. Join our community chat (if applicable)

## Recognition

Contributors will be recognized in:
- The CHANGELOG.md file
- The project README
- GitHub's contributor graph

Thank you for contributing to Rails Migration Guard! 🎉