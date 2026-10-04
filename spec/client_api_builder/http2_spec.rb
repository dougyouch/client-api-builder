# frozen_string_literal: true

require 'spec_helper'
require 'support/http2_server'
require 'tempfile'
require 'zlib'

describe ClientApiBuilder::HTTP2 do
  let(:handler) { nil }
  let(:alpn_protocol) { 'h2' }
  let(:server) { HTTP2Server.new(alpn_protocol: alpn_protocol, &handler) }
  let(:client_class) do
    url = server.url
    store = server.cert_store
    Class.new do
      include ClientApiBuilder::Router
      include ClientApiBuilder::HTTP2

      base_url url
      connection_option :cert_store, store

      route :get_item, '/items/:id'
      route :create_item, '/items', body: { name: :name }
      route :head_item, '/items/:id', method: :head, return: :response
      route :download, '/report', stream: :file
      route :download_chunks, '/report', stream: :block

      section :orders, inherit: [:connection_options] do
        route :get_order, '/orders/:id'
      end
    end
  end
  let(:client) { client_class.new }

  after do
    client_class.close_connections
    server.stop
  end

  def requests
    Array.new(server.requests.size) { server.requests.pop }
  end

  describe 'including' do
    it 'requires ClientApiBuilder::Router to be included first' do
      expect { Class.new { include ClientApiBuilder::HTTP2 } }
        .to raise_error(ArgumentError, 'include ClientApiBuilder::Router before ClientApiBuilder::HTTP2')
    end

    it 'explains how to install the http-2 gem when it is missing' do
      allow(described_class).to receive(:require).with('http/2').and_raise(LoadError)

      expect { described_class.require_http2_gem }
        .to raise_error(LoadError, "ClientApiBuilder::HTTP2 needs the http-2 gem; add gem 'http-2' to your Gemfile")
      allow(described_class).to receive(:require).and_call_original
    end

    it 'shares the connections with subclasses' do
      expect(Class.new(client_class).http2_connections).to be(client_class.http2_connections)
    end

    it 'must come after ClientApiBuilder::ConnectionPools' do
      expect { Class.new(client_class) { include ClientApiBuilder::ConnectionPools } }
        .to raise_error(ArgumentError, 'include ClientApiBuilder::ConnectionPools before ClientApiBuilder::HTTP2')
    end
  end

  describe 'requests' do
    it 'sends https requests over one HTTP/2 connection' do
      expect(client.get_item(id: 1)).to eq('ok' => true)
      expect(client.response.http_version).to eq('2.0')
      expect(client.create_item(name: 'widget')).to eq('ok' => true)
      Array.new(5) { |i| Thread.new { client_class.new.get_item(id: i) } }.each(&:join)

      expect(server.connections).to eq(1)
      expect(requests.map { |request| request[':path'] }.first(2)).to eq(['/items/1', '/items'])
    end

    it 'sends section requests over the root client connection' do
      client.get_item(id: 1)

      expect(client.orders.get_order(id: 2)).to eq('ok' => true)
      expect(server.connections).to eq(1)
    end

    it 'returns no body for a HEAD request' do
      response = client.head_item(id: 1)

      expect(response).to be_a(Net::HTTPOK)
      expect(response.body).to be_nil
    end

    it 'streams a response to a file' do
      Tempfile.create('report') do |file|
        client.download(file: file.path)

        expect(File.read(file.path)).to eq('{"ok":true}')
      end
    end

    it 'streams a response to a block' do
      chunks = []
      client.download_chunks { |_response, chunk| chunks << chunk }

      expect(chunks.join).to eq('{"ok":true}')
    end

    context 'when the server compresses the response' do
      let(:handler) do
        lambda do |_request, stream, _connection|
          HTTP2Server.respond(stream, headers: { 'content-type' => 'application/json', 'content-encoding' => 'gzip' },
                                      body: Zlib.gzip('{"ok":true}'))
        end
      end

      it 'inflates it' do
        expect(client.get_item(id: 1)).to eq('ok' => true)
      end
    end

    context 'when the server refuses a stream' do
      let(:handler) do
        refused = false
        lambda do |_request, stream, _connection|
          next HTTP2Server.respond(stream) if refused

          refused = true
          stream.refuse
        end
      end

      it 'retries it' do
        client_class.configure_retries 2, 0

        expect(client.get_item(id: 1)).to eq('ok' => true)
        expect(client.request_attempts).to eq(2)
      end
    end

    context 'when the server chooses HTTP/1.1' do
      let(:alpn_protocol) { 'http/1.1' }

      it 'sends the requests through Net::HTTP' do
        stub_request(:get, %r{\A#{server.url}/items/\d\z}).to_return(body: '{"via":"http1"}')

        expect(client.get_item(id: 1)).to eq('via' => 'http1')
        expect(client.get_item(id: 2)).to eq('via' => 'http1')
        expect(client.response.http_version).not_to eq('2.0')
        expect(server.connections).to eq(1)
      end
    end

    it 'sends http requests through Net::HTTP' do
      client_class.base_url 'http://example.com'
      stub_request(:get, 'http://example.com/items/1').to_return(body: '{"via":"http1"}')

      expect(client.get_item(id: 1)).to eq('via' => 'http1')
      expect(server.connections).to eq(0)
    end
  end

  describe '.close_connections' do
    it 'closes the HTTP/2 connections' do
      client.get_item(id: 1)
      client_class.close_connections
      client.get_item(id: 2)

      expect(server.connections).to eq(2)
    end

    context 'with connection pools' do
      let(:pooled_class) do
        Class.new do
          include ClientApiBuilder::Router
          include ClientApiBuilder::ConnectionPools
          include ClientApiBuilder::HTTP2
        end
      end

      it 'closes the pools too' do
        allow(pooled_class.connection_pools).to receive(:close).and_call_original
        pooled_class.close_connections

        expect(pooled_class.connection_pools).to have_received(:close)
      end
    end
  end
end
