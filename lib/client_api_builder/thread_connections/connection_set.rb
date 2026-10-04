# frozen_string_literal: true

module ClientApiBuilder
  module ThreadConnections
    # A client class's connections, kept per thread: one per scheme, host, port and connection
    # options, opened on the thread's first request and reused by its later ones.
    #
    # A connection is taken out of its thread's slot while a request uses it, so a request made
    # before it's back (from a streaming block, or another fiber on the thread) opens one of its
    # own; whichever finishes second is closed rather than kept. A connection that outlives the
    # ttl, was opened before close, or whose request raised is closed instead of reused. The
    # connections of threads that have died are closed when a thread makes its first request.
    # After a fork the child starts with none; the parent's are dropped without being closed,
    # since closing a shared TLS socket would disturb the parent.
    class ConnectionSet
      MONOTONIC_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      attr_reader :settings

      def initialize(settings, clock: MONOTONIC_CLOCK)
        @settings = settings
        @clock = clock
        reset
      end

      # Yields the current thread's Net::HTTP session and returns the block's result
      def with_connection(uri, connection_options)
        key = [uri.scheme, uri.hostname, uri.port, connection_options.dup.freeze].freeze
        connection = checkout(key) || open_connection(uri, connection_options)
        returned = false
        begin
          result = yield connection.http
          checkin(key, connection)
          returned = true
          result
        ensure
          connection.close unless returned
        end
      end

      # Closes idle connections now; connections in use are closed when their request ends
      def close
        idle = @mutex.synchronize do
          @closed_at = now
          remove_threads(@threads.keys)
        end
        idle.each(&:close)
      end

      # Idle connections, across all threads
      def size
        @mutex.synchronize { @threads.each_value.sum(&:size) }
      end

      private

      def reset
        @pid = Process.pid
        @mutex = Mutex.new
        @threads = {}
        @closed_at = nil
      end

      def forked?
        @pid != Process.pid
      end

      def now
        @clock.call
      end

      # Returns the thread's connection for key, or nil when it has none to reuse. Retired
      # connections are closed after the lock is released.
      def checkout(key)
        retired = []
        reset if forked?
        @mutex.synchronize do
          retired.concat(remove_threads(dead_threads)) unless @threads.key?(Thread.current)
          take(key, retired)
        end
      ensure
        retired.each(&:close)
      end

      def take(key, retired)
        connection = @threads[Thread.current]&.delete(key)
        return connection unless connection && retire?(connection)

        retired << connection
        nil
      end

      def open_connection(uri, connection_options)
        ConnectionPools::Connection.open(uri.hostname, uri.port,
                                         { keep_alive_timeout: settings.idle_timeout }.merge(connection_options), now)
      end

      def checkin(key, connection)
        connection.used(now)
        kept = @mutex.synchronize { !retire?(connection) && keep?(key, connection) }
        connection.close unless kept
      end

      # Keeps the connection for the thread's next request, unless a request that ran while
      # this one did has already left one there
      def keep?(key, connection)
        connections = (@threads[Thread.current] ||= {})
        return false if connections.key?(key)

        connections[key] = connection
        true
      end

      def dead_threads
        @threads.keys.reject(&:alive?)
      end

      # Forgets the threads and returns their idle connections
      def remove_threads(threads)
        threads.flat_map { |thread| @threads.delete(thread).values }
      end

      def retire?(connection)
        connection.expired?(settings.ttl, now) || closed_since_opened?(connection)
      end

      def closed_since_opened?(connection)
        !@closed_at.nil? && connection.opened_at <= @closed_at
      end
    end
  end
end
