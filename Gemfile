# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in rails-migration-guard.gemspec
gemspec

# For testing against different Rails versions
rails_version = ENV.fetch("RAILS_VERSION", "7.0")
gem "rails", "~> #{rails_version}.0"

group :development, :test do
  gem "bundler", "~> 2.0"
  gem "pry", "~> 0.14"
  gem "pry-byebug" if RUBY_VERSION >= "3.0"
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.13"
  gem "rspec-rails", "~> 7.0"
  gem "rubocop", "~> 1.69"
  gem "rubocop-capybara", "~> 2.21"
  gem "rubocop-factory_bot", "~> 2.26"
  gem "rubocop-rails", "~> 2.28"
  gem "rubocop-rspec", "~> 3.3"
  gem "simplecov", "~> 0.22"
  gem "sqlite3", "~> 1.4"
end

# Suppress Ruby 3.5 deprecation warning
gem "benchmark"
