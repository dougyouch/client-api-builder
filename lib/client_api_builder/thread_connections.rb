# frozen_string_literal: true

# Purpose: opt-in persistent HTTP connections dedicated to each thread. Include after
# ClientApiBuilder::Router, instead of ClientApiBuilder::ConnectionPools:
#
#   class MyClient
#     include ClientApiBuilder::Router
#     include ClientApiBuilder::ThreadConnections
#
#     connection_per_thread ttl: 60
#   end
#
# Each thread opens its own connection per host on its first request and reuses it for its
# later ones, so there's no pool size to match to the thread count and no waiting for a
# connection to free up.
module ClientApiBuilder
  module ThreadConnections
    autoload :ConnectionSet, 'client_api_builder/thread_connections/connection_set'
    autoload :Settings, 'client_api_builder/thread_connections/settings'

    def self.included(base)
      unless base.include?(::ClientApiBuilder::Router)
        raise ArgumentError, 'include ClientApiBuilder::Router before ClientApiBuilder::ThreadConnections'
      end
      if base.include?(::ClientApiBuilder::ConnectionPools)
        raise ArgumentError, 'include either ClientApiBuilder::ConnectionPools or ClientApiBuilder::ThreadConnections'
      end
      # HTTP2 falls back to these connections through super, so it must come after them
      if base.ancestors.any? { |mod| mod.name == 'ClientApiBuilder::HTTP2' }
        raise ArgumentError, 'include ClientApiBuilder::ThreadConnections before ClientApiBuilder::HTTP2'
      end

      base.extend ClassMethods
      base.connection_per_thread
    end

    module ClassMethods
      # Configures this class's per-thread connections, replacing any it already had.
      # Subclasses share their parent's unless they call connection_per_thread themselves.
      def connection_per_thread(**settings)
        redefine_class_method(:thread_connections, ConnectionSet.new(Settings.new(**settings)))
      end

      # Closes every thread's idle connections now and in-use ones when their request ends,
      # including those of sections that have their own
      def close_connections
        thread_connections.close
        section_routers.each_value(&:close_connections)
      end
    end

    def with_http_connection(uri, connection_options, &)
      self.class.thread_connections.with_connection(uri, connection_options, &)
    end
  end
end
