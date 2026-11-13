# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanupAuthieSessionsScheduledTask do
  let(:logger) { TestLogger.new }
  let(:user) { create(:user) }

  subject(:task) { described_class.new(logger: logger) }

  def create_session(**attributes)
    Authie::SessionModel.create!(user: user, browser_id: SecureRandom.uuid, login_at: 1.day.ago, **attributes)
  end

  describe "#call" do
    it "invalidates transient sessions which have been inactive for longer than the inactivity timeout" do
      session = create_session(last_activity_at: 13.hours.ago)
      task.call
      expect(session.reload.active).to be false
    end

    it "does not invalidate transient sessions which have been used recently" do
      session = create_session(last_activity_at: 11.hours.ago)
      task.call
      expect(session.reload.active).to be true
    end

    it "invalidates persistent sessions which have expired" do
      session = create_session(last_activity_at: 1.minute.ago, expires_at: 1.minute.ago)
      task.call
      expect(session.reload.active).to be false
    end

    it "does not invalidate persistent sessions which have not expired" do
      session = create_session(last_activity_at: 13.hours.ago, expires_at: 1.day.from_now)
      task.call
      expect(session.reload.active).to be true
    end

    it "does not remove any sessions" do
      create_session(last_activity_at: 13.hours.ago)
      expect { task.call }.not_to change(Authie::SessionModel, :count)
    end
  end

  describe ".next_run_after" do
    it "returns the next quarter past the hour" do
      Timecop.freeze(Time.utc(2026, 1, 1, 12, 20, 0)) do
        expect(described_class.next_run_after).to eq Time.utc(2026, 1, 1, 13, 15, 0)
      end
    end
  end
end
