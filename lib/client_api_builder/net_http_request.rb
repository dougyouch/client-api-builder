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
        # Use dup to avoid mutating the original hash
        opts = connection_options.dup
        mode = opts.delete(:file_mode)

        # Validate file mode - use whitelist approach
        mode = if mode.nil?
                 'wb'
               elsif ALLOWED_FILE_MODES.include?(mode.to_s)
                 mode.to_s
               else
                 raise ArgumentError, "Invalid file mode: #{mode.inspect}. Allowed modes: #{ALLOWED_FILE_MODES.join(', ')}"
               end

        # Validate file path - expand to absolute path and check for path traversal
        expanded_path = File.expand_path(file)
        raise ArgumentError, 'Invalid file path: potential path traversal detected' if file.to_s.include?('..') || expanded_path.include?("\0")

        File.open(expanded_path, mode) do |io|
          stream_to_io(method: method, uri: uri, body: body, headers: headers, connection_options: opts, io: io)
        end
      end
    end
  end
end
