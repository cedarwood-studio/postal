# frozen_string_literal: true

require "rails_helper"

# From Action Pack 8.0.5.2 rendered responses name the request headers used to
# choose the format in Vary. Redirects are not rendered and carry no Vary.
RSpec.describe "Vary header", type: :request do
  it "is set on a rendered response" do
    get "/ip"

    expect(response).to have_http_status(:ok)
    expect(response.headers["Vary"]).to eq "Accept, X-Requested-With"
  end

  it "is not set on a redirect" do
    get "/"

    expect(response).to redirect_to("/login?return_to=%2F")
    expect(response.headers["Vary"]).to be_nil
  end
end
