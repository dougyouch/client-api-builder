# frozen_string_literal: true

# Purpose: opt-in persistent HTTP connections shared by every instance of a client class.
# Include after ClientApiBuilder::Router:
#
#   class MyClient
#     include ClientApiBuilder::Router
#     include ClientApiBuilder::ConnectionPools
#
#     connection_pool max_connections: 10, ttl: 60
#   end
#
# Each thread uses its own client instance; the instances check connections out of the
# class's pools (one pool per host and connection options) for the length of one request.
# The pools are a Transports::Pooled declared as the class's transport, so
# ClientApiBuilder.use_transport can still pick another one for the class at boot.
module ClientApiBuilder
  module ConnectionPools
    autoload :Connection, 'client_api_builder/connection_pools/connection'
    autoload :Pool, 'client_api_builder/connection_pools/pool'
    autoload :PoolSet, 'client_api_builder/connection_pools/pool_set'
    autoload :Settings, 'client_api_builder/connection_pools/settings'

    # Raised when no connection frees up within checkout_timeout
    class TimeoutError < ::ClientApiBuilder::Error; end

    def self.included(base)
      unless base.include?(::ClientApiBuilder::Router)
        raise ArgumentError, 'include ClientApiBuilder::Router before ClientApiBuilder::ConnectionPools'
      end
      if base.include?(::ClientApiBuilder::ThreadConnections)
        raise ArgumentError, 'include either ClientApiBuilder::ConnectionPools or ClientApiBuilder::ThreadConnections'
      end
      # HTTP2 falls back to the pools through super, so it must come after them
      if base.ancestors.any? { |mod| mod.name == 'ClientApiBuilder::HTTP2' }
        raise ArgumentError, 'include ClientApiBuilder::ConnectionPools before ClientApiBuilder::HTTP2'
      end

      base.extend ::ClientApiBuilder::DeclaredTransport
      base.extend ClassMethods
      base.connection_pool
    end

    module ClassMethods
      # Configures this class's pools, replacing any it already had. Subclasses share their
      # parent's pools unless they call connection_pool themselves.
      def connection_pool(**settings)
        redefine_class_method(:http1_transport, ::ClientApiBuilder::Transports::Pooled.new(**settings))
        declare_transport
      end

      def connection_pools
        http1_transport.pool_set
      end

      # Closes idle connections now and in-use ones when they are returned, including the
      # pools of sections that have their own
      def close_connections
        connection_pools.close
        section_routers.each_value(&:close_connections)
      end
    end
  end
end
