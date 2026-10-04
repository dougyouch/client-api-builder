# frozen_string_literal: true

require 'spec_helper'
require 'support/http2_server'

describe ClientApiBuilder::HTTP2::ConnectionSet do
  let(:alpn_protocol) { 'h2' }
  let(:server) { HTTP2Server.new(alpn_protocol: alpn_protocol) }
  let(:uri) { URI("#{server.url}/items") }
  let(:options) { { cert_store: server.cert_store, open_timeout: 2, read_timeout: 2 } }
  let(:set) { described_class.new }

  after do
    set.close
    server.stop
  end

  describe '#connection_for' do
    it 'opens one connection per origin and reuses it' do
      connection = set.connection_for(uri, options)

      expect(set.connection_for(URI("#{server.url}/other"), options)).to be(connection)
      expect(server.connections).to eq(1)
    end

    it 'opens a separate connection for different connection options' do
      first = set.connection_for(uri, options)

      expect(set.connection_for(uri, options.merge(read_timeout: 5))).not_to be(first)
    end

    it 'replaces a connection that stopped taking streams' do
      first = set.connection_for(uri, options)
      first.close

      expect(set.connection_for(uri, options)).not_to be(first)
      expect(server.connections).to eq(2)
    end

    it 'starts over after a fork without closing the parent connections' do
      first = set.connection_for(uri, options)
      allow(Process).to receive(:pid).and_return(Process.pid + 1)

      expect(set.connection_for(uri, options)).not_to be(first)
      expect(first).to be_open
      first.close
    end

    context 'when the server chooses HTTP/1.1' do
      let(:alpn_protocol) { 'http/1.1' }

      it 'returns nil and remembers the origin' do
        expect(set.connection_for(uri, options)).to be_nil
        expect(set.connection_for(uri, options)).to be_nil
        expect(server.connections).to eq(1)
      end

      it 'asks again after close' do
        set.connection_for(uri, options)
        set.close
        set.connection_for(uri, options)

        expect(server.connections).to eq(2)
      end
    end
  end

  describe '#close' do
    it 'closes the open connections' do
      connection = set.connection_for(uri, options)
      set.close

      expect(connection).not_to be_open
    end
  end

  describe 'authority' do
    it 'leaves out the default port and keeps IPv6 brackets' do
      expect(set.send(:authority, URI('https://api.example.com/'))).to eq('api.example.com')
      expect(set.send(:authority, URI('https://api.example.com:8443/'))).to eq('api.example.com:8443')
      expect(set.send(:authority, URI('https://[::1]:8443/'))).to eq('[::1]:8443')
    end
  end
end
