# frozen_string_literal: true

module ClientApiBuilder
  class Error < StandardError; end
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
  autoload :NestedRouter, 'client_api_builder/nested_router'
  autoload :QueryParams, 'client_api_builder/query_params'
  autoload :Router, 'client_api_builder/router'
  autoload :Section, 'client_api_builder/section'

  module NetHTTP
    autoload :Request, 'client_api_builder/net_http_request'
  end
end
