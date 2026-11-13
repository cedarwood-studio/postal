# frozen_string_literal: true

# Records for the parity recording. Every id, uuid, token, key and timestamp is
# fixed so that two recordings of the same code agree byte for byte.

require "factory_bot"

# The recorder starts from an empty database server, so load the schema the
# same way the suite does before creating anything. Schema statements end an
# open transaction in MySQL, so they run on a second connection and leave the
# recorder's transaction alone.
unless ActiveRecord::Base.connection.table_exists?("users")
  Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      ActiveRecord::Schema.verbose = false
      load Rails.root.join("db/schema.rb").to_s
    end
  end.join
end

# The layouts link the compiled stylesheet and script. The test environment
# does not load the assets group, so compiling on demand fails and every HTML
# page would record an exception. Build the assets the way the Dockerfile does
# and point the view helpers at the fresh manifest, so pages render as they do
# in production and each recording exercises the asset build on its version.
assets_dir = Rails.root.join("public/assets").to_s
system({ "RAILS_GROUPS" => "assets" }, "bundle", "exec", "rake", "assets:precompile",
       out: File::NULL, err: File::NULL) || raise("asset precompile failed")
parity_manifest = Sprockets::Manifest.new(Rails.application.assets, assets_dir)
Rails.application.assets_manifest = parity_manifest
ActionView::Base.assets_manifest = parity_manifest

# The recorder holds the clock at a fixed time; every timestamp hangs off it.
PARITY_NOW = Time.now.utc

FactoryBot.find_definitions if FactoryBot.factories.none?

parity_uuid = ->(n) { format("00000000-0000-4000-8000-%012d", n) }
parity_pem = File.read(Rails.root.join("docker/ci-config/signing.key"))
stamp = { created_at: PARITY_NOW - 10.days, updated_at: PARITY_NOW - 10.days }

ip_pool = FactoryBot.create(:ip_pool, id: 9001, name: "Default Pool", default: true, uuid: parity_uuid.call(1), **stamp)
ip_address = FactoryBot.create(:ip_address, id: 9001, ip_pool: ip_pool, **stamp)

admin = FactoryBot.create(:user, id: 9001, admin: true, first_name: "Ada", last_name: "Admin",
                                 email_address: "admin@example.com", password: "passw0rd",
                                 time_zone: "UTC", uuid: parity_uuid.call(2),
                                 email_verified_at: PARITY_NOW - 10.days, **stamp)
member = FactoryBot.create(:user, id: 9002, admin: false, first_name: "Mia", last_name: "Member",
                                  email_address: "member@example.com", password: "passw0rd",
                                  time_zone: "UTC", uuid: parity_uuid.call(3),
                                  email_verified_at: PARITY_NOW - 10.days, **stamp)
resetter = FactoryBot.create(:user, id: 9003, admin: false, first_name: "Rex", last_name: "Reset",
                                    email_address: "reset@example.com", password: "passw0rd",
                                    time_zone: "UTC", uuid: parity_uuid.call(4),
                                    email_verified_at: PARITY_NOW - 10.days, **stamp)
resetter.update_columns(password_reset_token: "parityresettoken000000001", password_reset_token_valid_until: PARITY_NOW + 1.day)

org = FactoryBot.create(:organization, id: 9001, name: "Acme Inc", permalink: "acme", owner: admin,
                                       time_zone: "UTC", uuid: parity_uuid.call(10), **stamp)
org.organization_users.create!(user: admin, admin: true, all_servers: true)
org.organization_users.create!(user: member, admin: false, all_servers: true)
OrganizationIPPool.where(organization_id: org.id, ip_pool_id: ip_pool.id).first_or_create!

server = FactoryBot.create(:server, id: 9001, organization: org, name: "Mail Server", permalink: "mail",
                                    mode: "Live", token: "prtyaa", uuid: parity_uuid.call(20),
                                    ip_pool: ip_pool, **stamp)
suspended = FactoryBot.create(:server, id: 9002, organization: org, name: "Suspended Server", permalink: "suspended",
                                       mode: "Live", token: "prtybb", uuid: parity_uuid.call(21),
                                       suspended_at: PARITY_NOW - 1.day, suspension_reason: "Test Reason", **stamp)

domain = FactoryBot.create(:domain, id: 9001, owner: server, name: "mail.example.com", uuid: parity_uuid.call(30),
                                    dkim_identifier_string: "PRTYAA", verified_at: PARITY_NOW - 9.days, **stamp)
org_domain = FactoryBot.create(:domain, id: 9002, owner: org, name: "org.example.com", uuid: parity_uuid.call(31),
                                        dkim_identifier_string: "PRTYBB", verified_at: PARITY_NOW - 9.days, **stamp)
unverified = FactoryBot.create(:domain, id: 9003, owner: server, name: "unverified.example.com", uuid: parity_uuid.call(32),
                                        dkim_identifier_string: "PRTYCC", verified_at: nil, **stamp)
[domain, org_domain, unverified].each_with_index do |d, i|
  d.update_columns(dkim_private_key: parity_pem, verification_token: "parityverificationtoken00000000#{i}",
                   dkim_identifier_string: %w[PRTYAA PRTYBB PRTYCC][i])
end

credential = FactoryBot.create(:credential, id: 9001, server: server, name: "API Credential", type: "API",
                                            uuid: parity_uuid.call(40), **stamp)
credential.update_columns(key: "parityapikey000000000001")
smtp_credential = FactoryBot.create(:credential, id: 9002, server: server, name: "SMTP Credential", type: "SMTP",
                                                 uuid: parity_uuid.call(41), **stamp)
