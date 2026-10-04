# frozen_string_literal: true

module ClientApiBuilder
  module ConnectionPools
    # Thread-safe pool of connections to one host, sharing one set of connection options.
    # Connections are opened on demand up to max_connections and reused most recently used
    # first. One that outlives the ttl is closed when it's next checked out or returned, and
    # one whose request raised is closed rather than reused.
    class Pool
      MONOTONIC_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      attr_reader :host, :port, :settings

      def initialize(host:, port:, connection_options:, settings:, clock: MONOTONIC_CLOCK)
        @host = host
        @port = port
        @connection_options = connection_options
        @settings = settings
        @clock = clock
        @mutex = Mutex.new
        @available = ConditionVariable.new
        @idle = []
        @size = 0
        @closed_at = nil
      end

      # Yields a connection's Net::HTTP session and returns the block's result
      def with_connection
        connection = checkout
        returned = false
        begin
          result = yield connection.http
          checkin(connection)
          returned = true
          result
        ensure
          discard(connection) unless returned
        end
      end

      # Closes idle connections now; connections in use are closed when they're returned
      def close
        idle = @mutex.synchronize do
          @closed_at = now
          @size -= @idle.size
          @available.broadcast
          @idle.slice!(0..)
        end
        idle.each(&:close)
      end

      # Open connections, idle or in use
      def size
        @mutex.synchronize { @size }
      end

      def idle_size
        @mutex.synchronize { @idle.size }
      end

      private

      def now
        @clock.call
      end

      def checkout
        reuse_or_reserve(now + settings.checkout_timeout) || open_connection
      end

      # Returns an idle connection, or nil once a slot is reserved for a new one.
      # Expired idle connections are closed after the lock is released.
      def reuse_or_reserve(deadline)
        expired = []
        @mutex.synchronize do
          loop do
            connection = take_idle(expired)
            return connection if connection
            return nil if reserve_slot?

            wait_for_connection(deadline)
          end
        end
      ensure
        expired.each(&:close)
      end

      def take_idle(expired)
        while (connection = @idle.pop)
          return connection unless retire?(connection)

          @size -= 1
          expired << connection
        end
      end

      def reserve_slot?
        return false if @size >= settings.max_connections

        @size += 1
        true
      end

      def wait_for_connection(deadline)
        remaining = deadline - now
        unless remaining.positive?
          raise TimeoutError, "no connection to #{host}:#{port} became available within " \
                              "#{settings.checkout_timeout}s (max_connections: #{settings.max_connections})"
        end

        @available.wait(@mutex, remaining)
      end

      def open_connection
        connection = nil
        connection = Connection.open(host, port, @connection_options, now)
      ensure
        release_slot unless connection
      end

      def checkin(connection)
        connection.used(now)
        retired = @mutex.synchronize do
          retire = retire?(connection)
          retire ? @size -= 1 : @idle.push(connection)
          @available.signal
          retire
        end
        connection.close if retired
      end

      def discard(connection)
        release_slot
        connection.close
      end

      def release_slot
        @mutex.synchronize do
          @size -= 1
          @available.signal
        end
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
