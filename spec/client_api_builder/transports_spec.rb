# frozen_string_literal: true

require 'spec_helper'
require 'support/keep_alive_server'

describe ClientApiBuilder::Transports do
  # Records the URIs it sends, so specs can see which transport a request went through
  let(:recording_class) do
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
  let(:transport) { recording_class.new }
  let(:other) { recording_class.new }
  let(:client_class) do
    Class.new do
      include ClientApiBuilder::Router

      base_url 'http://example.com'
      route :get_user, '/users/:id'

      section :orders do
        route :get_order, '/orders/:id'
      end
    end
  end

  before { stub_request(:get, %r{\Ahttp://example\.com/}).to_return(body: '{}') }

  after { ClientApiBuilder.transports.reset }

  describe 'ClientApiBuilder.use_transport' do
    it 'sets the transport for every client' do
      ClientApiBuilder.use_transport(transport)
      client_class.new.get_user(id: 1)

      expect(transport.uris).to eq(['http://example.com/users/1'])
    end

    it 'sets the transport for one client class and its subclasses' do
      ClientApiBuilder.use_transport(transport, client_class)
      Class.new(client_class).new.get_user(id: 1)

      expect(transport.uris).to eq(['http://example.com/users/1'])
      expect(ClientApiBuilder.transports.for_class(Class.new)).to be_a(ClientApiBuilder::Transports::OneShot)
    end

    it 'takes precedence over the transport a class includes, whichever comes first' do
      ClientApiBuilder.use_transport(transport, client_class)
      client_class.include ClientApiBuilder::ConnectionPools
      client_class.new.get_user(id: 1)

      expect(transport.uris).to eq(['http://example.com/users/1'])
      expect(client_class.connection_pools.pools).to be_empty
    end
  end

  describe 'Router#transport=' do
    it 'sends that client instance through the transport' do
      ClientApiBuilder.use_transport(other, client_class)
      client = client_class.new
      client.transport = transport
      client.get_user(id: 1)
      client_class.new.get_user(id: 2)

      expect(transport.uris).to eq(['http://example.com/users/1'])
      expect(other.uris).to eq(['http://example.com/users/2'])
    end
  end

  describe 'sections' do
    it "use the root client's transport" do
      client = client_class.new
      client.transport = transport
      client.orders.get_order(id: 1)

      expect(transport.uris).to eq(['http://example.com/orders/1'])
    end

    it 'use a transport set on the section or registered for its class' do
      client = client_class.new
      client.transport = other
      client.orders.transport = transport
      client.orders.get_order(id: 1)
      ClientApiBuilder.use_transport(transport, client_class.orders_router)
      client_class.new.orders.get_order(id: 2)

      expect(transport.uris).to eq(['http://example.com/orders/1', 'http://example.com/orders/2'])
      expect(other.uris).to be_empty
    end
  end

  describe 'ClientApiBuilder.close_transports' do
    it 'closes every registered transport' do
      ClientApiBuilder.use_transport(transport)
      ClientApiBuilder.use_transport(other, client_class)

      ClientApiBuilder.close_transports

      expect([transport.closed, other.closed]).to eq([true, true])
    end
  end

  describe 'one client class in different environments' do
    let(:server) { KeepAliveServer.new }
    let(:client_class) do
      url = server.url
      Class.new do
        include ClientApiBuilder::Router

        base_url url
        route :get_ping, '/ping'
      end
    end

    around do |example|
      WebMock.disable_net_connect!(allow_localhost: true)
      example.run
    ensure
      ClientApiBuilder.close_transports
      server.stop
      WebMock.disable_net_connect!
    end

    def three_pings
      client = client_class.new
      3.times { expect(client.get_ping).to eq('ok' => true) }
      server.connections
    end

    it 'opens a connection per request in a web server' do
      ClientApiBuilder.use_transport(ClientApiBuilder::Transports::OneShot.new)

      expect(three_pings).to eq(3)
    end

    it 'keeps a connection per thread in a background worker' do
      ClientApiBuilder.use_transport(ClientApiBuilder::Transports::ThreadLocal.new(ttl: 30))

      expect(three_pings).to eq(1)
    end

    it 'shares pooled connections when registered for the class' do
      ClientApiBuilder.use_transport(ClientApiBuilder::Transports::Pooled.new(max_connections: 10), client_class)

      expect(three_pings).to eq(1)
    end
  end
end
