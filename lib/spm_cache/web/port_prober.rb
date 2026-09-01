# frozen_string_literal: true

require 'socket'
module SPMCache
  module Web
    # Bounded upward port probe for `spm-cache web` (WEB-01). macOS
    # AirPlay's ControlCenter holds TCP 5000 and 7000 (research CP9,
    # machine-probed) -- and thanks to its SO_REUSEADDR posture those
    # ports can even appear bindable while unusable -- so they are
    # skipped UNCONDITIONALLY, regardless of start_port.
    class PortProber
      SKIP_PORTS = [5000, 7000].freeze
      DEFAULT_START_PORT = 7915
      DEFAULT_ATTEMPTS = 25

      class << self
        def pick(host: '127.0.0.1', start_port: DEFAULT_START_PORT, attempts: DEFAULT_ATTEMPTS)
          candidate = start_port
          attempts.times do
            unless SKIP_PORTS.include?(candidate)
              server = bind(host, candidate)
              if server
                # addr[1] is the actually-bound port (start_port 0 probes
                # ephemeral); close BEFORE returning so the caller can
                # rebind the port (WEBrick binds it next).
                port = server.addr[1]
                server.close
                return port
              end
            end
            candidate += 1
          end
          raise Core::GeneralError,
                "no available port for spm-cache web in [#{start_port}, #{start_port + attempts}) " \
                '(skipping AirPlay 5000/7000)'
        end

        private

        def bind(host, port)
          TCPServer.new(host, port)
        rescue Errno::EADDRINUSE
          nil
        end
      end
    end
  end
end
