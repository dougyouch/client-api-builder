# frozen_string_literal: true

# Purpose: to nest routers, which are sub sections of APIs
# for example if you had an entire section of your API dedicatd to user management.
# you may want to nest all calls to those routes under the user section
# ex: client.users.get_user(id: 1) # where users is a nested router
module ClientApiBuilder
  class NestedRouter
    include ::ClientApiBuilder::Router

    attr_reader :parent_router

    def initialize(parent_router)
      @parent_router = parent_router
    end

    def self.get_instance_method(var)
      "\#{parent_router.#{var}\}"
    end

    def request(**options, &block)
      parent_router.request(**options, &block)
    end

    def stream(**options, &block)
      parent_router.stream(**options, &block)
    end

    def stream_to_io(**options, &block)
      parent_router.stream_to_io(**options, &block)
    end

    def stream_to_file(**options, &block)
      parent_router.stream_to_file(**options, &block)
    end

    def base_url(options)
      self.class.base_url || parent_router.base_url(options)
    end

    def build_headers(options)
      headers = parent_router.build_headers(options)

      add_header_proc = proc do |name, value|
        headers[name] =
          if value.is_a?(Proc)
            parent_router.instance_eval(&value)
          elsif value.is_a?(Symbol)
            parent_router.send(value)
          else
            value
          end
      end

      self.class.headers.each(&add_header_proc)

      headers
    end

    def build_connection_options(options)
      parent_router.build_connection_options(options)
    end

    def build_query(query, options)
      return nil if query.nil? && parent_router.class.query_params.empty? && self.class.query_params.empty?

      query_params = {}

      add_query_param_proc = proc do |name, value|
        query_params[name] =
          if value.is_a?(Proc)
            parent_router.instance_eval(&value)
          elsif value.is_a?(Symbol)
            parent_router.send(value)
          else
            value
          end
      end

      parent_router.class.query_params.each(&add_query_param_proc)
      self.class.query_params.each(&add_query_param_proc)
      query&.each(&add_query_param_proc)

      self.class.build_query(query_params)
    end

    def build_body(body, options)
      parent_router.build_body(body, options)
    end

    def expected_response_code!(response, expected_response_codes, options)
      parent_router.expected_response_code!(response, expected_response_codes, options)
    end

    def handle_response(response, options, &block)
      parent_router.handle_response(response, options, &block)
    end
  end
end
