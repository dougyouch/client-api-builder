# frozen_string_literal: true

module ClientApiBuilder
  module ThreadConnections
    # ttl:          seconds a connection may live before it's closed and replaced
    # idle_timeout: seconds a connection may sit unused before Net::HTTP reconnects it
    #               (Net::HTTP's keep_alive_timeout; a connection option overrides it)
    Settings = Data.define(:ttl, :idle_timeout) do
      def initialize(ttl: 30, idle_timeout: 2)
        { ttl: ttl, idle_timeout: idle_timeout }.each do |name, value|
          next if value.is_a?(Numeric) && value.positive?

          raise ArgumentError, "#{name} must be a positive number of seconds, got #{value.inspect}"
        end
        super
      end
    end
  end
end
