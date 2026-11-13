# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessMessageRetentionScheduledTask do
  let(:logger) { TestLogger.new }
  let(:server) { create(:server) }
  let(:old_raw_table) { "raw-2020-01-01" }

  subject(:task) { described_class.new(logger: logger) }

  def create_message(age:)
    message = MessageFactory.incoming(server)
    server.message_db.update(:messages, { timestamp: age.ago.to_f }, where: { id: message.id })
    message
  end

  def message_exists?(message)
    server.message_db.select(:messages, where: { id: message.id }).any?
  end

  after do
    provisioner = server.message_db.provisioner
    provisioner.drop_table(old_raw_table) if provisioner.raw_tables(nil).include?(old_raw_table)
  end

  describe "#call" do
    context "when the server has the default retention settings" do
      it "has a retention of 30 days and 2048 MB for raw messages and 60 days for messages" do
        expect(server).to have_attributes(
          raw_message_retention_days: 30,
          raw_message_retention_size: 2048,
          message_retention_days: 60
        )
      end

      it "removes messages older than the message retention" do
        old_message = create_message(age: 62.days)
        task.call
        expect(message_exists?(old_message)).to be false
        expect(logger).to have_logged("Tidying messages for #{server.permalink} (ID: #{server.id}). Keeping 60 days.")
      end

      it "does not remove messages within the message retention" do
        recent_message = create_message(age: 58.days)
        task.call
        expect(message_exists?(recent_message)).to be true
      end

      it "removes raw message tables older than the raw message retention" do
        server.message_db.provisioner.create_raw_table(old_raw_table)
        task.call
        expect(server.message_db.provisioner.raw_tables(nil)).not_to include(old_raw_table)
        expect(logger).to have_logged("Tidying raw messages (by days) for #{server.permalink} (ID: #{server.id}). Keeping 30 days.")
      end

      it "does not remove raw message tables within the raw message retention" do
        recent_message = create_message(age: 0.days)
        task.call
        expect(server.message_db.provisioner.raw_tables(nil)).to include(recent_message.raw_table)
        expect(logger).to have_logged("Tidying raw messages (by size) for #{server.permalink} (ID: #{server.id}). Keeping 2048 MB of data.")
      end
    end

    context "when the server has no retention settings" do
      before do
        server.update_columns(raw_message_retention_days: nil, raw_message_retention_size: nil, message_retention_days: nil)
      end

      it "does not remove anything" do
        old_message = create_message(age: 62.days)
        server.message_db.provisioner.create_raw_table(old_raw_table)
        task.call
        expect(message_exists?(old_message)).to be true
        expect(server.message_db.provisioner.raw_tables(nil)).to include(old_raw_table)
        expect(logger).not_to have_logged(/Tidying/)
      end
    end
  end

  describe ".next_run_after" do
    it "returns 3am today when that is still to come" do
      Timecop.freeze(Time.utc(2026, 1, 1, 2, 0, 0)) do
        expect(described_class.next_run_after).to eq Time.utc(2026, 1, 1, 3, 0, 0)
      end
    end

    it "returns 3am tomorrow when that has passed" do
      Timecop.freeze(Time.utc(2026, 1, 1, 12, 20, 0)) do
        expect(described_class.next_run_after).to eq Time.utc(2026, 1, 2, 3, 0, 0)
      end
    end
  end
end
