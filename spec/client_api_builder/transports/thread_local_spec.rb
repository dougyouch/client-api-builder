# frozen_string_literal: true

require 'spec_helper'
require 'support/transport_helpers'

describe ClientApiBuilder::Transports::ThreadLocal do
  include TransportHelpers

  let(:transport) { described_class.new(ttl: 10) }

  after { transport.close }

  it 'takes the per-thread connection settings' do
    expect(transport.settings.to_h).to eq(ttl: 10, idle_timeout: 2)
  end

  it 'validates the settings' do
    expect { described_class.new(ttl: 0) }.to raise_error(ArgumentError, /ttl/)
  end

  it 'gives each thread its own connection, reused by its later requests' do
    2.times { get_through(transport, server.url) }
    Thread.new { 2.times { get_through(transport, server.url) } }.join

    expect(server.connections).to eq(2)
  end

  it 'closes a connection whose request raised' do
    expect { transport.with_connection(URI(server.url), {}) { raise IOError, 'boom' } }.to raise_error(IOError)

    expect(transport.connection_set.size).to eq(0)
  end

  it 'closes idle connections with close' do
    get_through(transport, server.url)
    transport.close

    expect(transport.connection_set.size).to eq(0)
  end
end
