# frozen_string_literal: true

require "rails_helper"

RSpec.describe PruneWebhookRequestsScheduledTask do
  let(:logger) { TestLogger.new }
  let(:server) { create(:server) }

  subject(:task) { described_class.new(logger: logger) }

  def record_webhook_request(uuid, age:)
    server.message_db.webhooks.record(
      event: "MessageSent",
      url: "https://example.com",
      attempt: 1,
      timestamp: age.ago.to_f,
      payload: "{}",
      uuid: uuid,
      status_code: 200,
      body: "OK",
      will_retry: false
    )
  end

  def recorded_uuids
    server.message_db.select(:webhook_requests, order: :id).map { |r| r["uuid"] }
  end

  describe "#call" do
    it "removes recorded webhook requests which are more than 10 days old" do
      record_webhook_request("old", age: 11.days)
      record_webhook_request("recent", age: 9.days)
      task.call
      expect(recorded_uuids).to eq ["recent"]
      expect(logger).to have_logged("Pruning webhook requests for server #{server.id}")
    end

    it "does not remove anything when no request is more than 10 days old" do
      record_webhook_request("recent", age: 9.days)
      task.call
      expect(recorded_uuids).to eq ["recent"]
    end

    # The prune removes every row up to the ID of the newest old request, so a
    # recent request which was recorded before an old one is removed with it.
    it "removes recent requests which were recorded before an old request" do
      record_webhook_request("recent-recorded-first", age: 1.day)
      record_webhook_request("old", age: 11.days)
      record_webhook_request("recent-recorded-last", age: 1.day)
      task.call
      expect(recorded_uuids).to eq ["recent-recorded-last"]
    end
  end

  describe ".next_run_after" do
    it "returns quarter to the current hour when that is still to come" do
      Timecop.freeze(Time.utc(2026, 1, 1, 12, 20, 0)) do
        expect(described_class.next_run_after).to eq Time.utc(2026, 1, 1, 12, 45, 0)
      end
    end

    it "returns quarter to the next hour when that has passed" do
      Timecop.freeze(Time.utc(2026, 1, 1, 12, 50, 0)) do
        expect(described_class.next_run_after).to eq Time.utc(2026, 1, 1, 13, 45, 0)
      end
    end
  end
end
