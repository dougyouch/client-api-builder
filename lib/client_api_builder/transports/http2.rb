# frozen_string_literal: true

module ClientApiBuilder
  module Transports
    # HTTP/2 for https, one connection per origin and connection options carrying concurrent
    # requests as streams (needs the http-2 gem). http URLs, and origins whose server chose
    # HTTP/1.1 during the TLS handshake, go through the fallback transport.
    #
    # connections: shares the HTTP/2 connections of another transport (see with_fallback).
    class HTTP2
      attr_reader :fallback, :connections

      def initialize(fallback: OneShot.new, connections: nil)
        ::ClientApiBuilder::HTTP2.require_http2_gem
        @fallback = fallback
        @connections = connections || ::ClientApiBuilder::HTTP2::ConnectionSet.new
      end

      # A transport over the same HTTP/2 connections with a different fallback
      def with_fallback(fallback)
        self.class.new(fallback: fallback, connections: connections)
      end

      def with_connection(uri, connection_options, &)
        connection = uri.scheme == 'https' && connections.connection_for(uri, connection_options)
        connection ? yield(connection) : fallback.with_connection(uri, connection_options, &)
      end

      # Closes the HTTP/2 connections and the fallback's
      def close
        connections.close
        fallback.close
      end
    end
  end
end
