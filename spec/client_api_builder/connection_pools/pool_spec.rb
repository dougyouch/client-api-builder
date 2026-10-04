# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::ConnectionPools::Pool do
  let(:time) { [1000.0] }
  let(:clock) { -> { time[0] } }
  let(:settings) { ClientApiBuilder::ConnectionPools::Settings.new(max_connections: 2, ttl: 30) }
  let(:pool) do
    described_class.new(host: 'example.com', port: 80, connection_options: { read_timeout: 7 },
                        settings: settings, clock: clock)
  end

  def checkout_http
    pool.with_connection { |http| http }
  end

  describe '#with_connection' do
    it 'yields a started session with the connection options and returns the block result' do
      result = pool.with_connection do |http|
        expect(http).to be_started
        expect(http.read_timeout).to eq(7)
        :done
      end

      expect(result).to eq(:done)
    end

    it 'keeps the connection open and idle after the request' do
      http = checkout_http

      expect(http).to be_started
      expect(pool.size).to eq(1)
      expect(pool.idle_size).to eq(1)
    end

    it 'reuses an idle connection' do
      first = checkout_http

      expect(checkout_http).to be(first)
      expect(pool.size).to eq(1)
    end

    it 'opens another connection while one is in use' do
      outer = inner = nil
      pool.with_connection do |http|
        outer = http
        inner = checkout_http
      end

      expect(inner).not_to be(outer)
      expect(pool.size).to eq(2)
      expect(pool.idle_size).to eq(2)
    end

    it 'closes the connection instead of reusing it when the block raises' do
      http = nil
      expect do
        pool.with_connection do |session|
          http = session
          raise Errno::ECONNRESET
        end
      end.to raise_error(Errno::ECONNRESET)

      expect(http).not_to be_started
      expect(pool.size).to eq(0)
      expect(checkout_http).not_to be(http)
    end

    it 'frees the slot when a connection fails to open' do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      expect { checkout_http }.to raise_error(Errno::ECONNREFUSED)
      expect(pool.size).to eq(0)
    end
  end

  describe 'ttl' do
    it 'replaces an idle connection that has expired' do
      first = checkout_http
      time[0] += 30

      second = checkout_http

      expect(second).not_to be(first)
      expect(first).not_to be_started
      expect(pool.size).to eq(1)
    end

    it 'keeps using a connection until it expires' do
      first = checkout_http
      time[0] += 29.9

      expect(checkout_http).to be(first)
    end

    it 'closes a connection that expires while in use when it is returned' do
      http = pool.with_connection do |session|
        time[0] += 31
        session
      end

      expect(http).not_to be_started
      expect(pool.size).to eq(0)
      expect(pool.idle_size).to eq(0)
    end
  end

  describe 'max_connections' do
    let(:settings) do
      ClientApiBuilder::ConnectionPools::Settings.new(max_connections: 1, checkout_timeout: 0.05)
    end
    let(:pool) do
      described_class.new(host: 'example.com', port: 80, connection_options: {}, settings: settings)
    end

    it 'raises TimeoutError when no connection frees up within checkout_timeout' do
      pool.with_connection do
        thread = Thread.new do
          Thread.current.report_on_exception = false
          checkout_http
        end

        expect { thread.value }.to raise_error(
          ClientApiBuilder::ConnectionPools::TimeoutError,
          'no connection to example.com:80 became available within 0.05s (max_connections: 1)'
        )
      end
    end

    it 'hands a returned connection to a waiting thread' do
      settings = ClientApiBuilder::ConnectionPools::Settings.new(max_connections: 1, checkout_timeout: 5)
      pool = described_class.new(host: 'example.com', port: 80, connection_options: {}, settings: settings)
      checked_out = Queue.new
      release = Queue.new
      holder = Thread.new do
        pool.with_connection do |http|
          checked_out << http
          release.pop
        end
      end
      held = checked_out.pop
      waiter = Thread.new { pool.with_connection { |http| http } }
      Thread.pass until waiter.status == 'sleep'

      release << true
      holder.join

      expect(waiter.value).to be(held)
      expect(pool.size).to eq(1)
    end
  end

  describe '#close' do
    it 'closes idle connections' do
      http = checkout_http

      pool.close

      expect(http).not_to be_started
      expect(pool.size).to eq(0)
      expect(pool.idle_size).to eq(0)
    end

    it 'closes a connection in use when it is returned' do
      http = pool.with_connection do |session|
        pool.close
        session
      end

      expect(http).not_to be_started
      expect(pool.size).to eq(0)
    end

    it 'keeps connections opened after the close' do
      pool.close
      time[0] += 1

      http = checkout_http

      expect(http).to be_started
      expect(pool.idle_size).to eq(1)
    end
  end
end
