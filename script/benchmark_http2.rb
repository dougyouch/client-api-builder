#!/usr/bin/env ruby
# frozen_string_literal: true

# Compares HTTP/1.1 (a new connection per request, and ConnectionPools) with HTTP/2 against a
# local TLS server running in a forked process, so the server's CPU and GVL don't count against
# the client. Each scenario runs its requests across N threads, one client instance per thread.
#
#   bundle exec ruby script/benchmark_http2.rb
#   bundle exec ruby script/benchmark_http2.rb --requests 2000 --threads 1,10,50 --delay 20 --size 50000
#   bundle exec ruby script/benchmark_http2.rb --pool-size 5   # the pools' default max_connections
#
# --delay simulates server work/network latency per response (ms); --size is the body size (bytes);
# --pool-size caps the pooled client's connections (default: one per thread, the pools' best case).
# The server is Ruby too: its HTTP/2 side handles a connection's frames on one thread, while its
# HTTP/1.1 side has a thread per connection, so read the numbers as a rough comparison.

require 'bundler/setup'
require 'json'
require 'openssl'
require 'optparse'
require 'socket'
require 'http/2'
$LOAD_PATH << File.expand_path('../lib', __dir__)
require 'client-api-builder'

module Benchmarks
  # Self-signed certificate for 127.0.0.1, shared by the server and the clients' cert_store
  class Certificate
    attr_reader :key, :cert

    def initialize
      @key = OpenSSL::PKey::EC.generate('prime256v1')
      @cert = build
    end

    def store
      OpenSSL::X509::Store.new.tap { |store| store.add_cert(cert) }
    end

    private

    def build
      name = OpenSSL::X509::Name.parse('/CN=127.0.0.1')
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 1
      cert.subject = cert.issuer = name
      cert.public_key = key
      cert.not_before = Time.now - 60
      cert.not_after = Time.now + 86_400
      factory = OpenSSL::X509::ExtensionFactory.new(cert, cert)
      cert.add_extension(factory.create_extension('subjectAltName', 'IP:127.0.0.1'))
      cert.sign(key, OpenSSL::Digest.new('SHA256'))
    end
  end

  # TLS server speaking whichever protocol the client offers first (h2, else http/1.1),
  # answering every request with a body of body_size bytes after delay seconds
  class Server
    def initialize(certificate, delay:, body_size:)
      @certificate = certificate
      @delay = delay
      @body = 'x' * body_size
    end

    # Forks, serves in the child, and returns [pid, port]
    def start
      reader, writer = IO.pipe
      pid = fork do
        reader.close
        listener = OpenSSL::SSL::SSLServer.new(TCPServer.new('127.0.0.1', 0), ssl_context)
        listener.start_immediately = false
        writer.puts(listener.to_io.addr[1])
        writer.close
        accept_loop(listener)
      end
      writer.close
      [pid, Integer(reader.gets)]
    end

    private

    def ssl_context
      OpenSSL::SSL::SSLContext.new.tap do |context|
        context.cert = @certificate.cert
        context.key = @certificate.key
        context.alpn_select_cb = ->(offered) { offered.include?('h2') ? 'h2' : 'http/1.1' }
      end
    end

    def accept_loop(listener)
      loop do
        socket = listener.accept
        Thread.new { serve(socket) }
      end
    end

    def serve(socket)
      socket.accept
      socket.alpn_protocol == 'h2' ? serve_h2(socket) : serve_http1(socket)
    rescue IOError, SystemCallError, OpenSSL::SSL::SSLError, HTTP2::Error::Error
      socket.close
    end

    def serve_http1(socket)
      while (content_length = read_http1_request(socket))
        socket.read(content_length) if content_length.positive?
        sleep(@delay) if @delay.positive?
        socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: #{@body.bytesize}\r\n\r\n#{@body}")
      end
      socket.close
    end

    # Returns the request's content length, or nil once the client hangs up
    def read_http1_request(socket)
      content_length = 0
      while (line = socket.gets)
        return content_length if line == "\r\n"

        content_length = Integer(line.split(':', 2).last) if line.downcase.start_with?('content-length:')
      end
      nil
    end

    def serve_h2(socket)
      monitor = Monitor.new
      connection = HTTP2::Server.new
      connection.on(:frame) { |bytes| socket.write(bytes) }
      connection.on(:stream) do |stream|
        stream.on(:half_close) { respond_later(stream, monitor) }
      end
      loop do
        data = socket.readpartial(16_384)
        monitor.synchronize { connection << data }
      end
    end

    # Responds from another thread so a delayed response doesn't stall the connection
    def respond_later(stream, monitor)
      Thread.new do
        sleep(@delay) if @delay.positive?
        monitor.synchronize do
          stream.headers({ ':status' => '200', 'content-type' => 'text/plain' }, end_stream: false)
          stream.data(@body)
        end
      end
    end
  end

  # Builds the client class for each transport
  module Clients
    module_function

    def build(transport, url, cert_store, pool_size)
      Class.new do
        include ClientApiBuilder::Router
        include ClientApiBuilder::ConnectionPools if transport == :pooled
        include ClientApiBuilder::HTTP2 if transport == :http2

        base_url url
        connection_option :cert_store, cert_store
        connection_pool max_connections: pool_size, checkout_timeout: 60 if transport == :pooled

        route :get_item, '/items/:id', return: :body
      end
    end
  end

  # Runs one transport x thread-count scenario and reports throughput, latency and client CPU
  class Scenario
    Result = Data.define(:transport, :threads, :requests, :seconds, :latencies, :cpu_seconds) do
      def requests_per_second = requests / seconds
      def percentile(fraction) = latencies[((latencies.size - 1) * fraction).round] * 1000
      def cpu_ms_per_request = cpu_seconds * 1000 / requests
    end

    def initialize(client_class, transport:, threads:, requests:)
      @client_class = client_class
      @transport = transport
      @threads = threads
      @requests = requests
    end

    def run
      warm_up
      cpu_start = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
      started = now
      latencies = Array.new(@threads) { |index| Thread.new { thread_latencies(index) } }.flat_map(&:value)
      seconds = now - started
      cpu = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu_start
      Result.new(@transport, @threads, latencies.size, seconds, latencies.sort, cpu)
    ensure
      @client_class.close_connections if @client_class.respond_to?(:close_connections)
    end

    private

    # Opens the connections up front so the measurement is of steady-state requests
    def warm_up
      Array.new(@threads) { Thread.new { @client_class.new.get_item(id: 0) } }.each(&:join)
    end

    def thread_latencies(index)
      client = @client_class.new
      count = (@requests / @threads) + (index < @requests % @threads ? 1 : 0)
      Array.new(count) do |i|
        started = now
        client.get_item(id: i)
        now - started
      end
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  # Parses the options, runs every scenario against one server, and prints a table
  class Runner
    TRANSPORTS = { new_connection: 'HTTP/1.1 new conn', pooled: 'HTTP/1.1 pooled', http2: 'HTTP/2' }.freeze
    WIDTHS = [8, 11, 10, 10, 13].freeze

    def initialize(argv)
      @options = { requests: 1000, threads: [1, 10, 50], delay: 0, size: 512, pool_size: nil }
      parse(argv)
    end

    def run
      certificate = Certificate.new
      server = Server.new(certificate, delay: @options[:delay] / 1000.0, body_size: @options[:size])
      pid, port = server.start
      print_header
      run_scenarios("https://127.0.0.1:#{port}", certificate.store)
    ensure
      Process.kill('TERM', pid) if pid
    end

    private

    def parse(argv)
      OptionParser.new do |opts|
        opts.banner = 'Usage: bundle exec ruby script/benchmark_http2.rb [options]'
        opts.on('--requests N', Integer, 'requests per scenario (default 1000)') { |v| @options[:requests] = v }
        opts.on('--threads LIST', Array, 'thread counts (default 1,10,50)') { |v| @options[:threads] = v.map(&:to_i) }
        opts.on('--delay MS', Float, 'server delay per response in ms (default 0)') { |v| @options[:delay] = v }
        opts.on('--size BYTES', Integer, 'response body size (default 512)') { |v| @options[:size] = v }
        opts.on('--pool-size N', Integer, 'pooled max_connections (default: threads)') { |v| @options[:pool_size] = v }
      end.parse!(argv)
    end

    def run_scenarios(url, cert_store)
      @options[:threads].each do |threads|
        TRANSPORTS.each_key do |transport|
          client_class = Clients.build(transport, url, cert_store, @options[:pool_size] || threads)
          print_result(Scenario.new(client_class, transport: transport, threads: threads,
                                                  requests: @options[:requests]).run)
        end
        puts
      end
    end

    def print_header
      puts "Ruby #{RUBY_VERSION}, http-2 #{HTTP2::VERSION}; #{@options[:requests]} requests per scenario, " \
           "#{@options[:size]}-byte bodies, #{@options[:delay]}ms server delay, " \
           "pool size #{@options[:pool_size] || 'one per thread'}"
      puts
      print_row('transport', ['threads', 'req/s', 'p50 ms', 'p99 ms', 'CPU ms/req'])
    end

    def print_result(result)
      values = [result.threads.to_s, result.requests_per_second.round.to_s, result.percentile(0.5).round(2).to_s,
                result.percentile(0.99).round(2).to_s, result.cpu_ms_per_request.round(3).to_s]
      print_row(TRANSPORTS.fetch(result.transport), values)
    end

    def print_row(label, values)
      puts "#{label.ljust(18)}#{values.zip(WIDTHS).map { |value, width| value.rjust(width) }.join}"
    end
  end
end

Benchmarks::Runner.new(ARGV).run if $PROGRAM_NAME == __FILE__
