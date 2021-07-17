# frozen_string_literal: true
require 'net/http'

module ClientApiBuilder
  module NetHTTP
    module Request
      # Copied from https://ruby-doc.org/stdlib-2.7.1/libdoc/net/http/rdoc/Net/HTTP.html
      METHOD_TO_NET_HTTP_CLASS = {
        copy: Net::HTTP::Copy,
        delete: Net::HTTP::Delete,
        get: Net::HTTP::Get,
        head: Net::HTTP::Head,
        lock: Net::HTTP::Lock,
        mkcol: Net::HTTP::Mkcol,
        move: Net::HTTP::Move,
        options: Net::HTTP::Options,
        patch: Net::HTTP::Patch,
        post: Net::HTTP::Post,
        propfind: Net::HTTP::Propfind,
        proppatch: Net::HTTP::Proppatch,
        put: Net::HTTP::Put,
        trace: Net::HTTP::Trace,
        unlock: Net::HTTP::Unlock
      }

      def request(method:, uri:, body:, headers:, connection_options:)
        request = METHOD_TO_NET_HTTP_CLASS[method].new(uri.request_uri, headers)
        request.body = body if body

        Net::HTTP.start(uri.hostname, uri.port, connection_options.merge(use_ssl: uri.scheme == 'https')) do |http|
          http.request(request) do |response|
            yield response if block_given?
          end
        end
      end

      def stream(method:, uri:, body:, headers:, connection_options:)
        request(method: method, uri: uri, body: body, headers: headers, connection_options: connection_options) do |response|
          response.read_body do |chunk|
            yield response, chunk
          end
        end
      end

      def stream_to_io(method:, uri:, body:, headers:, connection_options:, io:)
        stream(method: method, uri: uri, body: body, headers: headers, connection_options: connection_options) do |_, chunk|
          io.write chunk
        end
      end

      def stream_to_file(method:, uri:, body:, headers:, connection_options:, file:)
        mode = connection_options.delete(:file_mode) || 'wb'
        File.open(file, mode) do |io|
          stream_to_io(method: method, uri: uri, body: body, headers: headers, connection_options: connection_options, io: io)
        end
      end
    end
  end
end
