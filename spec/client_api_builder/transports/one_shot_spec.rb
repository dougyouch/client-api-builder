# frozen_string_literal: true

require 'spec_helper'
require 'support/transport_helpers'

describe ClientApiBuilder::Transports::OneShot do
  include TransportHelpers

  let(:transport) { described_class.new }

  it 'opens a new connection for every request' do
    2.times { expect(get_through(transport, server.url)).to eq('{"ok":true}') }

    expect(server.connections).to eq(2)
  end

  it 'has nothing to close' do
    expect(transport.close).to be_nil
  end
end
