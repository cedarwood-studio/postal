# frozen_string_literal: true

require "rails_helper"

RSpec.describe CheckAllDNSScheduledTask do
  let(:logger) { TestLogger.new }

  subject(:task) { described_class.new(logger: logger) }

  describe "#call" do
    let(:domain_checks) { [] }
    let(:track_domain_checks) { [] }

    before do
      domain_checks = self.domain_checks
      track_domain_checks = self.track_domain_checks
      allow_any_instance_of(Domain).to receive(:check_dns) { |domain, *args| domain_checks << [domain.id, args] }
      allow_any_instance_of(TrackDomain).to receive(:check_dns) { |track_domain, *args| track_domain_checks << [track_domain.id, args] }
    end

    it "checks domains which were last checked over an hour ago" do
      domain = create(:domain, dns_checked_at: 2.hours.ago)
      task.call
      expect(domain_checks).to eq [[domain.id, [:auto]]]
      expect(logger).to have_logged("checking DNS for domain: #{domain.name}")
    end

    it "does not check domains which were checked within the last hour" do
      create(:domain, dns_checked_at: 10.minutes.ago)
      task.call
      expect(domain_checks).to be_empty
    end

    it "does not check domains which have never been checked" do
      create(:domain, dns_checked_at: nil)
      task.call
      expect(domain_checks).to be_empty
    end

    it "checks track domains which have never been checked" do
      track_domain = create(:track_domain, dns_checked_at: nil)
      task.call
      expect(track_domain_checks).to eq [[track_domain.id, []]]
      expect(logger).to have_logged("checking DNS for track domain: #{track_domain.full_name}")
    end

    it "checks track domains which were last checked over an hour ago" do
      track_domain = create(:track_domain, dns_checked_at: 2.hours.ago)
      task.call
      expect(track_domain_checks).to eq [[track_domain.id, []]]
    end

    it "does not check track domains which were checked within the last hour" do
      create(:track_domain, dns_checked_at: 10.minutes.ago)
      task.call
      expect(track_domain_checks).to be_empty
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
