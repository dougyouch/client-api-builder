# frozen_string_literal: true

require 'net/http'
require 'openssl'

module ClientApiBuilder
  module HTTP2
    # One HTTP/2 connection carrying concurrent requests as streams. A reader thread feeds the
    # socket's bytes to the http-2 client, whose callbacks hand each stream's events to its
    # Exchange. Every call into the http-2 client, and so every socket write, happens under one
    # mutex; the reader blocks in readpartial outside it. (OpenSSL never reads and writes at
    # once: Ruby holds the GVL while calling SSL_read and SSL_write.)
    #
    # A connection stops taking new streams once either side sends GOAWAY or it fails, and
    # closes its socket when its last stream finishes.
    class Connection
      READ_SIZE = 16_384

      # Returns nil, after closing the socket, when the server chose HTTP/1.1
      def self.open(host, port, authority, connection_options)
        socket = TLSSocket.open(host, port, connection_options)
        return new(socket, authority, connection_options[:read_timeout]) if socket.alpn_protocol == 'h2'

        socket.close
        nil
      end

      def initialize(socket, authority, read_timeout)
        @socket = socket
        @authority = authority
        @read_timeout = read_timeout
        @mutex = Mutex.new
        @stream_closed = ConditionVariable.new
        @exchanges = {}
        @error = nil
        @client = build_client
        @mutex.synchronize { @client.send_connection_preface }
        @reader = Thread.new { read_loop }
      end

      # Sends a Net::HTTP request and, like Net::HTTP#request, yields the response before its
      # body is read, then reads whatever the block left and returns the response
      def request(net_request)
        exchange = start(net_request)
        response = ResponseBuilder.build(exchange.response_headers, exchange, net_request)
        yield response if block_given?
        response.read_body
        response
      ensure
        cancel(exchange) if exchange
      end

      # True while the connection can take new streams
      def open?
        @mutex.synchronize { @error.nil? && !@client.closed? }
      end

      # Says goodbye to the server and closes the socket; streams still in flight fail
      def close
        @mutex.synchronize do
          send_goaway unless @error || @client.closed?
          abort(ConnectionLost.new("HTTP/2 connection to #{@authority} was closed"))
        end
      end

      private

      def build_client
        client = ::HTTP2::Client.new
        client.on(:frame) { |bytes| @socket.write(bytes) }
        client.on(:goaway) { |last_stream_id, _error, _payload| refuse_streams_after(last_stream_id) }
        client
      end

      def start(net_request)
        headers = RequestHeaders.build(net_request, @authority)
        body = net_request.body
        @mutex.synchronize do
          stream = open_stream
          exchange = @exchanges[stream.id] = Exchange.new(stream, @read_timeout)
          stream.on(:close) { stream_closed(stream.id) }
          stream.headers(headers, end_stream: body.nil?)
          stream.data(body) if body
          exchange
        end
      end

      # Waits, up to read_timeout, while the server's limit on concurrent streams is reached
      def open_stream
        deadline = @read_timeout && (now + @read_timeout)
        loop do
          raise_if_failed!
          return @client.new_stream
        rescue ::HTTP2::Error::StreamLimitExceeded
          wait_for_stream_slot(deadline)
        end
      rescue ::HTTP2::Error::ConnectionClosed
        raise StreamRefused, "HTTP/2 connection to #{@authority} is no longer taking new streams"
      end

      def wait_for_stream_slot(deadline)
        remaining = deadline && (deadline - now)
        if remaining && !remaining.positive?
          raise Net::ReadTimeout, "no HTTP/2 stream to #{@authority} became available within #{@read_timeout}s"
        end

        @stream_closed.wait(@mutex, remaining)
      end

      def raise_if_failed!
        raise @error.exception(@error.message) if @error
      end

      # Resets a stream the caller gave up on (it raised or timed out) so the server stops sending.
      # Streams that finished, were refused or failed with the connection are no longer tracked.
      def cancel(exchange)
        @mutex.synchronize do
          exchange.stream.cancel if @exchanges.key?(exchange.stream.id)
        end
      end

      # The peer may already be gone; the socket is closed next either way
      def send_goaway
        @client.goaway
      rescue IOError, SystemCallError, OpenSSL::SSL::SSLError => e
        ::ClientApiBuilder.logger&.warn("HTTP/2 connection to #{@authority} failed to send GOAWAY: #{e.message}")
      end

      # Called from the reader thread, holding the mutex
      def stream_closed(stream_id)
        @exchanges.delete(stream_id)
        @stream_closed.broadcast
        close_if_drained
      end

      # Once no new streams may open, the socket closes with the last stream, which ends the reader
      def close_if_drained
        @socket.close if @client.closed? && @exchanges.empty?
      end

      # Streams the server will never process after GOAWAY are safe to retry elsewhere
      def refuse_streams_after(last_stream_id)
        @exchanges.select { |id, _| id > last_stream_id }.each do |id, exchange|
          @exchanges.delete(id)
          exchange.fail(StreamRefused.new("HTTP/2 server at #{@authority} went away before stream #{id} was processed"))
        end
        @stream_closed.broadcast
        close_if_drained
      end

      def read_loop
        loop do
          data = @socket.readpartial(READ_SIZE)
          @mutex.synchronize { @client << data }
        end
      rescue StandardError => e
        fail_connection(e)
      end

      def fail_connection(exception)
        @mutex.synchronize { abort(connection_error(exception)) }
      end

      # Holding the mutex: fails every stream in flight and closes the socket. The first error
      # sticks, so closing the socket (which ends the reader) doesn't replace the real cause.
      def abort(error)
        @error ||= error
        @exchanges.each_value { |exchange| exchange.fail(@error.exception(@error.message)) }
        @exchanges.clear
        @stream_closed.broadcast
        @socket.close
      end

      def connection_error(exception)
        if exception.is_a?(::HTTP2::Error::Error)
          return ProtocolError.new("HTTP/2 protocol error from #{@authority}: #{exception.message}")
        end

        ConnectionLost.new("HTTP/2 connection to #{@authority} lost: #{exception.message} (#{exception.class})")
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