smtp_credential.update_columns(key: "paritysmtpkey00000000001")
suspended_credential = FactoryBot.create(:credential, id: 9003, server: suspended, name: "Suspended Credential", type: "API",
                                                      uuid: parity_uuid.call(42), **stamp)
suspended_credential.update_columns(key: "paritysuspendedkey000001")

http_endpoint = FactoryBot.create(:http_endpoint, id: 9001, server: server, uuid: parity_uuid.call(50), **stamp)
smtp_endpoint = FactoryBot.create(:smtp_endpoint, id: 9001, server: server, uuid: parity_uuid.call(51), **stamp)
address_endpoint = FactoryBot.create(:address_endpoint, id: 9001, server: server, address: "forward@example.com",
                                                        uuid: parity_uuid.call(52), **stamp)
route = FactoryBot.create(:route, id: 9001, server: server, domain: domain, name: "inbound", endpoint: http_endpoint,
                                  uuid: parity_uuid.call(53), token: "prtyrt01", **stamp)
webhook = FactoryBot.create(:webhook, id: 9001, server: server, uuid: parity_uuid.call(54), **stamp)
webhook_request = FactoryBot.create(:webhook_request, id: 9001, server: server, webhook: webhook,
                                                      uuid: parity_uuid.call(55), created_at: PARITY_NOW - 1.day)
track_domain = FactoryBot.create(:track_domain, id: 9001, server: server, domain: domain, name: "click",
                                                dns_status: "OK", uuid: parity_uuid.call(56), **stamp)
server_rule = FactoryBot.create(:ip_pool_rule, id: 9001, owner: server, ip_pool: ip_pool, to_text: "google.com",
                                               uuid: parity_uuid.call(57), **stamp)
org_rule = FactoryBot.create(:ip_pool_rule, id: 9002, owner: org, ip_pool: ip_pool, to_text: "example.org",
                                            uuid: parity_uuid.call(58), **stamp)

# The message database lives outside the main database, so it is not covered by
# the transaction around this file. Rebuild it from empty on every recording.
server.message_db.provisioner.provision
suspended.message_db.provisioner.provision

# Raw messages are written out by hand. The mail library picks random MIME
# boundaries and content ids when it builds a message, and those would differ
# between recordings.
plain_mail = lambda do |to, from, subject|
  [
    "Date: Thu, 01 Jan 2026 11:00:00 +0000",
    "From: #{from}",
    "To: #{to}",
    "Message-ID: <parity-#{subject.parameterize}@example.com>",
    "Subject: #{subject}",
    "Mime-Version: 1.0",
    "Content-Type: text/plain; charset=UTF-8",
    "Content-Transfer-Encoding: 7bit",
    "",
    "Hello world!",
    ""
  ].join("\r\n")
end

multipart_mail = [
  "Date: Thu, 01 Jan 2026 11:00:00 +0000",
  "From: test@mail.example.com",
  "To: john@example.com",
  "Message-ID: <parity-outgoing-example@example.com>",
  "Subject: Outgoing example",
  "Mime-Version: 1.0",
  "Content-Type: multipart/mixed; boundary=\"parity-mixed\"",
  "",
  "--parity-mixed",
  "Content-Type: multipart/alternative; boundary=\"parity-alt\"",
  "",
  "--parity-alt",
  "Content-Type: text/plain; charset=UTF-8",
  "Content-Transfer-Encoding: 7bit",
  "",
  "Hello world!",
  "--parity-alt",
  "Content-Type: text/html; charset=UTF-8",
  "Content-Transfer-Encoding: 7bit",
  "",
  "<html><body><p>hello <a href=\"https://example.com/\">link</a></p></body></html>",
  "--parity-alt--",
  "--parity-mixed",
  "Content-Type: text/plain; charset=UTF-8; name=note.txt",
  "Content-Transfer-Encoding: base64",
  "Content-Disposition: attachment; filename=note.txt",
  "",
  "aGVsbG8gYXR0YWNobWVudA==",
  "--parity-mixed--",
  ""
].join("\r\n")

outgoing = server.message_db.new_message
outgoing.scope = "outgoing"
outgoing.rcpt_to = "john@example.com"
outgoing.mail_from = "test@mail.example.com"
outgoing.domain_id = domain.id
outgoing.credential_id = credential.id
outgoing.token = "parityouttoken01"
outgoing.timestamp = (PARITY_NOW - 1.hour).to_f
outgoing.raw_message = multipart_mail
outgoing.save(queue_on_create: false)

incoming = server.message_db.new_message
incoming.scope = "incoming"
incoming.rcpt_to = "inbound@mail.example.com"
incoming.mail_from = "john@example.com"
incoming.route_id = route.id
incoming.token = "parityinctoken01"
incoming.timestamp = (PARITY_NOW - 2.hours).to_f
incoming.raw_message = plain_mail.call("inbound@mail.example.com", "john@example.com", "Incoming example")
incoming.save(queue_on_create: false)

held = server.message_db.new_message
held.scope = "outgoing"
held.rcpt_to = "held@example.com"
held.mail_from = "test@mail.example.com"
held.domain_id = domain.id
held.token = "parityheldtoken1"
held.timestamp = (PARITY_NOW - 3.hours).to_f
held.status = "Held"
held.held = true
held.raw_message = plain_mail.call("held@example.com", "test@mail.example.com", "Held example")
held.save(queue_on_create: false)

server.message_db.suppression_list.add(:recipient, "bounced@example.com", reason: "parity fixture")
