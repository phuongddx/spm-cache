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

  def self.with_server(project_dir:, assets: nil, read_models: {})
    previous = SPMCache::Core::Config.instance.project_dir
    SPMCache::Core::Config.configure(project_dir: project_dir)
    token = SecureRandom.hex(32)
    router = SPMCache::Web::Router.new(token: token, port: 0, assets: assets, read_models: read_models)
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
