# frozen_string_literal: true

require 'net/http'
require 'socket'
require 'securerandom'

# Hermetic WEBrick boot shared by the web server / assets specs:
# points the Config singleton at the given tmpdir project, constructs
# Router + Server with port: 0 (Server resolves the ephemeral port up
# front), starts the blocking run loop on a worker thread, waits until
# the loopback socket actually accepts, and yields a handle with the
# bound port and the launch token. Loopback-only; shutdown + Config
# restore in ensure so no example leaks a listener or project_dir.
module WebServerBoot
  Handle = Struct.new(:port, :token, :server, keyword_init: true)

  def self.with_server(project_dir:, assets: nil, read_models: {}, events: nil)
    previous = SPMCache::Core::Config.instance.project_dir
    SPMCache::Core::Config.configure(project_dir: project_dir)
    token = SecureRandom.hex(32)
    router_kwargs = { token: token, port: 0, assets: assets, read_models: read_models }
    router_kwargs[:events] = events if events
    router = SPMCache::Web::Router.new(**router_kwargs)
    server = SPMCache::Web::Server.new(port: 0, token: token, router: router)
    thread = Thread.new { server.start }
    begin
      wait_accepting(server.port)
      yield Handle.new(port: server.port, token: token, server: server)
    ensure
      shutdown(server)
      thread&.join(10)
      SPMCache::Core::Config.configure(project_dir: previous)
    end
  end

  # SSE rows (14-01): Net::HTTP CANNOT be used against /api/events -- the
  # stream never ends, so a full-body read would block forever. Raw
  # loopback sockets instead: hand-written GET with explicit Host +
  # Connection: close, bounded reads (raw_read_until), close in ensure
  # (wait_accepting idiom). The events: kwarg above injects the Router's
  # SSE collaborator (short poll/heartbeat for bounded specs); forwarded
  # only when present so routers without the kwarg keep working.
  def self.raw_stream_open(handle, path, headers = {})
    sock = TCPSocket.new('127.0.0.1', handle.port)
    lines = ["GET #{path} HTTP/1.1", "Host: 127.0.0.1:#{handle.port}"]
    headers.each { |name, value| lines << "#{name}: #{value}" }
    lines << 'Connection: close'
    sock.write("#{lines.join("\r\n")}\r\n\r\n")
    sock
  end

  # Bounded accumulate-until-match over the raw byte stream (chunked
  # framing included: each SSE frame is one WEBrick chunk, so frame bytes
  # are contiguous and pattern search is unambiguous). Raises on the
  # deadline or on EOF-before-match -- never blocks unbounded.
  def self.raw_read_until(sock, pattern, timeout:)
    deadline = Time.now + timeout
    buffer = +''
    loop do
      return buffer if pattern.is_a?(Regexp) ? buffer.match?(pattern) : buffer.include?(pattern)

      raise Timeout::Error, "pattern #{pattern.inspect} not received within #{timeout}s" if Time.now >= deadline

      readable = IO.select([sock], nil, nil, deadline - Time.now)
      raise Timeout::Error, "pattern #{pattern.inspect} not received within #{timeout}s" unless readable

      buffer << sock.read_nonblock(65_536)
    end
  rescue EOFError
    raise EOFError, "stream closed before #{pattern.inspect} matched (got: #{buffer.bytesize} bytes)"
  rescue IO::WaitReadable
    retry
  end

  def self.raw_close(sock)
    sock&.close
  rescue IOError, Errno::EBADF
    nil
  end

  def self.shutdown(server)
    server&.shutdown
  rescue StandardError
    nil
  end

  # Bounded readiness poll: the WEBrick accept loop answers on the
  # loopback before any request example runs (research CP12
  # health-before-open posture, applied to the specs themselves).
  def self.wait_accepting(port)
    deadline = Time.now + 5
    loop do
      TCPSocket.new('127.0.0.1', port).close
      return
    rescue SystemCallError
      raise "server never accepted connections on 127.0.0.1:#{port}" if Time.now > deadline

      sleep 0.02
    end
  end

  # One-shot GET with arbitrary headers. Net::HTTP passes an explicitly
  # set Host header through verbatim (machine-probed), so the DNS-rebinding
  # rows of the matrix use real spoofed Hosts, not the dial address.
  def self.http_get(handle, path, headers = {})
    request(handle, Net::HTTP::Get.new(path), headers)
  end

  def self.http_post(handle, path, headers = {})
    request(handle, Net::HTTP::Post.new(path), headers)
  end

  def self.request(handle, req, headers)
    Net::HTTP.start('127.0.0.1', handle.port) do |http|
      headers.each { |k, v| req[k] = v }
      http.request(req)
    end
  end
end
