# frozen_string_literal: true

module MigrationGuard
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class GitError < Error; end
  class MigrationNotFoundError < Error; end
  class RollbackError < Error; end

  # Recovery-specific errors
  class RecoveryError < Error; end
  class BackupError < RecoveryError; end
  class RestoreError < RecoveryError; end
  class DatabaseConnectionError < RecoveryError; end
  class MigrationLoadError < RecoveryError; end
  class FileSystemError < RecoveryError; end
  class ConcurrentAccessError < RecoveryError; end
  class EnvironmentError < RecoveryError; end
end
