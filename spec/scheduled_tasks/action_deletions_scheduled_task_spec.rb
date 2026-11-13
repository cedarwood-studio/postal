# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActionDeletionsScheduledTask do
  let(:logger) { TestLogger.new }

  subject(:task) { described_class.new(logger: logger) }

  describe "#call" do
    let(:dropped_databases) { [] }

    # Servers loaded by the task do not carry the factory's provision_database
    # flag, so destroying them drops their message database.
    before do
      GlobalMessageDB.find_or_create
      dropped_databases = self.dropped_databases
      allow_any_instance_of(Postal::MessageDB::Provisioner).to receive(:drop) do |provisioner|
        dropped_databases << provisioner.instance_variable_get(:@database).server_id
      end
    end

    it "destroys organizations which have been soft deleted" do
      organization = create(:organization, deleted_at: 1.minute.ago)
      task.call
      expect { organization.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(logger).to have_logged("permanently removing organization #{organization.id} (#{organization.permalink})")
    end

    it "destroys the servers of a soft deleted organization" do
      organization = create(:organization, deleted_at: 1.minute.ago)
      server = create(:server, organization: organization)
      task.call
      expect { server.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(dropped_databases).to eq [server.id]
    end

    it "destroys servers which have been soft deleted" do
      server = create(:server, deleted_at: 1.minute.ago)
      task.call
      expect { server.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect { server.organization.reload }.not_to raise_error
      expect(dropped_databases).to eq [server.id]
      expect(logger).to have_logged("permanently removing server #{server.id} (#{server.full_permalink})")
    end

    it "does not destroy organizations or servers which have not been deleted" do
      server = create(:server)
      task.call
      expect { server.reload }.not_to raise_error
      expect { server.organization.reload }.not_to raise_error
      expect(dropped_databases).to be_empty
      expect(logger).not_to have_logged(/permanently removing/)
    end
  end

  describe ".next_run_after" do
    it "returns quarter past the current hour when that is still to come" do
      Timecop.freeze(Time.utc(2026, 1, 1, 12, 10, 0)) do
        expect(described_class.next_run_after).to eq Time.utc(2026, 1, 1, 12, 15, 0)
      end
    end

    it "returns quarter past the next hour when that has passed" do
      Timecop.freeze(Time.utc(2026, 1, 1, 12, 20, 0)) do
        expect(described_class.next_run_after).to eq Time.utc(2026, 1, 1, 13, 15, 0)
      end
    end
  end
end
