# frozen_string_literal: true

module ClientApiBuilder
  module Transports
    # Persistent connections dedicated to each thread: one per scheme, host, port and
    # connection options, opened on the thread's first request. Takes the
    # ThreadConnections::Settings options (ttl, idle_timeout). Suits a fixed set of worker
    # threads; with many short-lived threads, prefer Pooled. A connection whose request
    # raised is closed, and after a fork the child opens its own.
    class ThreadLocal
      attr_reader :connection_set

      def initialize(**settings)
        @connection_set = ThreadConnections::ConnectionSet.new(ThreadConnections::Settings.new(**settings))
      end

      def settings
        connection_set.settings
      end

      def with_connection(uri, connection_options, &)
        connection_set.with_connection(uri, connection_options, &)
      end

      # Closes every thread's idle connections now and in-use ones when their request ends
      def close
        connection_set.close
      end
    end
  end
end
