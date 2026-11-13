# frozen_string_literal: true

require "rails_helper"

# The application keeps its own password reset token in the users table
# (password_reset_token and password_reset_token_valid_until). From Rails 8.0
# has_secure_password defines a signed token under the same name unless it is
# told not to, so these examples run the whole flow against the stored column.
RSpec.describe "Password reset", type: :request do
  let(:user) { create(:user, email_address: "reset@example.com") }

  before { ActionMailer::Base.deliveries.clear }

  describe "POST /login/reset" do
    it "stores a 24 character token valid for a day and e-mails a link containing it" do
      Timecop.freeze(Time.utc(2026, 1, 10, 12, 0, 0)) do
        post "/login/reset", params: { email_address: user.email_address }
      end

      expect(response).to redirect_to("/login")

      stored_token, valid_until = User.where(id: user.id).pick(:password_reset_token, :password_reset_token_valid_until)
      expect(stored_token).to match(/\A[A-Za-z0-9]{24}\z/)
      expect(valid_until).to eq Time.utc(2026, 1, 11, 12, 0, 0)

      expect(ActionMailer::Base.deliveries.size).to eq 1
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq [user.email_address]
      expect(mail.body.to_s).to include("/login/reset/#{stored_token}\n")
    end

    it "includes the return_to in the e-mailed link" do
      post "/login/reset", params: { email_address: user.email_address, return_to: "/org/acme" }

      stored_token = User.where(id: user.id).pick(:password_reset_token)
      expect(ActionMailer::Base.deliveries.last.body.to_s).to include("/login/reset/#{stored_token}?return_to=%2Forg%2Facme")
    end

    it "sends nothing for an unknown address" do
      post "/login/reset", params: { email_address: "nobody@example.com" }

      expect(response).to redirect_to("/login/reset")
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe "the e-mailed link" do
    def emailed_token
      post "/login/reset", params: { email_address: user.email_address }
      ActionMailer::Base.deliveries.last.body.to_s[/\/login\/reset\/([^\s?]+)/, 1]
    end

    it "sets the new password, clears the stored token and logs the user in" do
      token = emailed_token
      post "/login/reset/#{token}", params: { password: "n3w-passw0rd", password_confirmation: "n3w-passw0rd" }

      expect(response).to redirect_to("/")
      user.reload
      expect(user.authenticate("n3w-passw0rd")).to eq user
      expect(User.where(id: user.id).pick(:password_reset_token, :password_reset_token_valid_until)).to eq [nil, nil]

      get "/login/reset/#{token}"
      expect(response).to redirect_to("/login")
    end

    it "is refused once the stored token has expired" do
      token = emailed_token

      Timecop.freeze(25.hours.from_now) do
        get "/login/reset/#{token}"
      end

      expect(response).to redirect_to("/login")
    end
  end

  describe "User#password_reset_token" do
    it "reads the stored column" do
      user.update_columns(password_reset_token: "abcdefghijklmnopqrstuvwx")

      expect(User.find(user.id).password_reset_token).to eq "abcdefghijklmnopqrstuvwx"
    end
  end
end
