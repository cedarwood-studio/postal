# frozen_string_literal: true

require "rails_helper"

# config/initializers/secret_key.rb puts the key in the credentials. From Rails
# 7.2.3 the test and development environments read it from there as production
# always has, rather than from a generated tmp/local_secret.txt.
RSpec.describe "The secret key base" do
  it "is the key the initializer put in the credentials" do
    expect(Rails.application.credentials.secret_key_base).to be_present
    expect(Rails.application.secret_key_base).to eq Rails.application.credentials.secret_key_base
  end
end
