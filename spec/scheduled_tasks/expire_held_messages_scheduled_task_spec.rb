# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExpireHeldMessagesScheduledTask do
  let(:logger) { TestLogger.new }
  let(:server) { create(:server) }

  subject(:task) { described_class.new(logger: logger) }

  def create_held_message(hold_expiry:)
    message = MessageFactory.incoming(server)
    message.update(status: "Held", held: true, hold_expiry: hold_expiry.to_f)
    message
  end

  describe "#call" do
    it "cancels the hold on held messages whose hold has expired" do
      message = create_held_message(hold_expiry: 1.hour.ago)
      task.call

      message = server.message_db.message(message.id)
      expect(message.status).to eq "HoldCancelled"
      expect(message.held).to be false
      expect(message.hold_expiry).to be_nil
      expect(message.deliveries.last).to have_attributes(
        status: "HoldCancelled",
        details: "The hold on this message has been removed without action."
      )
    end

    it "does not change held messages whose hold has not expired" do
      message = create_held_message(hold_expiry: 1.hour.from_now)
      task.call

      message = server.message_db.message(message.id)
      expect(message.status).to eq "Held"
      expect(message.held).to be true
      expect(message.deliveries).to be_empty
    end

    it "does not change messages which are not held" do
      message = MessageFactory.incoming(server)
      message.update(hold_expiry: 1.hour.ago.to_f)
      task.call

      message = server.message_db.message(message.id)
      expect(message.status).to eq "Pending"
      expect(message.deliveries).to be_empty
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
