# frozen_string_literal: true

require "rails_helper"
require "migration_waiter"

RSpec.describe MigrationWaiter do
  describe ".wait" do
    it "returns when there are no pending migrations" do
      expect(Process).not_to receive(:exit)
      expect(Postal.logger).to receive(:info).with("no pending migrations, continuing")
      expect { described_class.wait }.not_to raise_error
    end

    it "exits when migrations are still pending after the configured attempts" do
      migrator = instance_double(ActiveRecord::Migrator, pending_migrations: [double("migration")])
      context = instance_double(ActiveRecord::MigrationContext, open: migrator)
      allow(ActiveRecord::Base.connection_pool).to receive(:migration_context).and_return(context)
      allow(described_class).to receive(:sleep)
      allow(Process).to receive(:exit).with(1).and_raise(SystemExit)

      expect { described_class.wait }.to raise_error(SystemExit)
      expect(described_class).to have_received(:sleep).with(described_class::SLEEP_TIME).exactly(described_class::ATTEMPTS - 1).times
    end
  end

  describe ".wait_if_appropriate" do
    it "does not wait when the migration waiter is not enabled" do
      allow(Postal::Config.migration_waiter).to receive(:enabled?).and_return(false)
      expect(described_class).not_to receive(:wait)
      described_class.wait_if_appropriate
    end

    it "waits when enabled outside the console, rake tasks and rails commands" do
      allow(Postal::Config.migration_waiter).to receive(:enabled?).and_return(true)
      allow(described_class).to receive_messages(console?: false, rake_task?: false, rails_command?: false)
      expect(described_class).to receive(:wait)
      described_class.wait_if_appropriate
    end
  end
end
