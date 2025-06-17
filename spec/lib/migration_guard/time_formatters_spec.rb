# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationGuard::TimeFormatters do
  include described_class

  describe "#format_duration" do
    it "returns '0m' for zero or negative seconds" do
      expect(format_duration(0)).to eq("0m")
      expect(format_duration(-10)).to eq("0m")
    end

    it "formats minutes correctly" do
      expect(format_duration(30)).to eq("1m")
      expect(format_duration(90)).to eq("2m")
      expect(format_duration(300)).to eq("5m")
      expect(format_duration(3540)).to eq("59m")
    end

    it "formats hours correctly" do
      expect(format_duration(3600)).to eq("1h")
      expect(format_duration(7200)).to eq("2h")
      expect(format_duration(86_340)).to eq("23h")
    end

    it "formats days correctly" do
      expect(format_duration(86_400)).to eq("1d")
      expect(format_duration(172_800)).to eq("2d")
      expect(format_duration(604_800)).to eq("7d")
    end
  end

  describe "#format_time_since" do
    it "returns nil for nil timestamp" do
      expect(format_time_since(nil)).to be_nil
    end

    it "formats time since a given timestamp" do
      allow(Time).to receive(:current).and_return(Time.zone.parse("2024-01-16 12:00:00"))

      timestamp = Time.zone.parse("2024-01-16 11:30:00")
      expect(format_time_since(timestamp)).to eq("30m")

      timestamp = Time.zone.parse("2024-01-16 10:00:00")
      expect(format_time_since(timestamp)).to eq("2h")

      timestamp = Time.zone.parse("2024-01-15 12:00:00")
      expect(format_time_since(timestamp)).to eq("1d")
    end
  end
end
