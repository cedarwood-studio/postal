# frozen_string_literal: true

require "rails_helper"

describe Postal::MessageParser do
  let(:server) { create(:server) }

  it "should not do anything when there are no tracking domains" do
    expect(server.track_domains.size).to eq 0
    message = create_plain_text_message(server, "Hello world!", "test@example.com")
    parser = Postal::MessageParser.new(message)
    expect(parser.actioned?).to be false
    expect(parser.tracked_links).to eq 0
    expect(parser.tracked_images).to eq 0
  end

  it "should replace links in messages" do
    message = create_plain_text_message(server, "Hello world! http://github.com/atech/postal", "test@example.com")
    create(:track_domain, server: server, domain: message.domain)
    parser = Postal::MessageParser.new(message)
    expect(parser.actioned?).to be true
    expect(parser.new_body).to match(/^Hello world! https:\/\/click\.#{message.domain.name}/)
    expect(parser.tracked_links).to eq 1
  end

  it "should replace links in HTML messages and store the unescaped URL" do
    domain = create(:domain, owner: server)
    prototype = OutgoingMessagePrototype.new(server, "127.0.0.1", "testsuite", {
      from: "test@#{domain.name}",
      to: "test@example.com",
      subject: "Test HTML Message",
      html_body: "<p><a href=\"http://github.com/atech/postal?a=1&amp;b=2\">Postal</a></p>"
    })
    message = server.message_db.message(prototype.create_message("test@example.com")[:id])
    create(:track_domain, server: server, domain: message.domain, track_loads: false)
    parser = Postal::MessageParser.new(message)
    expect(parser.tracked_links).to eq 1
    expect(parser.new_body).to match(/href='https:\/\/click\.#{message.domain.name}\/#{server.token}\/[A-Za-z0-9]{16}'/)
    links = server.message_db.select(:links, where: { message_id: message.id })
    expect(links.map { |l| l["url"] }).to eq ["http://github.com/atech/postal?a=1&b=2"]
  end
end
