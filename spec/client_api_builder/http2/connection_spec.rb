# frozen_string_literal: true

require 'spec_helper'
require 'logger'
require 'socket'
require 'stringio'
require 'support/http2_server'

describe ClientApiBuilder::HTTP2::Connection do
  let(:handler) { nil }
  let(:server_settings) { {} }
  let(:server) { HTTP2Server.new(settings: server_settings, &handler) }
  let(:sockets) { UNIXSocket.pair }
  let(:client_socket) { sockets.first }
  let(:server_socket) { sockets.last }
  let(:read_timeout) { 2 }
  let!(:connection) { described_class.new(client_socket, 'api.example.test', read_timeout) }

  before { server.attach(server_socket) }

  after do
    connection.close
    server.stop
  end

  def get(path)
    connection.request(Net::HTTP::Get.new(path))
  end

  # A thread whose expected exception isn't reported on stderr
  def in_thread(&block)
    Thread.new do
      Thread.current.report_on_exception = false
      block.call
    end
  end

  def wait_until(timeout: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    sleep 0.01 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  describe '#request' do
    it 'returns the response with its body read' do
      response = get('/items')

      expect(response).to be_a(Net::HTTPOK)
      expect(response.body).to eq('{"ok":true}')
      expect(server.requests.pop[':authority']).to eq('api.example.test')
    end

    it 'yields the response before its body is read' do
      chunks = []
      response = connection.request(Net::HTTP::Get.new('/items')) do |res|
        res.read_body { |chunk| chunks << chunk }
      end

      expect(chunks.join).to eq('{"ok":true}')
      expect(response.code).to eq('200')
    end

    it 'sends the request body' do
      request = Net::HTTP::Post.new('/items', 'Content-Type' => 'application/json')
      request.body = '{"name":"widget"}'
      connection.request(request)

      sent = server.requests.pop
      expect(sent.body).to eq('{"name":"widget"}')
      expect(sent['content-length']).to eq('17')
    end

    it 'carries concurrent requests on the one connection' do
      responses = Array.new(5) { |i| Thread.new { get("/items/#{i}") } }.map(&:value)

      expect(responses.map(&:code)).to all(eq('200'))
    end

    context 'when the server resets the stream' do
      let(:handler) { ->(_request, stream, _connection) { stream.close(:internal_error) } }

      it 'raises StreamError' do
        expect { get('/items') }.to raise_error(ClientApiBuilder::HTTP2::StreamError, /internal_error/)
        expect(connection).to be_open
      end
    end

    context 'when the server refuses the stream' do
      let(:handler) { ->(_request, stream, _connection) { stream.refuse } }

      it 'raises StreamRefused, which is retryable' do
        expect { get('/items') }.to raise_error(ClientApiBuilder::HTTP2::StreamRefused)
      end
    end

    context 'when the response does not arrive within read_timeout' do
      let(:read_timeout) { 0.1 }
      let(:resets) { Thread::Queue.new }
      let(:handler) do
        queue = resets
        ->(_request, stream, _connection) { stream.on(:close) { |error| queue << error } }
      end

      it 'raises Net::ReadTimeout and resets the stream' do
        expect { get('/never') }.to raise_error(Net::ReadTimeout)
        expect(resets.pop(timeout: 2)).to eq(:cancel)
      end
    end
  end

  describe 'stream limit' do
    let(:server_settings) { { settings_max_concurrent_streams: 1 } }
    let(:held) { Thread::Queue.new }
    let(:handler) do
      queue = held
      lambda do |request, stream, _connection|
        case request[':path']
        when '/slow' then queue << stream
        when '/open' then stream.headers({ ':status' => '200' }, end_stream: false)
        else HTTP2Server.respond(stream)
        end
      end
    end

    before { get('/warm-up') } # receives the server's SETTINGS

    def respond_to_held
      stream = held.pop
      server.synchronize { HTTP2Server.respond(stream) }
    end

    it 'waits for a stream to free up' do
      slow = Thread.new { get('/slow') }
      fast = Thread.new { get('/fast') }
      wait_until { fast.status == 'sleep' }
      respond_to_held

      expect([slow.value.code, fast.value.code]).to eq(%w[200 200])
    end

    context 'without a read_timeout' do
      let(:read_timeout) { nil }

      it 'waits as long as it takes' do
        slow = Thread.new { get('/slow') }
        fast = Thread.new { get('/fast') }
        wait_until { fast.status == 'sleep' }
        respond_to_held

        expect([slow.value.code, fast.value.code]).to eq(%w[200 200])
      end
    end

    context 'when no stream frees up within read_timeout' do
      let(:read_timeout) { 0.2 }

      it 'raises Net::ReadTimeout' do
        # holds the only stream open by not reading the body
        holding = in_thread { connection.request(Net::HTTP::Get.new('/open')) { sleep 0.5 } }
        wait_until { holding.status == 'sleep' }

        expect { get('/fast') }.to raise_error(Net::ReadTimeout, %r{no HTTP/2 stream to api.example.test became available})
        expect { holding.value }.to raise_error(Net::ReadTimeout)
      end
    end
  end

  describe 'GOAWAY from the server' do
    let(:held) { Thread::Queue.new }
    let(:handler) do
      queue = held
      lambda do |request, stream, server_connection|
        case request[':path']
        when '/hold' then queue << stream
        when '/goaway'
          server_connection.__send__(:send, type: :goaway, stream: 0, last_stream: stream.id - 2, error: :no_error)
        else HTTP2Server.respond(stream)
        end
      end
    end

    it 'refuses streams the server will not process, finishes the rest, then closes' do
      hold = Thread.new { get('/hold') }
      stream = held.pop

      expect { get('/goaway') }.to raise_error(ClientApiBuilder::HTTP2::StreamRefused, /went away before stream/)
      expect(connection).not_to be_open
      expect { get('/after') }.to raise_error(ClientApiBuilder::HTTP2::StreamRefused, /no longer taking new streams/)

      server.synchronize { HTTP2Server.respond(stream) }
      expect(hold.value.code).to eq('200')
      expect { client_socket.read_nonblock(1) }.to raise_error(IOError)
    end

    it 'closes at once when nothing is in flight' do
      hold = Thread.new { get('/hold') }
      stream = held.pop
      server.synchronize { HTTP2Server.respond(stream) }
      hold.join
      expect { get('/goaway') }.to raise_error(ClientApiBuilder::HTTP2::StreamRefused)

      wait_until { client_socket.closed? }
      expect(client_socket).to be_closed
    end
  end

  describe 'connection failures' do
    it 'fails requests in flight with ConnectionLost when the server hangs up' do
      server.stop
      pending_request = in_thread { get('/items') }
      wait_until { pending_request.status == 'sleep' }
      server_socket.close

      expect { pending_request.value }.to raise_error(ClientApiBuilder::HTTP2::ConnectionLost, /api.example.test lost/)
      expect(connection).not_to be_open
      expect { get('/items') }.to raise_error(ClientApiBuilder::HTTP2::ConnectionLost)
    end

    it 'fails with ProtocolError when the server breaks the protocol' do
      server.stop
      pending_request = in_thread { get('/items') }
      wait_until { pending_request.status == 'sleep' }
      server_socket.write(HTTP2::Framer.new.generate(type: :ping, stream: 0, flags: 0, payload: '12345678'))

      expect { pending_request.value }.to raise_error(ClientApiBuilder::HTTP2::ProtocolError, /protocol error/)
    end
  end

  describe '#close' do
    it 'sends GOAWAY and fails new requests' do
      get('/items')
      connection.close

      expect(connection).not_to be_open
      expect { get('/items') }.to raise_error(ClientApiBuilder::HTTP2::ConnectionLost, /was closed/)
    end

    it 'skips GOAWAY once the connection has failed' do
      server.stop
      server_socket.close
      wait_until { !connection.open? }

      expect { connection.close }.not_to raise_error
    end

    it 'skips GOAWAY once the server has sent one' do
      server.stop
      server_socket.write(HTTP2::Framer.new.generate(type: :settings, stream: 0, payload: []))
      server_socket.write(HTTP2::Framer.new.generate(type: :goaway, stream: 0, last_stream: 0, error: :no_error))
      wait_until { !connection.open? }

      expect { connection.close }.not_to raise_error
    end

    context 'when GOAWAY cannot be sent' do
      before do
        get('/items')
        allow(client_socket).to receive(:write).and_raise(Errno::EPIPE)
      end

      after { ClientApiBuilder.logger = nil }

      it 'logs and still closes' do
        log = StringIO.new
        ClientApiBuilder.logger = Logger.new(log)
        connection.close

        expect(log.string).to include('failed to send GOAWAY: Broken pipe')
        expect(client_socket).to be_closed
      end

      it 'closes without a logger' do
        connection.close

        expect(client_socket).to be_closed
      end
    end
  end
end
