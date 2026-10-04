# frozen_string_literal: true

module ClientApiBuilder
  module ConnectionPools
    # A client class's pools: one per scheme, host, port and connection options, created on
    # first use. After a fork the child starts with no pools; the parent's connections are
    # dropped without being closed, since closing a shared TLS socket would disturb the parent.
    class PoolSet
      attr_reader :settings

      def initialize(settings)
        @settings = settings
        reset
      end

      def with_connection(uri, connection_options, &)
        pool_for(uri, connection_options).with_connection(&)
      end

      def pool_for(uri, connection_options)
        reset if forked?
        key = [uri.scheme, uri.hostname, uri.port, connection_options.dup.freeze].freeze
        @mutex.synchronize { @pools[key] ||= build_pool(uri, connection_options) }
      end

      def pools
        @mutex.synchronize { @pools.values }
      end

      def close
        pools.each(&:close)
      end

      private

      def reset
        @pid = Process.pid
        @mutex = Mutex.new
        @pools = {}
      end

      def forked?
        @pid != Process.pid
      end

      def build_pool(uri, connection_options)
        Pool.new(host: uri.hostname, port: uri.port, settings: settings,
                 connection_options: { keep_alive_timeout: settings.idle_timeout }.merge(connection_options))
      end
    end
  end
end
