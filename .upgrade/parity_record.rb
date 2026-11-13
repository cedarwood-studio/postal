# parity_record.rb <inputs.json> <out.json>
#
# Records what the application answers to a fixed set of requests, in process,
# through ActionDispatch::Integration::Session. No server, no port, no network.
# The recording is the "before" or "after" half of a shadow-run diff.
#
# inputs.json: {"host": "...", "auto_get_routes": true, "setup": "/out/x.rb",
#               "requests": [{"name","method","path","headers","params","session"}]}
require "json"
inputs_path, out_path = ARGV
inputs = File.exist?(inputs_path) ? JSON.parse(File.read(inputs_path)) : {}
ENV["RAILS_ENV"] ||= "test"
srand(1)
require File.expand_path("config/environment", Dir.pwd)
require "action_dispatch/testing/integration"
require "active_support/testing/time_helpers"

helper = Object.new.extend(ActiveSupport::Testing::TimeHelpers)
helper.travel_to(Time.utc(2026, 1, 1, 12, 0, 0))

requests = (inputs["requests"] || []).dup
if inputs.fetch("auto_get_routes", true)
  seen = {}
  Rails.application.routes.routes.each do |r|
    verb = r.verb.to_s
    next unless verb.empty? || verb.split("|").include?("GET")
    path = r.path.spec.to_s.sub("(.:format)", "")
    next if path.include?(":") || path.include?("*") || path.include?("(")
    next if path.start_with?("/rails/", "/assets", "/cable")
    next if r.app.respond_to?(:engine?) && r.app.engine?
    next if seen[path]
    seen[path] = true
    requests << { "name" => "GET #{path}", "method" => "GET", "path" => path, "auto" => true }
  end
end

VOLATILE = %w[x-request-id x-runtime date etag set-cookie content-length server-timing].freeze
records = []
conn = defined?(ActiveRecord::Base) ? ActiveRecord::Base.connection : nil
conn&.begin_transaction(joinable: false)
begin
  if inputs["setup"] && File.exist?(inputs["setup"])
    load inputs["setup"]
  end
  sessions = {}
  requests.each do |req|
    # Requests that name the same "session" share cookies, so a sign-in
    # request can be followed by signed-in pages.
    session = (req["session"] && sessions[req["session"]]) || begin
      s = ActionDispatch::Integration::Session.new(Rails.application)
      s.host!(inputs["host"]) if inputs["host"]
      sessions[req["session"]] = s if req["session"]
      s
    end
    rec = { "name" => req["name"] || "#{req['method']} #{req['path']}",
            "method" => req["method"] || "GET", "path" => req["path"] }
    begin
      session.process(rec["method"].downcase.to_sym, req["path"],
                      params: req["params"], headers: req["headers"] || {})
      resp = session.response
      headers = {}
      resp.headers.each { |k, v| headers[k.to_s.downcase] = v.to_s }
      cookies = headers["set-cookie"].to_s.split(/\n|, (?=[^;]+=)/).map { |c| c[/\A[^=]+/] }.compact.sort
      rec["status"] = resp.status
      rec["headers"] = headers.reject { |k, _| VOLATILE.include?(k) }.sort.to_h
      rec["cookie_names"] = cookies
      rec["body"] = resp.body.to_s.dup.force_encoding("UTF-8").scrub("?")
    rescue Exception => e # rubocop:disable Lint/RescueException
      rec["error"] = { "class" => e.class.name, "message" => e.message.to_s[0, 300] }
    end
    records << rec
  end
ensure
  conn&.rollback_transaction
end

File.write(out_path, JSON.pretty_generate(
  "recorded_with" => { "rails" => Rails.version, "ruby" => RUBY_VERSION, "env" => Rails.env.to_s },
  "request_count" => records.size, "requests" => records
))
puts "recorded #{records.size} requests on Rails #{Rails.version}, Ruby #{RUBY_VERSION}"
