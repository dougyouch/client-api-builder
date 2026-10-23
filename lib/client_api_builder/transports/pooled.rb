# frozen_string_literal: true

module ClientApiBuilder
  module Transports
    # Persistent connections shared by every thread, checked out of a pool per scheme, host,
    # port and connection options for the length of one request. Takes the
    # ConnectionPools::Settings options (max_connections, ttl, checkout_timeout, idle_timeout).
    # A connection whose request raised is closed, and after a fork the child opens its own.
    class Pooled
      attr_reader :pool_set

      def initialize(**settings)
        @pool_set = ConnectionPools::PoolSet.new(ConnectionPools::Settings.new(**settings))
      end

      def settings
        pool_set.settings
      end

      def with_connection(uri, connection_options, &)
        pool_set.with_connection(uri, connection_options, &)
      end

      # Closes idle connections now and in-use ones when they're returned
      def close
        pool_set.close
      end
    end
  end
end
