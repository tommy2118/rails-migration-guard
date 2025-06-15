source "https://rubygems.org"

# Specify your gem's dependencies in rails-migration-guard.gemspec
gemspec

gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"

# For testing against different Rails versions
rails_version = ENV.fetch("RAILS_VERSION", "7.0")
gem "rails", "~> #{rails_version}.0"

group :development, :test do
  gem "pry"
  gem "pry-byebug" if RUBY_VERSION >= "3.0"
end