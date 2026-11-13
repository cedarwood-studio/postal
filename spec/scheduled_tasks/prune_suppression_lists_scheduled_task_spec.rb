# frozen_string_literal: true

require "rails_helper"

RSpec.describe PruneSuppressionListsScheduledTask do
  let(:logger) { TestLogger.new }
  let(:server) { create(:server) }

  subject(:task) { described_class.new(logger: logger) }

  def suppressed_addresses
    server.message_db.select("suppressions").map { |s| s["address"] }
  end

  describe "#call" do
    it "removes suppressions which have passed their keep until time" do
      server.message_db.suppression_list.add(:recipient, "expired@example.com")
      server.message_db.update("suppressions", { keep_until: 1.minute.ago.to_f }, where: { address: "expired@example.com" })
      task.call
      expect(suppressed_addresses).to eq []
      expect(logger).to have_logged("Pruning suppression lists for server #{server.id}")
    end

    it "does not remove suppressions which have not passed their keep until time" do
      server.message_db.suppression_list.add(:recipient, "current@example.com")
      task.call
      expect(suppressed_addresses).to eq ["current@example.com"]
    end
  end

  describe ".next_run_after" do
    it "returns the next 3am" do
      Timecop.freeze(Time.utc(2026, 1, 1, 12, 20, 0)) do
        expect(described_class.next_run_after).to eq Time.utc(2026, 1, 2, 3, 0, 0)
      end
    end
  end
end
