# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'resolv'
require 'socket'

module ClientApiBuilder
  module HTTP2
    # Opens a TLS connection that offers h2 and http/1.1 through ALPN, applying Net::HTTP's
    # SSL connection options and certificate checks. The caller reads alpn_protocol to see
    # which one the server chose.
    module TLSSocket
      ALPN_PROTOCOLS = %w[h2 http/1.1].freeze

      # Net::HTTP connection option => SSLContext attribute
      SSL_OPTIONS = %i[
        ca_file ca_path cert cert_store ciphers extra_chain_cert key min_version max_version
        ssl_version verify_callback verify_depth verify_hostname verify_mode
      ].to_h { |name| [name, name] }.merge(ssl_timeout: :timeout).freeze

      WAIT_EVENTS = { wait_readable: IO::READABLE, wait_writable: IO::WRITABLE }.freeze

      module_function

      def open(host, port, connection_options)
        context = ssl_context(connection_options)
        tcp = Socket.tcp(host, port, connect_timeout: connection_options[:open_timeout])
        begin
          ssl = start_tls(tcp, host, context, connection_options[:open_timeout])
          ssl.post_connection_check(host) if verify_hostname?(context)
          ssl
        rescue StandardError
          tcp.close
          raise
        end
      end

      def ssl_context(connection_options)
        params = SSL_OPTIONS.filter_map do |option, attribute|
          [attribute, connection_options[option]] unless connection_options[option].nil?
        end
        OpenSSL::SSL::SSLContext.new.tap do |context|
          context.set_params(params.to_h)
          context.alpn_protocols = ALPN_PROTOCOLS
        end
      end

      def start_tls(tcp, host, context, timeout)
        ssl = OpenSSL::SSL::SSLSocket.new(tcp, context)
        ssl.sync_close = true
        ssl.hostname = host unless ip_address?(host)
        handshake(ssl, timeout && (now + timeout))
        ssl
      end

      def handshake(ssl, deadline)
        while (state = ssl.connect_nonblock(exception: false)).is_a?(Symbol)
          remaining = deadline && (deadline - now)
          next if ssl.to_io.wait(WAIT_EVENTS.fetch(state), remaining)

          raise Net::OpenTimeout, 'TLS handshake timed out'
        end
      end

      # Same rule as Net::HTTP: the certificate must match the host unless verification is off
      def verify_hostname?(context)
        context.verify_mode != OpenSSL::SSL::VERIFY_NONE && context.verify_hostname != false
      end

      def ip_address?(host)
        host.match?(Resolv::IPv4::Regex) || host.match?(Resolv::IPv6::Regex)
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
