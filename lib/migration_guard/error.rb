# frozen_string_literal: true

module MigrationGuard
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class GitError < Error; end
  class MigrationNotFoundError < Error; end
  class RollbackError < Error; end
end
