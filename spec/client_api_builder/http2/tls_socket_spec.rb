# frozen_string_literal: true

require 'spec_helper'
require 'socket'
require 'support/http2_server'

describe ClientApiBuilder::HTTP2::TLSSocket do
  let(:server) { HTTP2Server.new }
  let(:options) { { cert_store: server.cert_store, open_timeout: 2 } }

  after { server.stop }

  describe '.open' do
    it 'negotiates h2 through ALPN and checks the certificate against an IP address' do
      socket = described_class.open('127.0.0.1', server.port, options)

      expect(socket.alpn_protocol).to eq('h2')
      expect(socket.hostname).to be_nil
      socket.close
    end

    it 'sends the host name (SNI) for a named host' do
      socket = described_class.open('localhost', server.port, options)

      expect(socket.hostname).to eq('localhost')
      socket.close
    end

    it 'waits as long as the handshake takes without an open_timeout' do
      socket = described_class.open('127.0.0.1', server.port, options.merge(open_timeout: nil))

      expect(socket.alpn_protocol).to eq('h2')
      socket.close
    end

    it 'rejects a certificate it does not trust' do
      expect { described_class.open('127.0.0.1', server.port, open_timeout: 2) }
        .to raise_error(OpenSSL::SSL::SSLError, /certificate verify failed/)
    end

    it 'rejects a certificate for another host' do
      tcp = Socket.method(:tcp)
      allow(Socket).to receive(:tcp) { |_host, _port, **kwargs| tcp.call('127.0.0.1', server.port, **kwargs) }

      expect { described_class.open('api.example.com', server.port, options) }
        .to raise_error(OpenSSL::SSL::SSLError, /certificate verify failed|hostname/)
    end

    it 'skips verification with VERIFY_NONE' do
      socket = described_class.open('127.0.0.1', server.port, verify_mode: OpenSSL::SSL::VERIFY_NONE, open_timeout: 2)

      expect(socket.alpn_protocol).to eq('h2')
      socket.close
    end

    it 'skips the host name check when verify_hostname is false' do
      socket = described_class.open('127.0.0.1', server.port, options.merge(verify_hostname: false))

      expect(socket.alpn_protocol).to eq('h2')
      socket.close
    end

    it 'raises Net::OpenTimeout and closes the socket when the handshake stalls' do
      silent = TCPServer.new('127.0.0.1', 0)
      tcp = nil
      allow(Socket).to(receive(:tcp).and_wrap_original { |original, *args, **kwargs| tcp = original.call(*args, **kwargs) })

      expect { described_class.open('127.0.0.1', silent.addr[1], open_timeout: 0.1) }
        .to raise_error(Net::OpenTimeout, 'TLS handshake timed out')
      expect(tcp).to be_closed
    ensure
      silent.close
    end
  end

  describe '.ssl_context' do
    it "applies Net::HTTP's SSL options, skipping unset ones" do
      context = described_class.ssl_context(ssl_timeout: 7, verify_depth: 3, ca_file: nil)

      expect(context.timeout).to eq(7)
      expect(context.verify_depth).to eq(3)
      expect(context.verify_mode).to eq(OpenSSL::SSL::VERIFY_PEER)
    end
  end
end
