# frozen_string_literal: true

require_relative 'client_api_builder/version'

module ClientApiBuilder
  class Error < StandardError; end

  # Raised by a transport when a request failed in a way that is safe to send again, e.g. the
  # server refused it before processing it. Router#retry_request? retries these.
  class RetryableError < Error; end

  class UnexpectedResponse < Error
    attr_reader :response

    def initialize(msg, response)
      super(msg)
      @response = response
    end
  end

  class << self
    attr_accessor :logger
  end

  autoload :ActiveSupportNotifications, 'client_api_builder/active_support_notifications'
  autoload :ActiveSupportLogSubscriber, 'client_api_builder/active_support_log_subscriber'
  autoload :ConnectionPools, 'client_api_builder/connection_pools'
  autoload :HTTP2, 'client_api_builder/http2'
  autoload :NestedRouter, 'client_api_builder/nested_router'
  autoload :QueryParams, 'client_api_builder/query_params'
  autoload :RouteValueValidator, 'client_api_builder/route_value_validator'
  autoload :Router, 'client_api_builder/router'
  autoload :Section, 'client_api_builder/section'

  module NetHTTP
    autoload :Request, 'client_api_builder/net_http_request'
  end
end
