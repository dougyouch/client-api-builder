# frozen_string_literal: true

require 'net/http'

module ClientApiBuilder
  module HTTP2
    # One request's stream, seen from the thread waiting on it. The connection's reader thread
    # pushes the stream's events (headers, data, close) or a connection failure onto a queue;
    # the waiting thread pops them, giving up after read_timeout seconds without one.
    #
    # Received data is acknowledged to the server as it arrives, so a consumer that reads
    # slower than the server sends buffers the difference in memory.
    class Exchange
      attr_reader :stream

      def initialize(stream, read_timeout)
        @stream = stream
        @read_timeout = read_timeout
        @events = Thread::Queue.new
        @finished = false
        stream.on(:headers) { |headers| @events << [:headers, headers] }
        stream.on(:data) { |chunk| @events << [:data, chunk] }
        stream.on(:close) { |error| @events << [:close, error] }
      end

      # Called by the connection when the stream will never finish
      def fail(error)
        @events << [:error, error]
      end

      # Waits for the final response headers, skipping informational (1xx) ones
      def response_headers
        loop do
          type, value = next_event
          raise stream_closed_error(value || :no_error) if type == :close
          return value unless informational?(value)
        end
      end

      # Yields each chunk of the response body until the stream ends. Trailers are ignored.
      def each_chunk
        until @finished
          type, value = next_event
          yield value if type == :data
          finish(value) if type == :close
        end
      end

      private

      def next_event
        type, value = @events.pop(timeout: @read_timeout)
        raise Net::ReadTimeout, "no response on HTTP/2 stream #{stream.id} within #{@read_timeout}s" if type.nil?
        raise value if type == :error

        [type, value]
      end

      def finish(error)
        raise stream_closed_error(error) unless error.nil? || error == :no_error

        @finished = true
      end

      def informational?(headers)
        headers.any? { |name, value| name == ':status' && value.start_with?('1') }
      end

      def stream_closed_error(error)
        return StreamRefused.new("server refused HTTP/2 stream #{stream.id}") if error == :refused_stream

        StreamError.new("HTTP/2 stream #{stream.id} closed before the response finished (#{error})")
      end
    end
  end
end
