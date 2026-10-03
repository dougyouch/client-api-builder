# frozen_string_literal: true

require 'erb'
require 'inheritance-helper'
require 'json'

module ClientApiBuilder
  module Router
    def self.included(base)
      base.extend InheritanceHelper::Methods
      base.extend ClassMethods
      base.include ::ClientApiBuilder::Section
      base.include ::ClientApiBuilder::NetHTTP::Request
      base.include(::ClientApiBuilder::ActiveSupportNotifications) if defined?(ActiveSupport)
      base.send(:attr_reader, :response, :request_options, :total_request_time, :request_attempts)
    end

    module ClassMethods
      REQUIRED_BODY_HTTP_METHODS = %i[
        post
        put
        patch
      ].freeze

      # Allowed URL schemes for base_url to prevent SSRF attacks
      ALLOWED_URL_SCHEMES = %w[http https].freeze

      # Ruby source that value_to_code inserts verbatim into a generated route method
      CodeSnippet = Data.define(:code)

      # '{name}' in a query/body string: a route argument with that name, or else the client's method
      PLACEHOLDER = /\{([a-z0-9_]+)\}/i
      WHOLE_PLACEHOLDER = /\A\{([a-z0-9_]+)\}\z/i

      # ':name' in a route path is an argument unless the colon follows a letter, digit, '_' or '}',
      # so items:batchGet, {name}:cancel and 12:30 stay literal
      PATH_PARAMETER = /(?<![a-z0-9_}]):([a-z_][a-z0-9_]*)/i

      # Deep duplicates hashes and arrays (at any depth) to prevent shared mutable state.
      # Other values are returned as is.
      def deep_dup(value)
        case value
        when Hash then value.transform_values { |v| deep_dup(v) }
        when Array then value.map { |v| deep_dup(v) }
        else value
        end
      end

      def deep_dup_hash(hash)
        deep_dup(hash)
      end

      def default_options
        {
          base_url: nil,
          body_builder: :to_json,
          connection_options: {},
          headers: {},
          query_builder: Hash.method_defined?(:to_query) ? :to_query : :query_params,
          query_params: {},
          response_procs: {},
          max_retries: 1,
          sleep: 0.05
        }.freeze
      end

      # tracks the proc used to handle responses; nil clears it
      def add_response_proc(method_name, proc)
        response_procs = deep_dup_hash(default_options[:response_procs])
        response_procs[method_name] = proc
        add_value_to_class_method(:default_options, response_procs: response_procs)
      end

      # retrieves the proc used to handle the response
      def get_response_proc(method_name)
        default_options[:response_procs][method_name]
      end

      # set/get base url
      # Validates URL scheme to prevent SSRF attacks
      def base_url(url = nil)
        return default_options[:base_url] unless url

        validate_base_url!(url)
        add_value_to_class_method(:default_options, base_url: url)
      end

      # Validates that base_url uses an allowed scheme
      def validate_base_url!(url)
        uri = URI.parse(url.to_s)
        unless ALLOWED_URL_SCHEMES.include?(uri.scheme&.downcase)
          allowed = ALLOWED_URL_SCHEMES.join(', ')
          raise ArgumentError, "Invalid base_url scheme: #{uri.scheme.inspect}. Allowed: #{allowed}"
        end
        raise ArgumentError, "Invalid base_url: #{url.to_s.inspect} has no host" if uri.host.to_s.empty?
      rescue URI::InvalidURIError => e
        raise ArgumentError, "Invalid base_url: #{e.message}"
      end

      # set the builder to :to_json, :to_query, :query_params or specify a proc
      # to handle building the request body payload, or get the body builder
      def body_builder(builder = nil, &block)
        return default_options[:body_builder] if builder.nil? && block.nil?

        add_value_to_class_method(:default_options, body_builder: builder || block)
      end

      # set the builder to :to_query, :query_params or specify a proc to handle building the request query params
      # or get the query builder
      def query_builder(builder = nil, &block)
        return default_options[:query_builder] if builder.nil? && block.nil?

        add_value_to_class_method(:default_options, query_builder: builder || block)
      end

      # add a request header
      def header(name, value = nil, &block)
        headers = deep_dup_hash(default_options[:headers])
        headers[name] = value || block
        add_value_to_class_method(:default_options, headers: headers)
      end

      # set a connection_option, specific to Net::HTTP
      def connection_option(name, value)
        connection_options = deep_dup_hash(default_options[:connection_options])
        connection_options[name] = value
        add_value_to_class_method(:default_options, connection_options: connection_options)
      end

      def configure_retries(max_retries, sleep_time_between_retries_in_seconds = 0.05)
        add_value_to_class_method(
          :default_options,
          max_retries: max_retries,
          sleep: sleep_time_between_retries_in_seconds
        )
      end

      # add a query param to all requests
      def query_param(name, value = nil, &block)
        query_params = deep_dup_hash(default_options[:query_params])
        query_params[name] = value || block
        add_value_to_class_method(:default_options, query_params: query_params)
      end

      # get default headers
      def default_headers
        default_options[:headers]
      end

      # get configured connection_options
      def default_connection_options
        default_options[:connection_options]
      end

      # get default query_params to add to all requests
      def default_query_params
        default_options[:query_params]
      end

      def build_body(router, body)
        case body_builder
        when :to_json
          body.to_json
        when :to_query
          body.to_query
        when :query_params
          ClientApiBuilder::QueryParams.new.to_query(body)
        when Symbol
          router.send(body_builder, body)
        else
          router.instance_exec(body, &body_builder)
        end
      end

      def build_query(router, query)
        case query_builder
        when :to_query
          query.to_query
        when :query_params
          ClientApiBuilder::QueryParams.new.to_query(query)
        when Symbol
          router.send(query_builder, query)
        else
          router.instance_exec(query, &query_builder)
        end
      end

      # The verb must be the whole name or be followed by '_', so create_user is a POST
      # but names such as posts or deleted_users stay GET.
      def auto_detect_http_method(method_name)
        case method_name.to_s
        when /\A(?:post|create|add|insert)(?:_|\z)/i
          :post
        when /\A(?:put|update|modify|change)(?:_|\z)/i
          :put
        when /\Apatch(?:_|\z)/i
          :patch
        when /\A(?:delete|remove|destroy)(?:_|\z)/i
          :delete
        else
          :get
        end
      end

      def requires_body?(http_method, options)
        return !options[:no_body] if options.key?(:no_body)
        return options[:has_body] if options.key?(:has_body)

        REQUIRED_BODY_HTTP_METHODS.include?(http_method)
      end

      # Replaces argument symbols and '{name}' strings in a query/body hash, in place, with
      # CodeSnippets; returns the argument names found
      def get_hash_arguments(hsh)
        arguments = []
        hsh.each { |key, value| hsh[key] = argument_code(value, arguments) }
        arguments
      end

      # Same as get_hash_arguments, for an array
      def get_array_arguments(list)
        arguments = []
        list.each_with_index { |value, idx| list[idx] = argument_code(value, arguments) }
        arguments
      end

      def argument_code(value, arguments)
        case value
        when Symbol
          arguments << value
          CodeSnippet.new(value.to_s)
        when Hash
          arguments.concat(get_hash_arguments(value))
          value
        when Array
          arguments.concat(get_array_arguments(value))
          value
        when String
          string_template_code(value)
        else
          value
        end
      end

      # A string that is exactly '{name}' passes the value through unchanged (keeping its type);
      # placeholders within text are interpolated into the string. Strings without placeholders
      # are returned as is.
      def string_template_code(str)
        return str unless str.match?(PLACEHOLDER)

        whole = str.match(WHOLE_PLACEHOLDER)
        return CodeSnippet.new(whole[1]) if whole

        parts = str.split(/(\{[a-z0-9_]+\})/i).map do |part|
          placeholder = part.match(WHOLE_PLACEHOLDER)
          # inspect escapes quotes, backslashes and '#{' so the text stays literal
          placeholder ? "\#{#{placeholder[1]}}" : part.inspect[1..-2]
        end
        CodeSnippet.new("\"#{parts.join}\"")
      end

      # returns a list of arguments to add to the route method
      def get_arguments(value)
        case value
        when Hash
          get_hash_arguments(value)
        when Array
          get_array_arguments(value)
        else
          []
        end
      end

      def get_instance_method(var)
        "#\{escape_path(#{var})}"
      end

      # Thread-local storage key for namespaces to ensure thread safety
      NAMESPACE_THREAD_KEY = :client_api_builder_namespaces

      def namespaces
        Thread.current[NAMESPACE_THREAD_KEY] ||= []
      end

      # a namespace is a top level path to apply to all routes within the namespace block
      def namespace(name)
        namespaces << name
        yield
      ensure
        # Always pop the namespace, even if an exception occurs during yield
        namespaces.pop
      end

      def process_route_path(path)
        path = namespaces.join + path

        # instance method - use block parameter to avoid thread-unsafe $1
        path = path.gsub(/\{([a-z0-9_]+)\}/i) do |_match|
          get_instance_method(Regexp.last_match(1))
        end

        path_arguments = []
        path = path.gsub(PATH_PARAMETER) do |_match|
          param_name = Regexp.last_match(1)
          path_arguments << param_name
          "#\{escape_path(#{param_name})}"
        end

        [path, path_arguments]
      end

      # Converts a value to Ruby code string with consistent hash syntax across Ruby versions.
      # Uses modern {key: value} syntax for symbol keys.
      def value_to_code(value)
        case value
        when Hash
          return '{}' if value.empty?

          pairs = value.map do |k, v|
            key_code = case k
                       when Symbol then k.match?(RouteValueValidator::ARGUMENT_NAME) ? "#{k}: " : "#{k.inspect} => "
                       when String then "#{k.inspect} => "
                       else "#{value_to_code(k)} => "
                       end
            "#{key_code}#{value_to_code(v)}"
          end
          "{#{pairs.join(', ')}}"
        when Array
          "[#{value.map { |v| value_to_code(v) }.join(', ')}]"
        when NilClass
          'nil'
        when TrueClass, FalseClass
          value.to_s
        when CodeSnippet
          value.code
        else
          value.inspect
        end
      end

      # get_arguments rewrites values in place, so work on a copy of the caller's query/body
      def build_query_code(options)
        if options[:query]
          query = deep_dup(options[:query])
          query_arguments = get_arguments(query)
          [value_to_code(query), query_arguments.map(&:to_s)]
        else
          ['nil', []]
        end
      end

      def build_body_code(options, has_body_param)
        if options[:body]
          body = deep_dup(options[:body])
          body_arguments = get_arguments(body)
          [value_to_code(body), body_arguments.map(&:to_s), false]
        else
          [has_body_param ? 'body' : 'nil', [], has_body_param]
        end
      end

      def extract_expected_response_codes(options)
        codes = options[:expected_response_codes] || Array(options[:expected_response_code])
        codes.map(&:to_s)
      end

      def determine_stream_param(options)
        case options[:stream]
        when true, :file then :file
        when :io then :io
        end
      end

      def build_method_args(named_arguments, has_body_param, stream_param)
        args = named_arguments.map { |arg_name| "#{arg_name}:" }
        args += ['body:'] if has_body_param
        args += ["#{stream_param}:"] if stream_param
        args + ['**__options__', '&block']
      end

      def generate_request_call_code(options, stream_param, expected_response_codes)
        code = "  @request_options[:#{stream_param}] = #{stream_param}\n" if stream_param
        code ||= ''
        validator = stream_validator_code(expected_response_codes)

        code + case options[:stream]
               when true, :file then "  @response = stream_to_file(**@request_options, #{validator})\n"
               when :io then "  @response = stream_to_io(**@request_options, #{validator})\n"
               when :block then "  @response = stream(**@request_options, #{validator}, &block)\n"
               else "  @response = request(**@request_options)\n"
               end
      end

      # Streaming routes check the status before the body is streamed, using the same
      # expected_response_code! as other routes, so error bodies never reach the file, IO or block
      def stream_validator_code(expected_response_codes)
        'validate_response: ->(response) { ' \
          "expected_response_code!(response, #{expected_response_codes.inspect}, __options__) }"
      end

      def generate_response_handling_code(options)
        if options[:stream] || options[:return] == :response
          "    @response\n"
        elsif options[:return] == :body
          "    @response.body\n"
        else
          "    handle_response(@response, __options__, &block)\n"
        end
      end

      def generate_route_code(method_name, path, options = {})
        # Validate method_name to prevent code injection
        unless method_name.to_s.match?(/\A[a-z_][a-z0-9_]*\z/i)
          raise ArgumentError, "Invalid method name: #{method_name.inspect}"
        end

        RouteValueValidator.validate!(method_name, :query, options[:query])
        RouteValueValidator.validate!(method_name, :body, options[:body])

        http_method = options[:method] || auto_detect_http_method(method_name)
        path, path_arguments = process_route_path(path)
        has_body_param = options[:body].nil? && requires_body?(http_method, options)

        query, query_arguments = build_query_code(options)
        body, body_arguments, has_body_param = build_body_code(options, has_body_param)

        named_arguments = (path_arguments + query_arguments + body_arguments).uniq
        expected_response_codes = extract_expected_response_codes(options)
        stream_param = determine_stream_param(options)
        method_args = build_method_args(named_arguments, has_body_param, stream_param)

        route_context = {
          method_name: method_name, method_args: method_args, path: path,
          query: query, body: body, http_method: http_method,
          options: options, stream_param: stream_param,
          expected_response_codes: expected_response_codes
        }

        generate_raw_response_method(route_context) + generate_wrapper_method(route_context)
      end

      def generate_raw_response_method(ctx)
        code = "def #{ctx[:method_name]}_raw_response(#{ctx[:method_args].join(', ')})\n"
        code += "  __path__ = \"#{ctx[:path]}\"\n"
        code += "  __query__ = #{ctx[:query]}\n"
        code += "  __body__ = #{ctx[:body]}\n"
        code += "  __uri__ = build_uri(__path__, __query__, __options__)\n"
        code += "  __body__ = build_body(__body__, __options__)\n"
        code += "  __headers__ = build_headers(__options__)\n"
        code += "  __connection_options__ = build_connection_options(__options__)\n"
        code += "  @request_options = {method: #{ctx[:http_method].inspect}, uri: __uri__, body: __body__, " \
                "headers: __headers__, connection_options: __connection_options__}\n"
        code += generate_request_call_code(ctx[:options], ctx[:stream_param], ctx[:expected_response_codes])
        "#{code}end\n\n"
      end

      def generate_wrapper_method(ctx)
        raw_call_args = ctx[:method_args].map { |a| a =~ /:$/ ? "#{a} #{a.sub(':', '')}" : a }.join(', ')

        code = "def #{ctx[:method_name]}(#{ctx[:method_args].join(', ')})\n"
        code += "  request_wrapper(__options__) do\n"
        code += "    block ||= self.class.get_response_proc(#{ctx[:method_name].inspect})\n"
        code += "    __expected_response_codes__ = #{ctx[:expected_response_codes].inspect}\n"
        code += "    #{ctx[:method_name]}_raw_response(#{raw_call_args})\n"
        code += "    expected_response_code!(@response, __expected_response_codes__, __options__)\n"
        code += generate_response_handling_code(ctx[:options])
        code += "  end\n"
        "#{code}end\n"
      end

      # A route definition is complete: redefining a route without a block also clears the
      # previous block, including one inherited from a parent class
      def route(method_name, path, options = {}, &block)
        add_response_proc(method_name, block)

        class_eval generate_route_code(method_name, path, options), __FILE__, __LINE__
      end
    end

    def base_url
      self.class.base_url
    end

    # Class-level headers may be method names or blocks; per-request headers are used as given.
    # Values are converted to strings, as Net::HTTP requires; nil values are left out of the request.
    def build_headers(options)
      headers = configured_headers
      headers.merge!(options[:headers]) if options[:headers]
      headers.transform_values { |value| value&.to_s }
    end

    # Class-level headers with symbols and blocks resolved; sections may add the root client's
    def configured_headers
      self.class.default_headers.transform_values { |value| resolve_config_value(value) }
    end

    def build_connection_options(options)
      connection_options = configured_connection_options
      options[:connection_options] ? connection_options.merge(options[:connection_options]) : connection_options
    end

    # Class-level connection options; sections may add the root client's
    def configured_connection_options
      self.class.default_connection_options
    end

    # Class-level query params may be method names or blocks; values from route arguments
    # and per-request options are sent as given.
    def build_query(query, options)
      query_params = configured_query_params
      query_params.merge!(query) if query
      query_params.merge!(options[:query]) if options[:query]

      query_params.empty? ? nil : self.class.build_query(self, query_params)
    end

    # Class-level query params with symbols and blocks resolved; sections may add the root client's
    def configured_query_params
      self.class.default_query_params.transform_values { |value| resolve_config_value(value) }
    end

    # Resolves a class-level header or query_param value: a Symbol calls that method and a
    # Proc is evaluated, both on the root router; anything else is used as is.
    def resolve_config_value(value)
      case value
      when Proc then root_router.instance_eval(&value)
      when Symbol then root_router.send(value)
      else value
      end
    end

    def build_body(body, options)
      body = options[:body] if options.key?(:body)

      return nil unless body
      return body if body.is_a?(String)

      self.class.build_body(self, body)
    end

    def build_uri(path, query, options)
      # Properly join base_url and path to handle missing/extra slashes
      base = validated_base_url.chomp('/')
      path = path.to_s
      path = "/#{path}" unless path.start_with?('/')

      uri = URI(base + path)
      uri.query = build_query(query, options)
      uri
    end

    # The base URL used for this request, checked every time so a base_url method defined on
    # the client gets the same scheme and host check as the class-level base_url
    def validated_base_url
      url = base_url.to_s
      if url.empty?
        raise ArgumentError, "no base_url configured for #{self.class.name || self.class.inspect}; set one with " \
                             "base_url 'https://api.example.com' or define a base_url method"
      end

      self.class.validate_base_url!(url)
      url
    end

    def expected_response_code!(response, expected_response_codes, _options)
      return if expected_response_codes.empty? && response.is_a?(Net::HTTPSuccess)
      return if expected_response_codes.include?(response.code)

      raise(::ClientApiBuilder::UnexpectedResponse.new("unexpected response code #{response.code}", response))
    end

    def parse_response(response, _options)
      body = response.body
      return nil if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError => e
      raise ::ClientApiBuilder::UnexpectedResponse.new(
        "Invalid JSON in response: #{e.message}",
        response
      )
    end

    def handle_response(response, options, &block)
      data =
        case options[:return]
        when :response
          response
        when :body
          response.body
        else
          parse_response(response, options)
        end

      if block
        instance_exec(data, &block)
      else
        data
      end
    end

    def root_router
      self
    end

    # Percent-encodes everything but RFC 3986 unreserved characters (A-Z a-z 0-9 - . _ ~),
    # so a value inserted into the path, including any '/', stays one segment.
    # Override to change how path values are encoded.
    def escape_path(path)
      ERB::Util.url_encode(path.to_s)
    end

    def instrument_request
      start_time = Time.now
      yield
    ensure
      @total_request_time = Time.now - start_time
    end

    def retry_request(options)
      @request_attempts = 0
      max_attempts = get_retry_request_max_retries(options)
      begin
        @request_attempts += 1
        yield
      rescue StandardError => e
        # Use StandardError instead of Exception to allow SystemExit, Interrupt, etc. to propagate
        log_request_exception(e)
        raise(e) if @request_attempts >= max_attempts || !retry_request?(e, options)

        sleep_time = get_retry_request_sleep_time(e, options)
        sleep(sleep_time) if sleep_time&.positive?
        retry
      end
    end

    def get_retry_request_sleep_time(_exception, options)
      options[:sleep] || self.class.default_options[:sleep] || 0.05
    end

    def get_retry_request_max_retries(options)
      options[:retries] || self.class.default_options[:max_retries] || 1
    end

    def request_wrapper(options, &block)
      retry_request(options) do
        # Clear the previous attempt's state so a failed attempt never reports an earlier response
        @request_options = nil
        @response = nil
        instrument_request(&block)
      end
    end

    # Determines whether to retry on a given exception.
    # Override this method to customize retry behavior.
    # By default, only retries on network-related errors, not application errors.
    def retry_request?(exception, _options)
      case exception
      when Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET,
           Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError, EOFError
        true
      else
        false
      end
    end

    def log_request_exception(exception)
      ::ClientApiBuilder.logger&.error(exception)
    end

    def request_log_message
      return '' unless request_options

      method = request_options[:method].to_s.upcase
      uri = request_options[:uri]
      return "#{method} [no URI]" unless uri

      response_code = response ? response.code : 'UNKNOWN'
      duration = total_request_time ? (total_request_time * 1000).to_i : 0

      "#{method} #{uri.scheme}://#{uri.host}#{uri.path}[#{response_code}] took #{duration}ms"
    end
  end
end
