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
  if rails_version.to_f >= 7.0
    gem "rspec-rails", "~> 7.0"
  else
    gem "rspec-rails", "~> 6.0"
  end
  gem "rubocop", "~> 1.69"
  gem "rubocop-capybara", "~> 2.21"
  gem "rubocop-factory_bot", "~> 2.26"
  gem "rubocop-rails", "~> 2.28"
  gem "rubocop-rspec", "~> 3.3"
  gem "simplecov", "~> 0.22"
  if rails_version.to_f >= 8.0
    gem "sqlite3", "~> 2.1"
  else
    gem "sqlite3", "~> 1.4"
  end
end

# Ruby 3.4+ extracted these from stdlib
if RUBY_VERSION >= "3.4.0"
  gem "benchmark"
  gem "bigdecimal"
  gem "logger"
  gem "mutex_m"
end
