# frozen_string_literal: true

require 'spec_helper'
require 'support/keep_alive_server'
require 'tmpdir'

describe ClientApiBuilder::ConnectionPools do
  let(:client_class) do
    Class.new do
      include ClientApiBuilder::Router
      include ClientApiBuilder::ConnectionPools

      base_url 'http://example.com'

      route :get_user, '/users/:id'
      route :download_report, '/report', stream: :file

      section :orders do
        route :get_order, '/orders/:id'
      end
    end
  end

  describe 'including' do
    it 'requires ClientApiBuilder::Router to be included first' do
      expect { Class.new { include ClientApiBuilder::ConnectionPools } }
        .to raise_error(ArgumentError, 'include ClientApiBuilder::Router before ClientApiBuilder::ConnectionPools')
    end

    it 'configures pools with the default settings' do
      expect(client_class.connection_pools.settings)
        .to eq(ClientApiBuilder::ConnectionPools::Settings.new)
    end

    it 'leaves clients that do not include it without pools' do
      plain = Class.new { include ClientApiBuilder::Router }

      expect(plain).not_to respond_to(:connection_pools)
    end
  end

  describe '.connection_pool' do
    it 'replaces the class pools with the given settings' do
      client_class.connection_pool max_connections: 10, ttl: 60

      expect(client_class.connection_pools.settings.to_h)
        .to eq(max_connections: 10, ttl: 60, checkout_timeout: 5, idle_timeout: 2)
    end

    it 'validates the settings' do
      expect { client_class.connection_pool max_connections: 0 }.to raise_error(ArgumentError, /max_connections/)
    end

    it 'is shared by subclasses unless they configure their own' do
      shared = Class.new(client_class)
      configured = Class.new(client_class) { connection_pool max_connections: 2 }

      expect(shared.connection_pools).to be(client_class.connection_pools)
      expect(configured.connection_pools).not_to be(client_class.connection_pools)
      expect(client_class.connection_pools.settings.max_connections).to eq(5)
    end
  end

  describe 'requests' do
    before do
      stub_request(:get, 'http://example.com/users/1').to_return(body: '{"id":1}')
      stub_request(:get, 'http://example.com/orders/2').to_return(body: '{"id":2}')
    end

    let(:pool) { client_class.connection_pools.pools.first }

    it 'shares one pool between client instances' do
      expect(client_class.new.get_user(id: 1)).to eq('id' => 1)
      expect(client_class.new.get_user(id: 1)).to eq('id' => 1)

      expect(client_class.connection_pools.pools.size).to eq(1)
      expect(pool.size).to eq(1)
      expect(pool.idle_size).to eq(1)
    end

    it 'uses the root client pools for sections' do
      client = client_class.new

      client.get_user(id: 1)
      expect(client.orders.get_order(id: 2)).to eq('id' => 2)

      expect(pool.size).to eq(1)
    end

    it 'streams through a pooled connection' do
      stub_request(:get, 'http://example.com/report').to_return(body: 'a,b,c')
      path = File.join(Dir.mktmpdir, 'report.csv')

      client_class.new.download_report(file: path)

      expect(File.read(path)).to eq('a,b,c')
      expect(pool.idle_size).to eq(1)
    end

    it 'closes the pools with close_connections' do
      client_class.new.get_user(id: 1)

      client_class.close_connections

      expect(pool.size).to eq(0)
    end
  end

  describe 'sections' do
    let(:client_class) do
      Class.new do
        include ClientApiBuilder::Router
        include ClientApiBuilder::ConnectionPools

        base_url 'http://example.com'
        route :get_user, '/users/:id'

        section :orders do
          route :get_order, '/orders/:id'
        end

        section :uploads do
          base_url 'http://uploads.example.com'
          route :get_upload, '/uploads/:id'
        end

        section :reports do
          base_url 'http://reports.example.com'
          connection_pool max_connections: 2, ttl: 10
          route :get_report, '/reports/:id'

          section :exports do
            route :get_export, '/exports/:id'
          end
        end
      end
    end

    let(:client) { client_class.new }

    before do
      stub_request(:get, %r{\Ahttp://(uploads\.|reports\.)?example\.com/}).to_return(body: '{}')
    end

    def pool_hosts(pool_set)
      pool_set.pools.map(&:host)
    end

    it 'gives a section with its own base_url a separate pool in the root client pools' do
      client.get_user(id: 1)
      client.orders.get_order(id: 2)
      client.uploads.get_upload(id: 3)

      expect(pool_hosts(client_class.connection_pools)).to contain_exactly('example.com', 'uploads.example.com')
      expect(client_class.connection_pools.pools.map(&:size)).to eq([1, 1])
    end

    it 'uses its own pools and settings in a section that calls connection_pool' do
      client.reports.get_report(id: 1)

      reports_pools = client_class.reports_router.connection_pools
      expect(pool_hosts(reports_pools)).to eq(['reports.example.com'])
      expect(reports_pools.settings.to_h).to include(max_connections: 2, ttl: 10)
      expect(client_class.connection_pools.pools).to be_empty
    end

    it 'uses the root client pools, like its base_url, in a section nested in a pooled one' do
      client.reports.exports.get_export(id: 1)

      expect(pool_hosts(client_class.connection_pools)).to eq(['example.com'])
      expect(client_class.reports_router.connection_pools.pools).to be_empty
    end

    it 'gives a section its own pools when the root client has none' do
      plain = Class.new do
        include ClientApiBuilder::Router

        base_url 'http://example.com'
        section(:pooled) { connection_pool max_connections: 1 }
      end
      plain.pooled_router.route :get_user, '/users/:id'

      plain.new.pooled.get_user(id: 1)

      expect(plain.pooled_router.connection_pools.pools.first.idle_size).to eq(1)
      expect(plain).not_to respond_to(:connection_pools)
    end

    it 'closes section pools, including nested ones, with the root client close_connections' do
      client_class.section(:outer) { section(:inner) { connection_pool } }
      client_class.outer_router.inner_router.route :get_user, '/users/:id'
      client.reports.get_report(id: 1)
      client.outer.inner.get_user(id: 1)

      client_class.close_connections

      expect(client_class.reports_router.connection_pools.pools.map(&:size)).to eq([0])
      expect(client_class.outer_router.inner_router.connection_pools.pools.map(&:size)).to eq([0])
    end
  end

  describe 'against a real server' do
    let(:server) { KeepAliveServer.new }
    let(:client_class) do
      url = server.url
      Class.new do
        include ClientApiBuilder::Router
        include ClientApiBuilder::ConnectionPools

        base_url url
        route :get_ping, '/ping'
      end
    end

    around do |example|
      WebMock.disable_net_connect!(allow_localhost: true)
      example.run
    ensure
      server.stop
      client_class.close_connections
      WebMock.disable_net_connect!
    end

    it 'reuses one TCP connection for sequential requests' do
      client = client_class.new
      3.times { expect(client.get_ping).to eq('ok' => true) }

      expect(server.connections).to eq(1)
    end

    it 'never opens more than max_connections across threads' do
      client_class.connection_pool max_connections: 3
      threads = Array.new(6) do
        Thread.new do
          client = client_class.new
          Array.new(5) { client.get_ping }
        end
      end

      expect(threads.flat_map(&:value)).to all(eq('ok' => true))
      expect(server.connections).to be_between(1, 3)
    end

    it 'reconnects once the ttl has passed' do
      client_class.connection_pool ttl: 0.05
      client = client_class.new

      client.get_ping
      sleep 0.06
      client.get_ping

      expect(server.connections).to eq(2)
    end

    context 'when the server closes connections after each response' do
      let(:server) { KeepAliveServer.new(close_after_response: true) }

      it 'reopens the socket automatically' do
        client = client_class.new
        3.times do
          expect(client.get_ping).to eq('ok' => true)
          sleep 0.02 # let the server hang up before the next request
        end

        expect(server.connections).to eq(3)
      end
    end
  end
end
