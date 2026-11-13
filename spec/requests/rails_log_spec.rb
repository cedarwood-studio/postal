# frozen_string_literal: true

require "rails_helper"

# The Rails log is off unless logging.rails_log_enabled is set, so no other
# spec reads what Rails writes to it. These examples point the Action
# Controller and Action View loggers at a string for one request and pin the
# shape of the "Completed" and "Rendered" lines, for anyone who feeds the Rails
# log to a parser. Since Rails 7.2 the Active Record part carries a query count
# and both lines end in a GC time; before that both ended in an allocation
# count. The request asks for JSON because the full application layout depends
# on the asset pipeline which is not configured in this test environment.
RSpec.describe "Rails log", type: :request do
  let(:user) { create(:user, admin: true) }
  let(:organization) { create(:organization, owner: user) }
  let(:server) { create(:server, organization: organization) }

  let(:output) { StringIO.new }
  let(:lines) { output.string.lines.map(&:chomp) }

  around do |example|
    original = [ActionController::Base.logger, ActionView::Base.logger]
    example.run
  ensure
    ActionController::Base.logger, ActionView::Base.logger = original
  end

  before do
    post "/login", params: { email_address: user.email_address, password: "passw0rd" }
    path = "/org/#{organization.permalink}/servers/#{server.permalink}/messages/outgoing"

    logger = Logger.new(output)
    logger.formatter = proc { |_, _, _, message| "#{message}\n" }
    ActionController::Base.logger = logger
    ActionView::Base.logger = logger
    get path, headers: { "Accept" => "application/json" }
  end

  it "writes the Completed line with a query count and a GC time" do
    expect(response).to have_http_status(:ok)
    completed = lines.grep(/\ACompleted /)
    expect(completed.size).to eq 1
    expect(completed.first).to match(
      /\ACompleted 200 OK in \d+ms \(Views: \d+\.\dms \| ActiveRecord: \d+\.\dms \(\d+ quer(?:y|ies), \d+ cached\) \| GC: \d+\.\dms\)\z/
    )
  end

  it "ends each Rendered line with a GC time" do
    rendered = lines.grep(/\A\s*Rendered /)
    expect(rendered).not_to be_empty
    expect(rendered).to all(match(/\(Duration: \d+\.\dms \| GC: \d+\.\dms\)\z/))
  end

  it "writes no allocation count" do
    expect(lines.grep(/Allocations:/)).to be_empty
  end
end
