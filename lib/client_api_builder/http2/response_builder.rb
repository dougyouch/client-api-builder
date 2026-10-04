# frozen_string_literal: true

require 'net/http'

module ClientApiBuilder
  module HTTP2
    # Builds the Net::HTTPResponse for an HTTP/2 response, so code written against Net::HTTP
    # (handle_response, UnexpectedResponse#response, response['header']) works unchanged.
    # HTTP/2 has no reason phrase, so message is empty. Like Net::HTTP, a gzip or deflate body
    # is inflated when Net::HTTP chose accept-encoding itself (request.decode_content); its
    # content-encoding and content-length headers are then removed.
    module ResponseBuilder
      INFLATABLE_ENCODINGS = %w[gzip deflate].freeze

      module_function

      def build(headers, exchange, net_request)
        status = headers.assoc(':status').last
        response = response_class(status).new('2.0', status, '')
        headers.each { |name, value| response.add_field(name, value) unless name.start_with?(':') }
        inflate = net_request.decode_content && inflatable?(response)
        response.delete('content-encoding') if inflate
        response.delete('content-length') if inflate
        response.extend(ResponseBody)
        response.http2_body(exchange, inflate: inflate, expected: body_expected?(response, net_request))
        response
      end

      def response_class(status)
        Net::HTTPResponse::CODE_TO_OBJ[status] ||
          Net::HTTPResponse::CODE_CLASS_TO_OBJ[status[0]] ||
          Net::HTTPUnknownResponse
      end

      def inflatable?(response)
        INFLATABLE_ENCODINGS.include?(response['content-encoding']&.downcase)
      end

      # A HEAD request or a 204/304 response has no body; Net::HTTP leaves it nil
      def body_expected?(response, net_request)
        net_request.response_body_permitted? && response.class.body_permitted?
      end
    end
  end
end
