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

  autoload :Router, 'client_api_builder/router'
  autoload :QueryParams, 'client_api_builder/query_params'

  module NetHTTP
    autoload :Request, 'client_api_builder/net_http_request'
  end
end
