# frozen_string_literal: true

require 'net/http'
require 'openssl'

module ClientApiBuilder
  module NetHTTP
    module Request
      # Allowed file modes for stream_to_file to prevent arbitrary mode injection
      ALLOWED_FILE_MODES = %w[w wb a ab w+ wb+ a+ ab+].freeze

      # Default connection options with secure SSL settings
      DEFAULT_SECURE_OPTIONS = {
        verify_mode: OpenSSL::SSL::VERIFY_PEER,
        open_timeout: 30,
        read_timeout: 60
      }.freeze

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
      }.freeze

      def request(method:, uri:, body:, headers:, connection_options:)
        request = METHOD_TO_NET_HTTP_CLASS[method].new(uri.request_uri, headers)
        request.body = body if body

        # Merge secure defaults, then user options, ensuring SSL verification is enabled for HTTPS
        ssl_options = uri.scheme == 'https' ? DEFAULT_SECURE_OPTIONS.merge(use_ssl: true) : {}
        merged_options = ssl_options.merge(connection_options)

        Net::HTTP.start(uri.hostname, uri.port, merged_options) do |http|
          http.request(request) do |response|
            yield response if block_given?
          end
        end
      end

      # validate_response, when given, is called with the response before its body is streamed
      # and raises to reject it. A rejected body is read into response.body instead of being
      # streamed, so the error can still show it.
      def stream(method:, uri:, body:, headers:, connection_options:, validate_response: nil)
        request(method: method, uri: uri, body: body, headers: headers,
                connection_options: connection_options) do |response|
          validate_streamed_response(response, validate_response) if validate_response
          response.read_body do |chunk|
            yield response, chunk
          end
        end
      end

      def stream_to_io(method:, uri:, body:, headers:, connection_options:, io:, validate_response: nil)
        stream(method: method, uri: uri, body: body, headers: headers,
               connection_options: connection_options, validate_response: validate_response) do |_, chunk|
          io.write chunk
        end
      end

      # The file is opened only once the response has passed validate_response, so a rejected
      # response never creates, truncates or appends to it.
      def stream_to_file(method:, uri:, body:, headers:, connection_options:, file:, validate_response: nil)
        # Use dup to avoid mutating the original hash
        opts = connection_options.dup
        mode = stream_file_mode(opts.delete(:file_mode))
        path = stream_file_path(file)

        io = nil
        open_file = lambda do |response|
          validate_response&.call(response)
          io = File.open(path, mode) # rubocop:disable Style/FileOpen -- closed in ensure
        end
        stream(method: method, uri: uri, body: body, headers: headers,
               connection_options: opts, validate_response: open_file) do |_, chunk|
          io.write chunk
        end
      ensure
        io&.close
      end

      private

      def validate_streamed_response(response, validate_response)
        validate_response.call(response)
      rescue StandardError
        response.read_body
        raise
      end

      # Validate file mode - use whitelist approach
      def stream_file_mode(mode)
        return 'wb' if mode.nil?
        return mode.to_s if ALLOWED_FILE_MODES.include?(mode.to_s)

        raise ArgumentError, "Invalid file mode: #{mode.inspect}. Allowed modes: #{ALLOWED_FILE_MODES.join(', ')}"
      end

      # Validate file path - expand to absolute path and check for path traversal
      def stream_file_path(file)
        expanded_path = File.expand_path(file)
        if file.to_s.include?('..') || expanded_path.include?("\0")
          raise ArgumentError, 'Invalid file path: potential path traversal detected'
        end

        expanded_path
      end
    end
  end
end
