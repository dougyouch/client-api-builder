# frozen_string_literal: true

require 'active_support'

# Purpose is to log all requests
module ClientApiBuilder
  class ActiveSupportLogSubscriber
    attr_reader :logger

    def initialize(logger)
      @logger = logger
    end

    def subscribe!
      ActiveSupport::Notifications.subscribe('client_api_builder.request') do |event|
        logger.info(generate_log_message(event))
      end
    end

    # request_options is nil when the request failed before it was built,
    # and response is nil when no response was received.
    # Failed requests end with the exception, e.g. "(Net::OpenTimeout: execution expired)".
    def generate_log_message(event)
      client = event.payload[:client]
      request_options = client.request_options
      response_code = client.response ? client.response.code : 'UNKNOWN'

      message = "#{request_description(request_options)}[#{response_code}] took #{event.duration.to_i}ms"
      exception = event.payload[:exception]
      exception ? "#{message} (#{exception.join(': ')})" : message
    end

    private

    def request_description(request_options)
      return '[request not built]' unless request_options

      method = request_options[:method].to_s.upcase
      uri = request_options[:uri]
      uri ? "#{method} #{uri.scheme}://#{uri.host}#{uri.path}" : "#{method} [no URI]"
    end
  end
end
