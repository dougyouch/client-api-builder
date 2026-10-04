# frozen_string_literal: true

module ClientApiBuilder
  module HTTP2
    # Turns a Net::HTTP request into an HTTP/2 header list: the pseudo-headers first, then the
    # request's own headers (already lowercase) without the connection-specific ones HTTP/2
    # forbids (RFC 9113 section 8.2.2). Host becomes :authority.
    module RequestHeaders
      CONNECTION_HEADERS = %w[connection host keep-alive proxy-connection transfer-encoding upgrade].freeze

      module_function

      def build(net_request, authority)
        headers = pseudo_headers(net_request, authority)
        net_request.each_header do |name, value|
          headers << [name, value] unless connection_header?(name, value)
        end
        body = net_request.body
        headers << ['content-length', body.bytesize.to_s] if body && !net_request.key?('content-length')
        headers
      end

      def pseudo_headers(net_request, authority)
        [
          [':method', net_request.method],
          [':scheme', 'https'],
          [':authority', net_request['host'] || authority],
          [':path', net_request.path]
        ]
      end

      # te is allowed only as "trailers"
      def connection_header?(name, value)
        CONNECTION_HEADERS.include?(name) || (name == 'te' && value != 'trailers')
      end
    end
  end
end
