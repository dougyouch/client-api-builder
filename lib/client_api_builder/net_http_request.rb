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

      def request(method, uri, body, headers, connection_options)
        request = METHOD_TO_NET_HTTP_CLASS[method].new(uri.request_uri, headers)
        request_uri.body = body if body

        Net::HTTP.start(uri.hostname, uri.port, connection_options.merge(use_ssl: uri.scheme == 'https')) do |http|
          http.request(request)
        end
      end
    end
  end
end
