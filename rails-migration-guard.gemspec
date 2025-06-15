require_relative "lib/migration_guard/version"

Gem::Specification.new do |spec|
  spec.name          = "rails-migration-guard"
  spec.version       = MigrationGuard::VERSION
  spec.authors       = ["Your Name"]
  spec.email         = ["your.email@example.com"]

  spec.summary       = "Prevent orphaned Rails migrations in development and staging"
  spec.description   = "A Rails gem that tracks database migrations across branches, identifies orphaned migrations, and provides tools for cleanup. Helps prevent database schema divergence in development and staging environments."
  spec.homepage      = "https://github.com/tommy2118/rails-migration-guard"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "CHANGELOG.md"]
  end

  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{\Abin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 6.1", "< 8.0"
  spec.add_dependency "activerecord", ">= 6.1", "< 8.0"
  spec.add_dependency "activesupport", ">= 6.1", "< 8.0"
  spec.add_dependency "bigdecimal"
  spec.add_dependency "logger"
  spec.add_dependency "mutex_m"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "sqlite3", "~> 1.4"
  spec.add_development_dependency "pry", "~> 0.14"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "rubocop-rspec", "~> 2.20"
  spec.add_development_dependency "rubocop-rails", "~> 2.19"
end