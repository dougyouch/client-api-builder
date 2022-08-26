# frozen_string_literal: true

# Purpose: to nest routers, which are sub sections of APIs
# for example if you had an entire section of your API dedicatd to user management.
# you may want to nest all calls to those routes under the user section
# ex: client.users.get_user(id: 1) # where users is a nested router
module ClientApiBuilder
  class NestedRouter
    include ::ClientApiBuilder::Router

    attr_reader :root_router,
                :nested_router_options

    def initialize(root_router, nested_router_options)
      @root_router = root_router
      @nested_router_options = nested_router_options
    end

    def self.get_instance_method(var)
      "\#{root_router.#{var}\}"
    end

    def request(**options, &block)
      root_router.request(**options, &block)
    end

    def stream(**options, &block)
      root_router.stream(**options, &block)
    end

    def stream_to_io(**options, &block)
      root_router.stream_to_io(**options, &block)
    end

    def stream_to_file(**options, &block)
      root_router.stream_to_file(**options, &block)
    end

    def base_url
      self.class.base_url || root_router.base_url
    end

    def build_headers(options)
      headers = nested_router_options[:ignore_headers] ? {} : root_router.build_headers(options)

      add_header_proc = proc do |name, value|
        headers[name] =
          if value.is_a?(Proc)
            root_router.instance_eval(&value)
          elsif value.is_a?(Symbol)
            root_router.send(value)
          else
            value
          end
      end

      self.class.default_headers.each(&add_header_proc)

      headers
    end

    def build_connection_options(options)
      root_router.build_connection_options(options)
    end

    def build_query(query, options)
      return nil if query.nil? && root_router.class.default_query_params.empty? && self.class.default_query_params.empty?
      return nil if nested_router_options[:ignore_query] && query.nil? && self.class.default_query_params.empty?

      query_params = {}

      add_query_param_proc = proc do |name, value|
        query_params[name] =
          if value.is_a?(Proc)
            root_router.instance_eval(&value)
          elsif value.is_a?(Symbol)
            root_router.send(value)
          else
            value
          end
      end

      root_router.class.default_query_params.each(&add_query_param_proc)
      self.class.default_query_params.each(&add_query_param_proc)
      query && query.each(&add_query_param_proc)
      options[:query] && options[:query].each(&add_query_param_proc)

      self.class.build_query(self, query_params)
    end

    def build_body(body, options)
      root_router.build_body(body, options)
    end

    def expected_response_code!(response, expected_response_codes, options)
      root_router.expected_response_code!(response, expected_response_codes, options)
    end

    def handle_response(response, options, &block)
      root_router.handle_response(response, options, &block)
    end

    def escape_path(path)
      root_router.escape_path(path)
    end

    def retry_request?(exception)
      root_router.retry_request?(exception)
    end
  end
end
