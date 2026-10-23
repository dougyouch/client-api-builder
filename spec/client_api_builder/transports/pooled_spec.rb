# frozen_string_literal: true

require 'spec_helper'
require 'support/transport_helpers'

describe ClientApiBuilder::Transports::Pooled do
  include TransportHelpers

  let(:transport) { described_class.new(max_connections: 2, ttl: 10) }
  let(:pool) { transport.pool_set.pools.first }

  after { transport.close }

  it 'takes the connection pool settings' do
    expect(transport.settings.to_h).to eq(max_connections: 2, ttl: 10, checkout_timeout: 5, idle_timeout: 2)
  end

  it 'validates the settings' do
    expect { described_class.new(max_connections: 0) }.to raise_error(ArgumentError, /max_connections/)
  end

  it 'reuses a pooled connection for sequential requests' do
    3.times { expect(get_through(transport, server.url)).to eq('{"ok":true}') }

    expect(server.connections).to eq(1)
    expect(pool.idle_size).to eq(1)
  end

  it 'closes a connection whose request raised' do
    expect { transport.with_connection(URI(server.url), {}) { raise IOError, 'boom' } }.to raise_error(IOError)

    expect(pool.size).to eq(0)
  end

  it 'closes idle connections with close' do
    get_through(transport, server.url)
    transport.close

    expect(pool.size).to eq(0)
  end
end
