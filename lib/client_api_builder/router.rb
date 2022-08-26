# frozen_string_literal: true
require 'inheritance-helper'

module ClientApiBuilder
  module Router
    def self.included(base)
      base.extend InheritanceHelper::Methods
      base.extend ClassMethods
      base.include ::ClientApiBuilder::Section
      base.include ::ClientApiBuilder::NetHTTP::Request
      base.send(:attr_reader, :response, :request_options, :total_request_time, :retry_attempts)
    end

    module ClassMethods
      REQUIRED_BODY_HTTP_METHODS = [
        :post,
        :put,
        :patch
      ]

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

      # tracks the proc used to handle responses
      def add_response_proc(method_name, proc)
        response_procs = default_options[:response_procs].dup
        response_procs[method_name] = proc
        add_value_to_class_method(:default_options, response_procs: response_procs)
      end

      # retrieves the proc used to handle the response
      def get_response_proc(method_name)
        default_options[:response_procs][method_name]
      end

      # set/get base url
      def base_url(url = nil)
        return default_options[:base_url] unless url

        add_value_to_class_method(:default_options, base_url: url)
      end

      # set the builder to :to_json, :to_query, :query_params or specify a proc to handle building the request body payload
      # or get the body builder
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
        headers = default_options[:headers].dup
        headers[name] = value || block
        add_value_to_class_method(:default_options, headers: headers)
      end

      # set a connection_option, specific to Net::HTTP
      def connection_option(name, value)
        connection_options = default_options[:connection_options].dup
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
        query_params = default_options[:query_params].dup
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

      def auto_detect_http_method(method_name)
        case method_name.to_s
        when /^(?:post|create|add|insert)/i
          :post
        when /^(?:put|update|modify|change)/i
          :put
        when /^(?:delete|remove)/i
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

      def get_hash_arguments(hsh)
        arguments = []
        hsh.each do |k, v|
          case v
          when Symbol
            hsh[k] = "__||#{v}||__"
            arguments << v
          when Hash
            arguments += get_hash_arguments(v)
          when Array
            arguments += get_array_arguments(v)
          when String
            hsh[k] = "__||#{$1}||__" if v =~ /\{([a-z0-9_]+)\}/i
          end
        end
        arguments
      end

      def get_array_arguments(list)
        arguments = []
        list.each_with_index do |v, idx|
          case v
          when Symbol
            list[idx] = "__||#{v}||__"
            arguments << v
          when Hash
            arguments += get_hash_arguments(v)
          when Array
            arguments += get_array_arguments(v)
          when String
            list[idx] = "__||#{$1}||__" if v =~ /\{([a-z0-9_]+)\}/i
          end
        end
        arguments
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
         "#\{escape_path(#{var})\}"
      end

      @@namespaces = []
      def namespaces
        @@namespaces
      end

      # a namespace is a top level path to apply to all routes within the namespace block
      def namespace(name)
        namespaces << name
        yield
        namespaces.pop
      end

      def generate_route_code(method_name, path, options = {})
        http_method = options[:method] || auto_detect_http_method(method_name)

        path = namespaces.join + path

        # instance method
        path.gsub!(/\{([a-z0-9_]+)\}/i) do |_|
          get_instance_method($1)
        end

        path_arguments = []
        path.gsub!(/:([a-z0-9_]+)/i) do |_|
          path_arguments << $1
          "#\{escape_path(#{$1})\}"
        end

        has_body_param = options[:body].nil? && requires_body?(http_method, options)

        query =
          if options[:query]
            query_arguments = get_arguments(options[:query])
            str = options[:query].inspect
            str.gsub!(/"__\|\|(.+?)\|\|__"/) { $1 }
            str
          else
            query_arguments = []
            'nil'
          end

        body =
          if options[:body]
            has_body_param = false
            body_arguments = get_arguments(options[:body])
            str = options[:body].inspect
            str.gsub!(/"__\|\|(.+?)\|\|__"/) { $1 }
            str
          else
            body_arguments = []
            has_body_param ? 'body' : 'nil'
          end

        query_arguments.map!(&:to_s)
        body_arguments.map!(&:to_s)
        named_arguments = path_arguments + query_arguments + body_arguments
        named_arguments.uniq!

        expected_response_codes =
          if options[:expected_response_codes]
            options[:expected_response_codes]
          elsif options[:expected_response_code]
            [options[:expected_response_code]]
          else
            []
          end
        expected_response_codes.map!(&:to_s)

        stream_param =
          case options[:stream]
          when true,
               :file
            :file
          when :io
            :io
          end

        method_args = named_arguments.map { |arg_name| "#{arg_name}:" }
        method_args += ['body:'] if has_body_param
        method_args += ["#{stream_param}:"] if stream_param
        method_args += ['**__options__', '&block']

        code = "def #{method_name}_raw_response(" + method_args.join(', ') + ")\n"
        code += "  __path__ = \"#{path}\"\n"
        code += "  __query__ = #{query}\n"
        code += "  __body__ = #{body}\n"
        code += "  __uri__ = build_uri(__path__, __query__, __options__)\n"
        code += "  __body__ = build_body(__body__, __options__)\n"
        code += "  __headers__ = build_headers(__options__)\n"
        code += "  __connection_options__ = build_connection_options(__options__)\n"
        code += "  @request_options = {method: #{http_method.inspect}, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__}\n"
        code += "  @request_options[:#{stream_param}] = #{stream_param}\n" if stream_param

        case options[:stream]
        when true,
             :file
          code += "  @response = stream_to_file(**@request_options)\n"
        when :io
          code += "  @response = stream_to_io(**@request_options)\n"
        when :block
          code += "  @response = stream(**@request_options, &block)\n"
        else
          code += "  @response = request(**@request_options)\n"
        end
        code += "end\n"
        code += "\n"

        code += "def #{method_name}(" + method_args.join(', ') + ")\n"
        code += "  request_wrapper(__options__) do\n"
        code += "    block ||= self.class.get_response_proc(#{method_name.inspect})\n"
        code += "    __expected_response_codes__ = #{expected_response_codes.inspect}\n"
        code += "    #{method_name}_raw_response(" + method_args.map { |a| a =~ /:$/ ? "#{a} #{a.sub(':', '')}" : a }.join(', ') + ")\n"
        code += "    expected_response_code!(@response, __expected_response_codes__, __options__)\n"

        if options[:stream] || options[:return] == :response
          code += "    @response\n"
        elsif options[:return] == :body
          code += "    @response.body\n"
        else
          code += "    handle_response(@response, __options__, &block)\n"
        end

        code += "  end\n"
        code += "end\n"
        code
      end

      def route(method_name, path, options = {}, &block)
        add_response_proc(method_name, block) if block

        self.class_eval generate_route_code(method_name, path, options), __FILE__, __LINE__
      end
    end

    def base_url
      self.class.base_url
    end

    def build_headers(options)
      headers = {}

      add_header_proc = proc do |name, value|
        headers[name] =
          if value.is_a?(Proc)
            instance_eval(&value)
          elsif value.is_a?(Symbol)
            send(value)
          else
            value
          end
      end

      self.class.default_headers.each(&add_header_proc)
      options[:headers] && options[:headers].each(&add_header_proc)

      headers
    end

    def build_connection_options(options)
      if options[:connection_options]
        self.class.default_connection_options.merge(options[:connection_options])
      else
        self.class.default_connection_options
      end
    end

    def build_query(query, options)
      return nil if query.nil? && self.class.default_query_params.empty?

      query_params = {}

      add_query_param_proc = proc do |name, value|
        query_params[name] =
          if value.is_a?(Proc)
            instance_eval(&value)
          elsif value.is_a?(Symbol)
            send(value)
          else
            value
          end
      end

      self.class.default_query_params.each(&add_query_param_proc)
      query && query.each(&add_query_param_proc)
      options[:query] && options[:query].each(&add_query_param_proc)

      self.class.build_query(self, query_params)
    end

    def build_body(body, options)
      body = options[:body] if options.key?(:body)

      return nil unless body
      return body if body.is_a?(String)

      self.class.build_body(self, body)
    end

    def build_uri(path, query, options)
      uri = URI(base_url + path)
      uri.query = build_query(query, options)
      uri
    end

    def expected_response_code!(response, expected_response_codes, options)
      return if expected_response_codes.empty? && response.kind_of?(Net::HTTPSuccess)
      return if expected_response_codes.include?(response.code)

      raise(::ClientApiBuilder::UnexpectedResponse.new("unexpected response code #{response.code}", response))
    end

    def parse_response(response, options)
      response.body && JSON.parse(response.body)
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

    def escape_path(path)
      path
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
      rescue Exception => e
        raise(e) if @request_attempts >= max_attempts
        sleep(get_retry_request_sleep_time(e, options))
        retry
      end
    end

    def get_retry_request_sleep_time(e, options)
      options[:sleep] || self.class.default_options[:sleep] || 0.05
    end

    def get_retry_request_max_retries(options)
      options[:retries] || self.class.default_options[:max_retries] || 1
    end

    def request_wrapper(options)
      retry_request(options) do
        instrument_request do
          yield
        end
      end
    end
  end
end
