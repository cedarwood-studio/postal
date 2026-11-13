# frozen_string_literal: true

require "socket"
require "tempfile"
require "timeout"

module ProcessHelpers

  # Run one of the scripts in script/ as a child process for the duration of
  # the block. The child is killed if it is still running when the block ends.
  def run_script(script, env = {})
    output = Tempfile.new("postal-process")
    pid = Process.spawn(env.transform_values(&:to_s), "bundle", "exec", "ruby", script,
                        chdir: Rails.root.to_s, out: output.path, err: [:child, :out])
    yield pid, output
  ensure
    kill_process(pid) if pid
    output&.close!
  end

  def kill_process(pid)
    return unless Process.waitpid(pid, Process::WNOHANG).nil?

    Process.kill("KILL", pid)
    Process.wait(pid)
  rescue Errno::ECHILD
    # The process has already exited and been waited for.
  end

  # Send TERM to the process and return its exit status
  def terminate_process(pid, timeout: 30)
    Process.kill("TERM", pid)
    Timeout.timeout(timeout) { Process.wait2(pid).last }
  end

  def free_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end

  def wait_until(timeout: 60, interval: 0.2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      result = yield
      return result if result
      raise "timed out after #{timeout} seconds" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep interval
    end
  end

  def connect_when_listening(port, **options)
    wait_until(**options) do
      TCPSocket.new("127.0.0.1", port)
    rescue Errno::ECONNREFUSED
      nil
    end
  end

  def health_check(port, **options)
    socket = connect_when_listening(port, **options)
    socket.write("GET /health HTTP/1.0\r\n\r\n")
    socket.read
  ensure
    socket&.close
  end

end
