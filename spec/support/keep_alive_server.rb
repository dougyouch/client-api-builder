# frozen_string_literal: true

require 'socket'

# Minimal HTTP/1.1 server on 127.0.0.1 for specs that need real sockets. Answers every
# request with a small JSON body and counts the TCP connections it accepts. With
# close_after_response, it hangs up after each response without saying so, the way a
# server drops an idle keep-alive connection.
class KeepAliveServer
  attr_reader :port

  def initialize(close_after_response: false)
    @close_after_response = close_after_response
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
    @mutex = Mutex.new
    @connections = 0
    @thread = Thread.new { accept_loop }
  end

  def url
    "http://127.0.0.1:#{port}"
  end

  def connections
    @mutex.synchronize { @connections }
  end

  def stop
    @thread.kill
    @server.close
  end

  private

  def accept_loop
    loop do
      socket = @server.accept
      @mutex.synchronize { @connections += 1 }
      Thread.new(socket) { |client| serve(client) }
    end
  end

  def serve(client)
    while request_received?(client)
      client.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 11\r\n\r\n{\"ok\":true}")
      break if @close_after_response
    end
  ensure
    client.close
  end

  # Reads the request line and headers; false once the client has hung up
  def request_received?(client)
    while (line = client.gets)
      return true if line == "\r\n"
    end
    false
  end
end
