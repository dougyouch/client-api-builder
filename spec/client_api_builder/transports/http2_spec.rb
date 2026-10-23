# frozen_string_literal: true

require 'spec_helper'
require 'support/http2_server'

describe ClientApiBuilder::Transports::HTTP2 do
  # Records the URIs it's asked for and sends them with Net::HTTP, so WebMock can answer
  let(:fallback_class) do
    Class.new(ClientApiBuilder::Transports::OneShot) do
      attr_accessor :closed

      def uris
        @uris ||= []
      end

      def with_connection(uri, connection_options, &)
        uris << uri.to_s
        super
      end

      def close
        self.closed = true
      end
    end
  end
  let(:fallback) { fallback_class.new }
  let(:alpn_protocol) { 'h2' }
  let(:server) { HTTP2Server.new(alpn_protocol: alpn_protocol) }
  let(:options) { { use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_PEER, cert_store: server.cert_store } }
  let(:transport) { described_class.new(fallback: fallback) }

  after do
    transport.close
    server.stop
  end

  def get_through(transport, url, connection_options = options)
    uri = URI("#{url}/items/1")
    transport.with_connection(uri, connection_options) { |http| http.request(Net::HTTP::Get.new(uri.request_uri)) }
  end

  it 'falls back to a new connection per request by default' do
    expect(described_class.new.fallback).to be_a(ClientApiBuilder::Transports::OneShot)
  end

  it 'sends https requests over one HTTP/2 connection' do
    2.times { expect(get_through(transport, server.url).http_version).to eq('2.0') }

    expect(server.connections).to eq(1)
    expect(fallback.uris).to be_empty
  end

  it 'sends http requests through the fallback' do
    stub_request(:get, 'http://example.com/items/1').to_return(body: 'http1')

    expect(get_through(transport, 'http://example.com', {}).body).to eq('http1')
    expect(fallback.uris).to eq(['http://example.com/items/1'])
  end

  context 'when the server chooses HTTP/1.1' do
    let(:alpn_protocol) { 'http/1.1' }

    it 'sends the requests through the fallback' do
      stub_request(:get, "#{server.url}/items/1").to_return(body: 'http1')

      expect(get_through(transport, server.url).body).to eq('http1')
      expect(fallback.uris).to eq(["#{server.url}/items/1"])
    end
  end

  describe '#with_fallback' do
    it 'shares the HTTP/2 connections and uses the new fallback' do
      other = transport.with_fallback(ClientApiBuilder::Transports::OneShot.new)

      expect(other.connections).to be(transport.connections)
      expect(other.fallback).not_to be(fallback)
    end
  end

  describe '#close' do
    it 'closes the HTTP/2 connections and the fallback' do
      get_through(transport, server.url)
      transport.close
      get_through(transport, server.url)

      expect(server.connections).to eq(2)
      expect(fallback.closed).to be(true)
    end
  end
end
