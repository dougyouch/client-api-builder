# frozen_string_literal: true
require 'inheritance-helper'

module ClientApiBuilder
  module Router
    def self.included(base)
      base.extend InheritanceHelper::Methods
      base.extend ClassMethods
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
          raise("unsupported query builder #{query_builder}")
        end
      end

      def http_method(method_name, options)
        return options[:method] if  options[:method]

        case method_name.to_s
        when /^(?:post|create|add|insert)/i
          :post
        when /^(?:put|update|modify|change/i
          :put
        when /^(?:delete|remove)/i
          :delete
        else
          :get
        end
      end

      def requires_body?(method, options)
        return !options[:no_body] if options.key?(:no_body)
        return options[:has_body] if options[:has_body]

        REQUIRED_BODY_HTTP_METHODS.include?(method)
      end

      def route(method_name, path, options = {})
        query = options[:query] || {}
        method_arguments = []
        add_query_method_argument_proc = Proc.new do |k|
          arg
          query[k] = 
        query.each { |k, v| v == :primary_arg ? query[k]
        path_arguments = path.scan(/:[a-z_]+/)
        primary_query_arguments = query.select { |_, v| v == :primary_arg }.values
        query_arguments = query.select { |_, v| v == :arg }.values
        http_method = http_method(method_name, options)
        has_body_param = requires_body?(method, options)

        method_arguments = (primary_query_arguments + path_arguments + query_arguments).each_with_index.each_with_object({}) do |(param, idx), hsh|
          
        end
        
        class_eval(
<<-STR, __FILE__, __LINE__ + 1
STR
        )
      end
    end

    def base_url
      self.class.base_url
    end

    def headers
      self.class.headers
    end

    def connection_options
      self.class.connection_options
    end

    def build_query(query)
      self.class.build_query(query)
    end

    def create_uri(path, query)
      uri = URI(base_url + path)
      uri.query = build_query(query) if query
      uri
    end
  end
end
