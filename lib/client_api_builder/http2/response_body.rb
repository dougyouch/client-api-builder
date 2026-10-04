# frozen_string_literal: true

require 'net/http'
require 'zlib'

module ClientApiBuilder
  module HTTP2
    # Extended onto a Net::HTTPResponse built by ResponseBuilder: read_body reads the HTTP/2
    # stream instead of a socket, with Net::HTTP's semantics (into a string, a given buffer or a
    # block, once). A body that isn't expected is drained and left nil.
    module ResponseBody
      def http2_body(exchange, inflate:, expected:)
        @http2_exchange = exchange
        @http2_inflate = inflate
        @http2_body_expected = expected
      end

      def read_body(dest = nil, &block)
        if @read
          raise IOError, "#{self.class}#read_body called twice" if dest || block

          return @body
        end
        raise ArgumentError, 'both arg and block given for HTTP method' if dest && block

        @body = @http2_body_expected ? read_http2_body(body_destination(dest, block)) : drain
        @read = true
        @body
      end

      private

      def body_destination(dest, block)
        return Net::ReadAdapter.new(block) if block

        dest || String.new
      end

      def read_http2_body(dest)
        inflater = Zlib::Inflate.new(32 + Zlib::MAX_WBITS) if @http2_inflate
        @http2_exchange.each_chunk { |chunk| dest << (inflater ? inflater.inflate(chunk) : chunk) }
        dest << inflater.finish if inflater
        dest
      ensure
        inflater&.close
      end

      def drain
        @http2_exchange.each_chunk { |_chunk| nil }
        nil
      end
    end
  end
end
