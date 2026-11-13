# frozen_string_literal: true

require "rails_helper"

# The test environment raises exceptions instead of rendering them, so no other
# request spec reaches the static error pages. These examples switch rendering
# on, the way production runs, and pin what a client receives for a path that
# does not exist. Since Rails 7.2.3 a HEAD request that ends in an error page is
# answered with an empty body in the format the request asked for; before that
# it was answered with the headers of the HTML page.
RSpec.describe "Error pages", type: :request do
  around do |example|
    env_config = Rails.application.env_config
    original = env_config.slice("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
    env_config["action_dispatch.show_exceptions"] = :all
    env_config["action_dispatch.show_detailed_exceptions"] = false
    example.run
  ensure
    env_config.merge!(original)
  end

  let(:not_found_page) { Rails.public_path.join("404.html").read }

  describe "GET a path that does not exist" do
    it "renders the static 404 page" do
      get "/no/such/page", headers: { "Accept" => "*/*" }
      expect(response).to have_http_status(:not_found)
      expect(response.headers["Content-Type"]).to eq "text/html; charset=UTF-8"
      expect(response.headers["Content-Length"]).to eq not_found_page.bytesize.to_s
      expect(response.body).to eq not_found_page
    end
  end

  describe "HEAD a path that does not exist" do
    it "answers 404 with an empty body in the requested format" do
      head "/no/such/page", headers: { "Accept" => "*/*" }
      expect(response).to have_http_status(:not_found)
      expect(response.headers["Content-Type"]).to eq "*/*; charset=UTF-8"
      expect(response.headers["Content-Length"]).to eq "0"
      expect(response.body).to eq ""
    end

    it "keeps the HTML content type for a client that asks for HTML" do
      head "/no/such/page", headers: { "Accept" => "text/html" }
      expect(response).to have_http_status(:not_found)
      expect(response.headers["Content-Type"]).to eq "text/html; charset=UTF-8"
      expect(response.headers["Content-Length"]).to eq "0"
      expect(response.body).to eq ""
    end
  end
end
