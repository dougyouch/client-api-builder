# frozen_string_literal: true

module ClientApiBuilder
  module HTTP2
    # A client class's HTTP/2 connections: one per host, port and connection options, opened on
    # first use and replaced once it stops taking new streams. Origins whose server chose
    # HTTP/1.1 are remembered so they aren't asked again. After a fork the child starts empty;
    # the parent's connections are dropped without being closed, since closing a shared TLS
    # socket would disturb the parent.
    class ConnectionSet
      def initialize
        reset
      end

      # Returns an open connection to the URI's origin, or nil when the server speaks only HTTP/1.1.
      # A new connection is opened while holding the set's lock, so other origins wait for it.
      def connection_for(uri, connection_options)
        reset if forked?
        key = [uri.hostname, uri.port, connection_options.dup.freeze].freeze
        @mutex.synchronize do
          return nil if @http1_origins.include?(key)

          connection = @connections[key]
          connection&.open? ? connection : open_connection(key, uri, connection_options)
        end
      end

      def close
        connections = @mutex.synchronize do
          @http1_origins.clear
          @connections.values.tap { @connections.clear }
        end
        connections.each(&:close)
      end

      private

      def reset
        @pid = Process.pid
        @mutex = Mutex.new
        @connections = {}
        @http1_origins = Set.new
      end

      def forked?
        @pid != Process.pid
      end

      def open_connection(key, uri, connection_options)
        connection = Connection.open(uri.hostname, uri.port, authority(uri), connection_options)
        connection ? @connections[key] = connection : @http1_origins << key
        connection
      end

      # host keeps an IPv6 address's brackets; the port is left out when it's the default
      def authority(uri)
        uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}"
      end
    end
  end
end
