# frozen_string_literal: true

# Purpose: to nest routers, which are sub sections of APIs
# for example if you had an entire section of your API dedicatd to user management.
# you may want to nest all calls to those routes under the user section
# ex: client.users.get_user(id: 1) # where users is a nested router
module ClientApiBuilder
  class NestedRouter
    include ::ClientApiBuilder::Router

    # Root client settings a section can opt into with inherit: or inherit_from_root
    INHERITABLE_SETTINGS = %i[headers query_params connection_options].freeze

    attr_reader :root_router,
                :nested_router_options

    def initialize(root_router, nested_router_options)
      @root_router = root_router
      @nested_router_options = nested_router_options
    end

    def self.get_instance_method(var)
      "\#{escape_path(root_router.#{var})}"
    end

    # The root client settings this section uses beneath its own; none by default
    def self.inherited_root_settings
      [].freeze
    end

    # Opts this section into the root client's class-level headers, query params and/or
    # connection options. They are read per request and the section's own values take precedence.
    def self.inherit_from_root(*settings)
      settings = normalize_inherited_settings(settings)
      redefine_class_method(:inherited_root_settings, (inherited_root_settings | settings).freeze)
    end

    def self.normalize_inherited_settings(settings)
      settings = settings.flatten.map(&:to_sym)
      unknown = settings - INHERITABLE_SETTINGS
      return settings if unknown.empty?

      raise ArgumentError, "Unknown inherit setting(s): #{unknown.map(&:inspect).join(', ')}. " \
                           "Allowed: #{INHERITABLE_SETTINGS.map(&:inspect).join(', ')}"
    end

    def configured_headers
      inherits_from_root?(:headers) ? root_router.configured_headers.merge(super) : super
    end

    def configured_query_params
      inherits_from_root?(:query_params) ? root_router.configured_query_params.merge(super) : super
    end

    def configured_connection_options
      inherits_from_root?(:connection_options) ? root_router.configured_connection_options.merge(super) : super
    end

    def base_url
      self.class.base_url || root_router.base_url
    end

    def handle_response(response, options, &)
      root_router.handle_response(response, options, &)
    end

    # Uses the root client's connections, so a client's sections share its connection pools
    def with_http_connection(uri, connection_options, &)
      root_router.with_http_connection(uri, connection_options, &)
    end

    private

    def inherits_from_root?(setting)
      self.class.inherited_root_settings.include?(setting)
    end
  end
end
