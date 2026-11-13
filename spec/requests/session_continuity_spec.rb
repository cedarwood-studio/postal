# frozen_string_literal: true

require "rails_helper"

# The cookies below were issued by this application running on Rails 7.1.6, in
# response to a successful POST /login, with the secret key base set to
# SECRET_KEY_BASE. They pin that a browser which signed in before an upgrade
# is still signed in after it, and that its session can still be decrypted.
RSpec.describe "Session continuity", type: :request do
  secret_key_base = "postal-characterization-secret-key-base-7-1-6-#{'0123456789abcdef' * 6}"
  browser_id = "841d3e0a-4383-48e8-ab9a-136921a20fee"
  user_session = "pYWRn2oSVYkcaRALt4DXrVF372WeJVZaKdB4zoCSApnfRQ1vulsm00SaTk1P7IyX"
  session_id = "3cf3aac426670d34fbcfb711ee8e1b3c"
  postal_session = "iYCXSvOe9/M7+TfQJ6oB++SP1r2e1B75ZHk/V3tUxS4RWl1xGaNp1qlsYZk+PM1pkQUYezYXkyet6xLYHxRYwTWBHxjpc9QbpTVc4kLCB8val" \
                   "jGKjfQfciT7vKsYZL5V4/vHCAAWDRdYUlrYV+7f5bk6wB8PUp040Ues2cCKJ2rFNZfuODRH6jf6a7We51GL+UxDqf/cy5xJ44H6Yhw0xST73I" \
                   "exjvt7PXXGYcH354w5MWNBTOWbybtzg4vGaqI/3oNCfgbNYIpZd3JHfOw+s96vFw==--+ZYaND4NtxqOl6i+--87Klm35qGL+SMr1zHuZ4Yg=="

  let(:user) { create(:user) }

  # The database row which Authie created alongside the cookies.
  let!(:auth_session) do
    auth_session = Authie::SessionModel.create!(
      user: user,
      browser_id: browser_id,
      host: Postal::Config.postal.web_hostname,
      login_at: 1.minute.ago,
      last_activity_at: 1.minute.ago
    )
    auth_session.update_columns(token_hash: Digest::SHA256.hexdigest(user_session))
    auth_session
  end

  def use_secret_key_base(secret_key_base)
    env_config = Rails.application.env_config.merge(
      "action_dispatch.key_generator" => Rails.application.key_generator(secret_key_base),
      "action_dispatch.secret_key_base" => secret_key_base
    )
    allow(Rails.application).to receive(:env_config).and_return(env_config)
  end

  context "with the cookies of a browser which signed in on Rails 7.1.6" do
    before do
      use_secret_key_base(secret_key_base)
      cookies["browser_id"] = browser_id
      cookies["user_session"] = user_session
      cookies["_postal_session"] = postal_session
      post "/persist"
    end

    it "treats the request as signed in" do
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq "OK"
    end

    it "updates the stored session" do
      auth_session.reload
      expect(auth_session.active).to be true
      expect(auth_session.requests).to eq 1
      expect(auth_session.last_activity_path).to eq "/persist"
      expect(auth_session.expires_at).to be_within(1.minute).of(2.months.from_now)
    end

    it "reads the session and flash from the session cookie" do
      expect(session[:session_id]).to eq session_id
      expect(flash[:remember_login]).to be true
    end
  end

  context "with the same cookies and a different secret key" do
    before do
      use_secret_key_base("another-secret-key-base-#{'0123456789abcdef' * 6}")
      cookies["browser_id"] = browser_id
      cookies["user_session"] = user_session
      cookies["_postal_session"] = postal_session
      post "/persist"
    end

    it "is still signed in but does not read the session cookie" do
      expect(response).to have_http_status(:ok)
      expect(session[:session_id]).not_to eq session_id
      expect(flash[:remember_login]).to be_nil
    end
  end

  context "with a session cookie only" do
    before do
      use_secret_key_base(secret_key_base)
      cookies["_postal_session"] = postal_session
      post "/persist"
    end

    it "redirects to the login page" do
      expect(response).to redirect_to("/login?return_to=%2Fpersist")
    end
  end
end
