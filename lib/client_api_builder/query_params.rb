# frozen_string_literal: true
require 'cgi'

module ClientApiBuilder
  module QueryParams
    module_function

    def to_query(data, namespace = nil, name_value_separator = '=', param_separator = '&')
      case data
      when Hash
        to_query_from_hash(data, (namespace ? CGI.escape(namespace) : nil), name_value_separator).join(param_separator)
      when Array
        to_query_from_array(data, (namespace ? CGI.escape(namespace) : nil), name_value_separator).join(param_separator)
      else
        if namespace
          "#{CGI.escape(namespace)}#{name_value_separator}#{CGI.escape(value.to_s)}"
        else
          CGI.escape(data.to_s)
        end
      end
    end

    def to_query_from_hash(hsh, namespace, name_value_separator)
      query_params = []

      hsh.each do |key, value|
        case value
        when Array
          array_namespace = namespace ? "#{namespace}[#{CGI.escape(key.to_s)}][]" : "#{CGI.escape(key.to_s)}[]"
          query_params += to_query_from_array(value, array_namespace, name_value_separator)
        when Hash
          hash_namespace = namespace ? "#{namespace}[#{CGI.escape(key.to_s)}]" : "#{CGI.escape(key.to_s)}"
          query_params += to_query_from_hash(value, hash_namespace, name_value_separator)
        else
          query_name = namespace ? "#{namespace}[#{CGI.escape(key.to_s)}]" : "#{CGI.escape(key.to_s)}"
          query_params << "#{query_name}#{name_value_separator}#{CGI.escape(value.to_s)}"
        end
      end

      query_params
    end

    def to_query_from_array(array, namespace, name_value_separator)
      query_params = []

      array.each do |value|
        case value
        when Hash
          query_params += to_query_from_hash(value, namespace, name_value_separator)
        when Array
          query_params += to_query_from_array(value, "#{namespace}[]", name_value_separator)
        else
          query_params << "#{namespace}#{name_value_separator}#{CGI.escape(value.to_s)}"
        end
      end

      query_params
    end
  end
end
