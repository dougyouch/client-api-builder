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

    def handle_response(response, options, &block)
      root_router.handle_response(response, options, &block)
    end
  end
end
