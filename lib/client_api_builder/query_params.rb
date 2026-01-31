# frozen_string_literal: true

require 'cgi'

module ClientApiBuilder
  class QueryParams
    attr_reader :name_value_separator,
                :param_separator

    attr_accessor :custom_escape_proc

    def initialize(name_value_separator: '=', param_separator: '&', custom_escape_proc: nil)
      @name_value_separator = name_value_separator
      @param_separator = param_separator
      @custom_escape_proc = custom_escape_proc
    end

    def to_query(data, namespace = nil)
      case data
      when Hash
        to_query_from_hash(data, (namespace ? escape(namespace) : nil)).join(param_separator)
      when Array
        to_query_from_array(data, (namespace ? "#{escape(namespace)}[]" : '[]')).join(param_separator)
      else
        if namespace
          "#{escape(namespace)}#{name_value_separator}#{escape(data.to_s)}"
        else
          escape(data.to_s)
        end
      end
    end

    def to_query_from_hash(hsh, namespace)
      query_params = []

      hsh.each do |key, value|
        case value
        when Array
          array_namespace = namespace ? "#{namespace}[#{escape(key.to_s)}][]" : "#{escape(key.to_s)}[]"
          query_params += to_query_from_array(value, array_namespace)
        when Hash
          hash_namespace = namespace ? "#{namespace}[#{escape(key.to_s)}]" : escape(key.to_s).to_s
          query_params += to_query_from_hash(value, hash_namespace)
        else
          query_name = namespace ? "#{namespace}[#{escape(key.to_s)}]" : escape(key.to_s).to_s
          query_params << "#{query_name}#{name_value_separator}#{escape(value.to_s)}"
        end
      end

      query_params
    end

    def to_query_from_array(array, namespace)
      query_params = []

      array.each do |value|
        case value
        when Hash
          query_params += to_query_from_hash(value, namespace)
        when Array
          query_params += to_query_from_array(value, "#{namespace}[]")
        else
          query_params << "#{namespace}#{name_value_separator}#{escape(value.to_s)}"
        end
      end

      query_params
    end

    def escape(str)
      custom_escape_proc ? custom_escape_proc.call(str) : CGI.escape(str)
    end
  end
end
