# frozen_string_literal: true

# Purpose: opt-in HTTP/2 for https requests, using the http-2 gem (add gem 'http-2' to your
# Gemfile; it isn't a runtime dependency). Include after ClientApiBuilder::Router, and after
# ClientApiBuilder::ConnectionPools when using both:
#
#   class MyClient
#     include ClientApiBuilder::Router
#     include ClientApiBuilder::HTTP2
#
#     base_url 'https://api.example.com'
#   end
#
# Every instance of the class shares one connection per origin, carrying concurrent requests
# as streams. TLS negotiates the protocol (ALPN): when the server picks HTTP/1.1, the origin is
# remembered and its requests go through Net::HTTP (or the connection pools) instead. http
# URLs always use HTTP/1.1. Responses are Net::HTTPResponse objects with http_version '2.0'.
module ClientApiBuilder
  module HTTP2
    autoload :Connection, 'client_api_builder/http2/connection'
    autoload :ConnectionSet, 'client_api_builder/http2/connection_set'
    autoload :Exchange, 'client_api_builder/http2/exchange'
    autoload :RequestHeaders, 'client_api_builder/http2/request_headers'
    autoload :ResponseBody, 'client_api_builder/http2/response_body'
    autoload :ResponseBuilder, 'client_api_builder/http2/response_builder'
    autoload :TLSSocket, 'client_api_builder/http2/tls_socket'

    # The connection dropped (or was closed) before the response finished
    class ConnectionLost < ::ClientApiBuilder::RetryableError; end

    # The server refused the stream, or announced it would stop (GOAWAY) before processing it
    class StreamRefused < ::ClientApiBuilder::RetryableError; end

    # The server reset the stream with an error code
    class StreamError < ::ClientApiBuilder::Error; end

    # The server broke the HTTP/2 protocol; the connection is closed
    class ProtocolError < ::ClientApiBuilder::Error; end

    def self.included(base)
      unless base.include?(::ClientApiBuilder::Router)
        raise ArgumentError, 'include ClientApiBuilder::Router before ClientApiBuilder::HTTP2'
      end

      require_http2_gem
      base.extend ClassMethods
      base.redefine_class_method(:http2_connections, ConnectionSet.new)
    end

    def self.require_http2_gem
      require 'http/2'
    rescue LoadError
      raise LoadError, "ClientApiBuilder::HTTP2 needs the http-2 gem; add gem 'http-2' to your Gemfile"
    end

    module ClassMethods
      # Closes this class's HTTP/2 connections, and its connection pools when it has them
      def close_connections
        http2_connections.close
        super if defined?(super)
      end
    end

    def with_http_connection(uri, connection_options, &)
      connection = uri.scheme == 'https' && self.class.http2_connections.connection_for(uri, connection_options)
      connection ? yield(connection) : super
    end
  end
end
