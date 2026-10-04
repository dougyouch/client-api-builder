# frozen_string_literal: true

require 'net/http'

module ClientApiBuilder
  module ConnectionPools
    # A started Net::HTTP session and when it was opened and last used. Times come from the
    # pool's monotonic clock. Net::HTTP reopens the socket itself if the server closed it or it
    # sat idle past keep_alive_timeout.
    class Connection
      attr_reader :http, :opened_at, :last_used_at

      def self.open(host, port, connection_options, now)
        new(Net::HTTP.start(host, port, connection_options), now)
      end

      def initialize(http, now)
        @http = http
        @opened_at = now
        @last_used_at = now
      end

      def used(now)
        @last_used_at = now
      end

      def expired?(ttl, now)
        now - opened_at >= ttl
      end

      def close
        http.finish if http.started?
      end
    end
  end
end
