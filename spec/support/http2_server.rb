# frozen_string_literal: true

require 'http/2'
require 'openssl'
require 'socket'

# Minimal HTTP/2 server over TLS on 127.0.0.1 for specs. Its self-signed certificate covers
# 127.0.0.1 and localhost; clients trust it through cert_store. ALPN picks alpn_protocol
# (h2 by default; 'http/1.1' makes the server hang up once TLS is up, for fallback specs).
#
# Each complete request is passed to the handler with its stream and server connection, under
# the server's lock. The default handler answers 200 with a JSON body. A handler that answers
# later from another thread wraps its calls in server.synchronize.
class HTTP2Server
  Request = Data.define(:headers, :body) do
    def [](name)
      headers.assoc(name)&.last
    end
  end

  attr_reader :port, :requests, :connections

  def self.respond(stream, status: '200', headers: { 'content-type' => 'application/json' }, body: '{"ok":true}')
    stream.headers({ ':status' => status }.merge(headers), end_stream: body.nil?)
    stream.data(body) if body
  end

  def initialize(alpn_protocol: 'h2', settings: {}, &handler)
    @alpn_protocol = alpn_protocol
    @settings = settings
    @handler = handler || ->(_request, stream, _connection) { self.class.respond(stream) }
    @monitor = Monitor.new
    @requests = Thread::Queue.new
    @connections = 0
    @server = OpenSSL::SSL::SSLServer.new(TCPServer.new('127.0.0.1', 0), ssl_context)
    # the TLS handshake runs on the connection's thread, after it's counted
    @server.start_immediately = false
    @port = @server.to_io.addr[1]
    @threads = []
    @thread = Thread.new { accept_loop }
  end

  def url(host = '127.0.0.1')
    "https://#{host}:#{port}"
  end

  def cert_store
    OpenSSL::X509::Store.new.tap { |store| store.add_cert(certificate) }
  end

  def synchronize(&)
    @monitor.synchronize(&)
  end

  # Serves HTTP/2 on an already connected socket (e.g. one end of a UNIXSocket.pair)
  def attach(socket)
    @threads << Thread.new { serve_h2(socket) }
  end

  def stop
    @thread.kill
    @threads.each(&:kill)
    @server.close
  end

  private

  def accept_loop
    loop do
      socket = accept
      next unless socket

      synchronize { @connections += 1 }
      @threads << Thread.new(socket) { |client| serve(client) }
    end
  end

  def accept
    @server.accept
  rescue SystemCallError
    nil
  end

  def serve(socket)
    socket.accept
    socket.alpn_protocol == 'h2' ? serve_h2(socket) : socket.close
  rescue OpenSSL::SSL::SSLError, SystemCallError
    socket.close
  end

  def serve_h2(socket)
    connection = build_connection(socket)
    loop do
      data = socket.readpartial(16_384)
      synchronize { connection << data }
    end
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError, HTTP2::Error::Error
    socket.close
  end

  def build_connection(socket)
    connection = HTTP2::Server.new(@settings)
    connection.on(:frame) { |bytes| write(socket, bytes) }
    connection.on(:stream) { |stream| collect_request(stream, connection) }
    connection
  end

  def write(socket, bytes)
    socket.write(bytes)
  rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
    nil
  end

  def collect_request(stream, connection)
    headers = []
    body = String.new
    stream.on(:headers) { |pairs| headers.concat(pairs) }
    stream.on(:data) { |chunk| body << chunk }
    stream.on(:half_close) do
      request = Request.new(headers, body)
      @requests << request
      @handler.call(request, stream, connection)
    end
  end

  def ssl_context
    OpenSSL::SSL::SSLContext.new.tap do |context|
      context.cert = certificate
      context.key = key
      context.alpn_select_cb = ->(_offered) { @alpn_protocol }
    end
  end

  def key
    @key ||= OpenSSL::PKey::EC.generate('prime256v1')
  end

  def certificate
    @certificate ||= build_certificate
  end

  def build_certificate
    name = OpenSSL::X509::Name.parse('/CN=localhost')
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = name
    cert.issuer = name
    cert.public_key = key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    extensions = OpenSSL::X509::ExtensionFactory.new(cert, cert)
    cert.add_extension(extensions.create_extension('basicConstraints', 'CA:TRUE', true))
    cert.add_extension(extensions.create_extension('subjectAltName', 'IP:127.0.0.1,DNS:localhost'))
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    cert
  end
end
