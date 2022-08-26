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

    def generate_log_message(event)
      client = event.payload[:client]
      method = client.request_options[:method].to_s.upcase
      uri = client.request_options[:uri]
      response = client.response
      response_code = response ? response.code : 'UNKNOWN'

      "#{method} #{uri.scheme}://#{uri.host}#{uri.path}[#{response_code}] took #{event.duration.to_i}ms"
    end
  end
end
