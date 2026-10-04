# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::ThreadConnections::Settings do
  it 'has defaults for every setting' do
    expect(described_class.new.to_h).to eq(ttl: 30, idle_timeout: 2)
  end

  it 'accepts overrides' do
    expect(described_class.new(ttl: 60, idle_timeout: 0.5).to_h).to eq(ttl: 60, idle_timeout: 0.5)
  end

  it 'rejects unknown settings' do
    expect { described_class.new(max_connections: 3) }.to raise_error(ArgumentError, /max_connections/)
  end

  it 'rejects durations that are not positive numbers' do
    %i[ttl idle_timeout].each do |name|
      [0, -1, '30', nil].each do |value|
        expect { described_class.new(name => value) }
          .to raise_error(ArgumentError, /#{name} must be a positive number of seconds, got #{Regexp.escape(value.inspect)}/)
      end
    end
  end
end
