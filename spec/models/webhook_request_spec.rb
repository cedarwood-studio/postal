# frozen_string_literal: true

require "rails_helper"

describe WebhookRequest do
  # The payload column holds a Hash serialized as YAML text. These examples pin
  # the text as Rails 7.1.6 writes it and check that rows holding that text can
  # still be read.
  describe "#payload" do
    let(:organization) { create(:organization, permalink: "acme") }
    let(:server) { create(:server, organization: organization, permalink: "mail", uuid: "56749a05-ee88-4aa5-b315-a4c26d45a80d") }
    let(:webhook) { create(:webhook, server: server) }

    let(:send_limit_payload_yaml) do
      <<~YAML
        ---
        :server:
          :uuid: 56749a05-ee88-4aa5-b315-a4c26d45a80d
          :name: Mail Server
          :permalink: mail
          :organization: acme
        :volume: 5
        :limit: 100
      YAML
    end

    let(:send_limit_payload) do
      {
        server: { uuid: "56749a05-ee88-4aa5-b315-a4c26d45a80d", name: "Mail Server", permalink: "mail", organization: "acme" },
        volume: 5,
        limit: 100
      }
    end

    def stored_payload(webhook_request)
      webhook_request.reload.read_attribute_before_type_cast(:payload)
    end

    def store_payload(webhook_request, text)
      connection = described_class.connection
      connection.update("UPDATE webhook_requests SET payload = #{connection.quote(text)} WHERE id = #{webhook_request.id}")
    end

    it "stores the payload of a triggered event as YAML with symbol keys" do
      webhook
      described_class.trigger(server, "SendLimitExceeded", server: server.webhook_hash, volume: 5, limit: 100)
      webhook_request = server.webhook_requests.first
      expect(stored_payload(webhook_request)).to eq send_limit_payload_yaml
    end

    it "stores a hash with string keys as YAML" do
      webhook_request = create(:webhook_request, webhook: webhook, payload: { "hello" => "world", "size" => 1.5, "bounce" => nil })
      expect(stored_payload(webhook_request)).to eq "---\nhello: world\nsize: 1.5\nbounce:\n"
    end

    it "reads a stored YAML payload with symbol keys" do
      webhook_request = create(:webhook_request, webhook: webhook)
      store_payload(webhook_request, send_limit_payload_yaml)
      expect(webhook_request.reload.payload).to eq send_limit_payload
    end

    it "reads a stored YAML payload with string keys" do
      webhook_request = create(:webhook_request, webhook: webhook)
      store_payload(webhook_request, "---\nhello: world\nsize: 1.5\nbounce:\n")
      expect(webhook_request.reload.payload).to eq({ "hello" => "world", "size" => 1.5, "bounce" => nil })
    end

    it "reads a stored NULL as an empty hash" do
      webhook_request = create(:webhook_request, webhook: webhook)
      store_payload(webhook_request, nil)
      expect(webhook_request.reload.payload).to eq({})
    end
  end
end
