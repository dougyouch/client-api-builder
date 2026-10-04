# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::ThreadConnections::ConnectionSet do
  let(:time) { [1000.0] }
  let(:clock) { -> { time[0] } }
  let(:settings) { ClientApiBuilder::ThreadConnections::Settings.new(ttl: 30, idle_timeout: 4) }
  let(:connection_set) { described_class.new(settings, clock: clock) }
  let(:uri) { URI('http://example.com/users') }
  let(:options) { { read_timeout: 7 } }

  def checkout_http(target = uri, connection_options = options)
    connection_set.with_connection(target, connection_options) { |http| http }
  end

  def in_thread(&)
    Thread.new(&).value
  end

  describe '#with_connection' do
    it 'yields a started session with the connection options and returns the block result' do
      result = connection_set.with_connection(uri, options) do |http|
        expect(http).to be_started
        expect(http.read_timeout).to eq(7)
        :done
      end

      expect(result).to eq(:done)
    end

    it 'passes idle_timeout to Net::HTTP as keep_alive_timeout' do
      expect(connection_set.with_connection(uri, options, &:keep_alive_timeout)).to eq(4)
    end

    it 'lets a keep_alive_timeout connection option override idle_timeout' do
      expect(connection_set.with_connection(uri, { keep_alive_timeout: 9 }, &:keep_alive_timeout)).to eq(9)
    end

    it "reuses the thread's connection" do
      first = checkout_http

      expect(checkout_http).to be(first)
      expect(first).to be_started
      expect(connection_set.size).to eq(1)
    end

    it 'keeps a connection per scheme, host, port and connection options' do
      connections = [
        checkout_http,
        checkout_http(URI('https://example.com/users')),
        checkout_http(URI('http://example.com:8080/users')),
        checkout_http(URI('http://other.example.com/users')),
        checkout_http(uri, { read_timeout: 8 })
      ]

      expect(connections.uniq.size).to eq(5)
      expect(connection_set.size).to eq(5)
    end

    it 'gives each thread its own connection' do
      main = checkout_http
      other = in_thread { checkout_http }

      expect(other).not_to be(main)
      expect(checkout_http).to be(main)
      expect(connection_set.size).to eq(2)
    end

    it "opens another connection for a request made while the thread's is in use, keeping the first returned" do
      outer = inner = nil
      connection_set.with_connection(uri, options) do |http|
        outer = http
        inner = checkout_http
      end

      expect(inner).not_to be(outer)
      expect(inner).to be_started
      expect(outer).not_to be_started
      expect(checkout_http).to be(inner)
      expect(connection_set.size).to eq(1)
    end

    it 'closes the connection instead of keeping it when the block raises' do
      http = nil
      expect do
        connection_set.with_connection(uri, options) do |session|
          http = session
          raise Errno::ECONNRESET
        end
      end.to raise_error(Errno::ECONNRESET)

      expect(http).not_to be_started
      expect(connection_set.size).to eq(0)
      expect(checkout_http).not_to be(http)
    end

    it 'raises when a connection fails to open' do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      expect { checkout_http }.to raise_error(Errno::ECONNREFUSED)
      expect(connection_set.size).to eq(0)
    end

    it 'starts with no connections in a forked child' do
      parent = checkout_http
      allow(Process).to receive(:pid).and_return(Process.pid + 1)

      expect(checkout_http).not_to be(parent)
      expect(parent).to be_started
      expect(connection_set.size).to eq(1)
    end
  end

  describe 'ttl' do
    it 'replaces a connection that has expired' do
      first = checkout_http
      time[0] += 30

      second = checkout_http

      expect(second).not_to be(first)
      expect(first).not_to be_started
      expect(connection_set.size).to eq(1)
    end

    it 'closes a connection that expires during its request' do
      http = connection_set.with_connection(uri, options) do |session|
        time[0] += 30
        session
      end

      expect(http).not_to be_started
      expect(connection_set.size).to eq(0)
    end
  end

  describe 'dead threads' do
    it 'closes their connections when a thread makes its first request' do
      dead = in_thread { checkout_http }

      checkout_http

      expect(dead).not_to be_started
      expect(connection_set.size).to eq(1)
    end

    it 'leaves them until then' do
      checkout_http
      dead = in_thread { checkout_http }

      checkout_http

      expect(dead).to be_started
      expect(connection_set.size).to eq(2)
    end
  end

  describe '#close' do
    it 'closes idle connections across threads' do
      main = checkout_http
      other = in_thread { checkout_http }

      connection_set.close

      expect([main, other]).to all(satisfy { |http| !http.started? })
      expect(connection_set.size).to eq(0)
    end

    it 'closes connections in use when their request ends' do
      http = connection_set.with_connection(uri, options) do |session|
        connection_set.close
        expect(session).to be_started
        session
      end

      expect(http).not_to be_started
      expect(connection_set.size).to eq(0)
    end

    it 'opens new connections afterwards' do
      first = checkout_http
      connection_set.close
      time[0] += 1

      expect(checkout_http).not_to be(first)
      expect(connection_set.size).to eq(1)
    end
  end
end
