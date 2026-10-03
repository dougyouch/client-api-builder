# frozen_string_literal: true

module ClientApiBuilder
  # A route's query: and body: values are compiled into the source of the generated method,
  # so only values that value_to_code can write back as equal Ruby literals are allowed.
  # Anything computed per request belongs in a symbol argument or a '{method}' placeholder.
  module RouteValueValidator
    LITERAL_CLASSES = [String, Integer, TrueClass, FalseClass, NilClass].freeze
    ARGUMENT_NAME = /\A[a-z_][a-z0-9_]*\z/i

    module_function

    # Raises ArgumentError naming the route for the first value that can't be compiled
    def validate!(route_name, location, value)
      case value
      when Hash
        value.each do |key, item|
          validate_key!(route_name, location, key)
          validate!(route_name, location, item)
        end
      when Array
        value.each { |item| validate!(route_name, location, item) }
      when Symbol
        validate_argument_name!(route_name, location, value)
      else
        raise ArgumentError, unsupported_value_message(route_name, location, value) unless literal?(value)
      end
    end

    def validate_key!(route_name, location, key)
      return if key.is_a?(Symbol) || literal?(key)

      raise ArgumentError, unsupported_value_message(route_name, location, key)
    end

    # Symbol values become keyword arguments of the generated method
    def validate_argument_name!(route_name, location, name)
      return if name.to_s.match?(ARGUMENT_NAME)

      raise ArgumentError,
            "route #{route_name.inspect}: #{location} argument #{name.inspect} is not a valid argument name"
    end

    def literal?(value)
      LITERAL_CLASSES.any? { |klass| value.is_a?(klass) } || (value.is_a?(Float) && value.finite?)
    end

    def unsupported_value_message(route_name, location, value)
      "route #{route_name.inspect}: #{location} value #{value.inspect} (#{value.class}) can't be written into " \
        "the generated method; use a String, number, boolean, nil, Hash or Array, or a '{method}' placeholder " \
        'to compute it per request'
    end
  end
end
