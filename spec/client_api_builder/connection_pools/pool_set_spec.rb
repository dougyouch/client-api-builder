# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::ConnectionPools::PoolSet do
  let(:settings) { ClientApiBuilder::ConnectionPools::Settings.new(idle_timeout: 4) }
  let(:pool_set) { described_class.new(settings) }
  let(:uri) { URI('https://example.com/users') }
  let(:options) { { use_ssl: true, read_timeout: 9 } }

  describe '#pool_for' do
    it 'returns the same pool for the same host and connection options' do
      pool = pool_set.pool_for(uri, options)

      expect(pool_set.pool_for(URI('https://example.com/orders'), options.dup)).to be(pool)
      expect(pool.host).to eq('example.com')
      expect(pool.port).to eq(443)
      expect(pool.settings).to be(settings)
    end

    it 'returns separate pools for different hosts, ports or connection options' do
      pool = pool_set.pool_for(uri, options)

      expect(pool_set.pool_for(URI('https://other.example.com/'), options)).not_to be(pool)
      expect(pool_set.pool_for(URI('https://example.com:8443/'), options)).not_to be(pool)
      expect(pool_set.pool_for(uri, options.merge(read_timeout: 1))).not_to be(pool)
      expect(pool_set.pools.size).to eq(4)
    end

    it 'is unaffected by later changes to the connection options' do
      pool = pool_set.pool_for(uri, options)
      options[:read_timeout] = 1

      expect(pool_set.pool_for(uri, { use_ssl: true, read_timeout: 9 })).to be(pool)
    end

    it 'starts with no pools in a forked child' do
      pool = pool_set.pool_for(uri, options)
      allow(Process).to receive(:pid).and_return(Process.pid + 1)

      expect(pool_set.pool_for(uri, options)).not_to be(pool)
      expect(pool_set.pools.size).to eq(1)
    end
  end

  describe '#with_connection' do
    it 'passes idle_timeout to Net::HTTP as keep_alive_timeout' do
      expect(pool_set.with_connection(uri, options, &:keep_alive_timeout)).to eq(4)
    end

    it 'lets a keep_alive_timeout connection option override idle_timeout' do
      expect(pool_set.with_connection(uri, options.merge(keep_alive_timeout: 10), &:keep_alive_timeout)).to eq(10)
    end
  end

  describe '#close' do
    it 'closes every pool' do
      first = pool_set.with_connection(uri, options) { |http| http }
      second = pool_set.with_connection(URI('http://other.example.com/'), {}) { |http| http }

      pool_set.close

      expect([first, second]).to all(satisfy { |http| !http.started? })
    end
  end
end
