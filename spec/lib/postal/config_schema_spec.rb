# frozen_string_literal: true

require "rails_helper"

module Postal

  RSpec.describe ConfigSchema do
    def build_config(env)
      Konfig::Config.build(ConfigSchema, sources: [Konfig::Sources::Environment.new(env)])
    end

    describe "postal.smtp_relays" do
      it "reads the ssl_mode from the query string of each relay" do
        config = build_config("POSTAL_SMTP_RELAYS" => "smtp://relay1.example.com:2525?ssl_mode=TLS,smtp://relay2.example.com")
        expect(config.postal.smtp_relays).to eq [
          { "host" => "relay1.example.com", "port" => 2525, "ssl_mode" => "TLS" },
          { "host" => "relay2.example.com", "port" => 25, "ssl_mode" => "Auto" },
        ]
      end
    end
  end

end
