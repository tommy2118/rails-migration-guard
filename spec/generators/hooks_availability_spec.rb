# frozen_string_literal: true

require "rails_helper"
require "generators/migration_guard/hooks/hooks_generator"

RSpec.describe MigrationGuard::Generators::HooksGenerator do
  it "loads the hooks generator" do
    expect(defined?(described_class)).to be_truthy
  end

  it "inherits from Rails::Generators::Base" do
    expect(described_class.superclass).to eq(Rails::Generators::Base)
  end

  it "has proper description" do
    expect(described_class.desc).to eq("Installs git hooks for Rails Migration Guard")
  end
end
