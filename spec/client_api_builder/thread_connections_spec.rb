# frozen_string_literal: true

require 'spec_helper'
require 'support/keep_alive_server'
require 'tmpdir'

describe ClientApiBuilder::ThreadConnections do
  let(:client_class) do
    Class.new do
      include ClientApiBuilder::Router
      include ClientApiBuilder::ThreadConnections

      base_url 'http://example.com'

      route :get_user, '/users/:id'
      route :download_report, '/report', stream: :file

      section :orders do
        route :get_order, '/orders/:id'
      end
    end
  end

  def router_class(*modules)
    Class.new do
      include ClientApiBuilder::Router

      modules.each { |mod| include mod }
    end
  end

  describe 'including' do
    it 'requires ClientApiBuilder::Router to be included first' do
      expect { Class.new { include ClientApiBuilder::ThreadConnections } }
        .to raise_error(ArgumentError, 'include ClientApiBuilder::Router before ClientApiBuilder::ThreadConnections')
    end

    it 'configures the connections with the default settings' do
      expect(client_class.thread_connections.settings).to eq(ClientApiBuilder::ThreadConnections::Settings.new)
    end

    it 'cannot be combined with ClientApiBuilder::ConnectionPools, in either order' do
      message = 'include either ClientApiBuilder::ConnectionPools or ClientApiBuilder::ThreadConnections'

      expect { router_class(ClientApiBuilder::ConnectionPools, described_class) }
        .to raise_error(ArgumentError, message)
      expect { router_class(described_class, ClientApiBuilder::ConnectionPools) }
        .to raise_error(ArgumentError, message)
    end

    it 'must come before ClientApiBuilder::HTTP2' do
      expect { router_class(ClientApiBuilder::HTTP2, described_class) }
        .to raise_error(ArgumentError, 'include ClientApiBuilder::ThreadConnections before ClientApiBuilder::HTTP2')
    end
  end

  describe '.connection_per_thread' do
    it 'replaces the class connections with the given settings' do
      client_class.connection_per_thread ttl: 60

      expect(client_class.thread_connections.settings.to_h).to eq(ttl: 60, idle_timeout: 2)
    end

    it 'validates the settings' do
      expect { client_class.connection_per_thread ttl: 0 }.to raise_error(ArgumentError, /ttl/)
    end

    it 'is shared by subclasses unless they configure their own' do
      shared = Class.new(client_class)
      configured = Class.new(client_class) { connection_per_thread ttl: 5 }

      expect(shared.thread_connections).to be(client_class.thread_connections)
      expect(configured.thread_connections).not_to be(client_class.thread_connections)
    end
  end

  describe 'requests' do
    before do
      stub_request(:get, 'http://example.com/users/1').to_return(body: '{"id":1}')
      stub_request(:get, 'http://example.com/orders/2').to_return(body: '{"id":2}')
    end

    it "shares the thread's connection between client instances and their sections" do
      client = client_class.new

      expect(client.get_user(id: 1)).to eq('id' => 1)
      expect(client_class.new.get_user(id: 1)).to eq('id' => 1)
      expect(client.orders.get_order(id: 2)).to eq('id' => 2)

      expect(client_class.thread_connections.size).to eq(1)
    end

    it 'streams through the thread connection' do
      stub_request(:get, 'http://example.com/report').to_return(body: 'a,b,c')
      path = File.join(Dir.mktmpdir, 'report.csv')

      client_class.new.download_report(file: path)

      expect(File.read(path)).to eq('a,b,c')
      expect(client_class.thread_connections.size).to eq(1)
    end

    it 'closes the connections with close_connections' do
      client_class.new.get_user(id: 1)

      client_class.close_connections

      expect(client_class.thread_connections.size).to eq(0)
    end
  end

  describe 'sections' do
    let(:client_class) do
      Class.new do
        include ClientApiBuilder::Router

        base_url 'http://example.com'

        section :reports do
          base_url 'http://reports.example.com'
          connection_per_thread ttl: 10
          route :get_report, '/reports/:id'

          section :exports do
            connection_per_thread
            route :get_export, '/exports/:id'
          end
        end
      end
    end

    before do
      stub_request(:get, %r{\Ahttp://(reports\.)?example\.com/}).to_return(body: '{}')
    end

    it 'gives a section its own connections and settings when the root client has none' do
      client_class.new.reports.get_report(id: 1)

      reports = client_class.reports_router.thread_connections
      expect(reports.size).to eq(1)
      expect(reports.settings.ttl).to eq(10)
      expect(client_class).not_to respond_to(:thread_connections)
    end

    it 'closes nested section connections with the section close_connections' do
      client = client_class.new
      client.reports.get_report(id: 1)
      client.reports.exports.get_export(id: 2)

      client_class.reports_router.close_connections

      expect(client_class.reports_router.thread_connections.size).to eq(0)
      expect(client_class.reports_router.exports_router.thread_connections.size).to eq(0)
    end
  end

  context 'with HTTP2' do
    it 'closes the per-thread connections too' do
      http2_class = router_class(described_class, ClientApiBuilder::HTTP2)
      allow(http2_class.thread_connections).to receive(:close).and_call_original

      http2_class.close_connections

      expect(http2_class.thread_connections).to have_received(:close)
    end
  end

  describe 'against a real server' do
    let(:server) { KeepAliveServer.new }
    let(:client_class) do
      url = server.url
      Class.new do
        include ClientApiBuilder::Router
        include ClientApiBuilder::ThreadConnections

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

    it 'opens exactly one connection per worker thread' do
      ready = Queue.new
      go = Queue.new
      workers = Array.new(20) do
        Thread.new do
          client = client_class.new
          client.get_ping
          ready << true
          go.pop # keep every worker alive so none of their connections are swept
          Array.new(5) { client.get_ping }
        end
      end
      20.times { ready.pop }
      20.times { go << true }

      expect(workers.flat_map(&:value)).to all(eq('ok' => true))
      expect(server.connections).to eq(20)
    end
  end
end
