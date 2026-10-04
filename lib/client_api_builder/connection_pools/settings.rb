# frozen_string_literal: true

module ClientApiBuilder
  module ConnectionPools
    # max_connections:  connections per host, in use or idle
    # ttl:              seconds a connection may live before it's closed and replaced
    # checkout_timeout: seconds a thread waits for a free connection before TimeoutError
    # idle_timeout:     seconds a connection may sit unused before Net::HTTP reconnects it
    #                   (Net::HTTP's keep_alive_timeout; a connection option overrides it)
    Settings = Data.define(:max_connections, :ttl, :checkout_timeout, :idle_timeout) do
      def initialize(max_connections: 5, ttl: 30, checkout_timeout: 5, idle_timeout: 2)
        validate_max_connections!(max_connections)
        { ttl: ttl, checkout_timeout: checkout_timeout, idle_timeout: idle_timeout }.each do |name, value|
          validate_seconds!(name, value)
        end
        super
      end

      private

      def validate_max_connections!(value)
        return if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "max_connections must be a positive Integer, got #{value.inspect}"
      end

      def validate_seconds!(name, value)
        return if value.is_a?(Numeric) && value.positive?

        raise ArgumentError, "#{name} must be a positive number of seconds, got #{value.inspect}"
      end
    end
  end
end
