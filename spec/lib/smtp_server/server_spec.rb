# frozen_string_literal: true

require "rails_helper"

module SMTPServer

  describe Server do
    include ProcessHelpers

    describe "running script/smtp_server.rb" do
      let(:port) { free_port }
      let(:health_server_port) { free_port }

      it "boots, serves a client and shuts down on TERM" do
        env = { "BIND_ADDRESS" => "127.0.0.1", "PORT" => port, "HEALTH_SERVER_PORT" => health_server_port }
        run_script("script/smtp_server.rb", env) do |pid, output|
          socket = connect_when_listening(port)
          expect(socket.gets).to match(/\A220 #{Regexp.escape(Postal::Config.postal.smtp_hostname)} ESMTP Postal\/\S+\r\n\z/)
          socket.write("QUIT\r\n")
          expect(socket.gets).to eq "221 Closing Connection\r\n"
          socket.close

          response = health_check(health_server_port)
          expect(response).to start_with("HTTP/1.1 200 OK")
          expect(response).to end_with("OK")

          status = terminate_process(pid)
          expect(status.exitstatus).to eq 0
          expect(output.read).to include("Received TERM signal, shutting down.")
        end
      end
    end
  end

end
