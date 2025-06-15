require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: %i[spec rubocop]

desc "Run specs against multiple Rails versions"
task :test_all do
  %w[6.1 7.0 7.1].each do |rails_version|
    puts "Testing against Rails #{rails_version}"
    system("RAILS_VERSION=#{rails_version} bundle exec rspec") || exit(1)
  end
end