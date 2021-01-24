# frozen_string_literal: true
require 'inheritance-helper'

module ClientApiBuilder
  module Router
    def self.included(base)
      base.extend InheritanceHelper::Methods
      base.extend ClassMethods
      base.include ::ClientApiBuilder::NetHTTP::Request
      base.attr_reader :response
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
          headers: {},
          connection_options: {},
          query_builder: Hash.method_defined?(:to_query) ? :to_query : :query_params
        }.freeze
      end

      def base_url(url = nil)
        return default_options[:base_url] unless url

        add_value_to_class_method(:default_options, base_url: url)
      end

      def query_builder(builder = nil)
        return default_options[:query_builder] unless builder

        add_value_to_class_method(:default_options, query_builder: builder)
      end

      def header(name, value)
        headers = default_options[:headers].dup
        headers[name] = value
        add_value_to_class_method(:default_options, headers: headers)
      end

      def connection_option(name, value)
        connection_options = default_options[:connection_options].dup
        connection_options[name] = value
        add_value_to_class_method(:default_options, connection_options: connection_options)
      end

      def headers
        default_options[:headers]
      end

      def connection_options
        default_options[:connection_options]
      end

      def build_query(query)
        case query_builder
        when :to_query
          query.to_query
        when :query_params
          ClientApiBuilder::QueryParams.to_query(query)
        else
          query_builder.call(query)
        end
      end

      def http_method(method_name)
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
          end
        end
        arguments
      end

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

      def generate_route_code(method_name, path, options = {})
        http_method = options[:method] || http_method(method_name)

        path_arguments = []
        path.gsub!(/:([a-z0-9_]+)/i) do |_|
          path_arguments << $1
          "#\{#{$1}\}"
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

        method_args = named_arguments.map { |arg_name| "#{arg_name}:" }
        method_args += ['body:'] if has_body_param
        method_args += ['**__options__', '&block']

        code = "def #{method_name}(" + method_args.join(', ') + ")\n"
        code += "  __path__ = \"#{path}\"\n"
        code += "  __query__ = #{query}\n"
        code += "  __body__ = #{body}\n"
        code += "  __expected_response_codes__ = #{expected_response_codes.inspect}\n"
        code += "  __uri__ = build_uri(__path__, __query__, __options__)\n"
        code += "  __body__ = build_body(__body__, __options__)\n"
        code += "  __headers__ = build_headers(__options__)\n"
        code += "  __connection_options__ = build_connection_options(__options__)\n"
        code += "  @response = request(method: #{http_method.inspect}, uri: __uri__, body: __body__, headers: __headers__, connection_options: __connection_options__)\n"
        code += "  expected_response!(@response, __expected_response_codes__, __options__)\n"
        code += "  handle_response(@response, __options__, &block)\n"
        code += "end\n"
        code
      end

      def route(method_name, path, options = {})
        self.class_eval generate_route_code(method_name, path, options), __FILE__, __LINE__
      end
    end

    def base_url(options)
      self.class.base_url
    end

    def build_headers(options)
      if options[:headers]
        self.class.headers.merge(options[:headers])
      else
        self.class.headers
      end
    end

    def build_connection_options(options)
      if options[:connection_options]
        self.class.connection_options.merge(options[:connection_options])
      else
        self.class.connection_options
      end
    end

    def build_query(query, options)
      query.merge!(options[:query]) if options[:query]
      self.class.build_query(query)
    end

    def build_body(body, options)
      return unless body
      return body if body.is_a?(String)

      body.merge!(options[:body]) if options[:body]
      body.to_json
    end

    def build_uri(path, query, options)
      uri = URI(base_url(options) + path)
      uri.query = build_query(query, options) if query
      uri
    end

    def expected_response!(response, expected_response_codes, options)
      return if expected_response_codes.empty? && response.kind_of?(Net::HTTPSuccess)
      return if expected_response_codes.include?(response.code)

      raise(::ClientApiBuilder::UnexpectedResponse.new("unexpected response code #{response.code}", response))
    end

    def parse_response(response, options)
      JSON.parse(response.body)
    end

    def handle_response(response, options, &block)
      data = parse_response(response, options)
      if block
        instance_exec(data, &block)
      else
        data
      end
    end
  end
end
