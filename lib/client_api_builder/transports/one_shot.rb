# frozen_string_literal: true

require 'net/http'

module ClientApiBuilder
  module Transports
    # A new connection for every request, closed once the response is read. Nothing outlives
    # a request, so it suits web servers and forking process managers. This is the default.
    class OneShot
      def with_connection(uri, connection_options, &)
        Net::HTTP.start(uri.hostname, uri.port, connection_options, &)
      end

      # Nothing stays open between requests
      def close; end
    end
  end
end
