# frozen_string_literal: true

require "rails_helper"

RSpec.describe SendNotificationsScheduledTask do
  let(:logger) { TestLogger.new }
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }

  subject(:task) { described_class.new(logger: logger) }

  before do
    organization.users << user
    ActionMailer::Base.deliveries.clear
  end

  describe "#call" do
    context "when a server has exceeded its send limit in the last 3 minutes" do
      let!(:server) { create(:server, :exceeded_send_limit, organization: organization, send_limit: 100) }
      let!(:webhook) { create(:webhook, server: server) }

      it "emails the users of the organization" do
        task.call
        expect(ActionMailer::Base.deliveries.size).to eq 1
        expect(ActionMailer::Base.deliveries.last).to have_attributes(
          to: [user.email_address],
          subject: "[#{server.full_permalink}] Mail server has exceeded its send limit"
        )
      end

      it "records when the notification was sent" do
        task.call
        server.reload
        expect(server.send_limit_exceeded_notified_at).to be_within(5.seconds).of(Time.now)
        expect(server.send_limit_approaching_notified_at).to be_nil
      end

      it "creates a webhook request for the SendLimitExceeded event" do
        task.call
        expect(server.webhook_requests.count).to eq 1
        webhook_request = server.webhook_requests.first
        expect(webhook_request).to have_attributes(event: "SendLimitExceeded", url: webhook.url, webhook: webhook)
        expect(webhook_request.payload).to eq({ server: server.webhook_hash, volume: 0, limit: 100 })
      end

      it "does not notify again when run a second time" do
        task.call
        described_class.new(logger: logger).call
        expect(ActionMailer::Base.deliveries.size).to eq 1
        expect(server.webhook_requests.count).to eq 1
      end
    end

    context "when a server started approaching its send limit in the last 3 minutes" do
      let!(:server) { create(:server, organization: organization, send_limit: 100, send_limit_approaching_at: 1.minute.ago) }

      it "emails the users of the organization and records when it did" do
        task.call
        expect(ActionMailer::Base.deliveries.size).to eq 1
        expect(ActionMailer::Base.deliveries.last.subject).to eq "[#{server.full_permalink}] Mail server is approaching its send limit"
        expect(server.reload.send_limit_approaching_notified_at).to be_within(5.seconds).of(Time.now)
      end
    end

    context "when a server exceeded its send limit more than 3 minutes ago" do
      let!(:server) { create(:server, organization: organization, send_limit: 100, send_limit_exceeded_at: 5.minutes.ago) }

      it "does not notify" do
        task.call
        expect(ActionMailer::Base.deliveries).to be_empty
        expect(server.reload.send_limit_exceeded_notified_at).to be_nil
      end
    end

    context "when the organization has no users" do
      let!(:server) { create(:server, :exceeded_send_limit, send_limit: 100) }

      it "does not send an email but still records the notification" do
        task.call
        expect(ActionMailer::Base.deliveries).to be_empty
        expect(server.reload.send_limit_exceeded_notified_at).to be_within(5.seconds).of(Time.now)
      end
    end
  end

  describe ".next_run_after" do
    it "returns one minute from now" do
      Timecop.freeze(Time.utc(2026, 1, 1, 12, 20, 0)) do
        expect(described_class.next_run_after).to eq Time.utc(2026, 1, 1, 12, 21, 0)
      end
    end
  end
end
