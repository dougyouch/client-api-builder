# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::ConnectionPools::Settings do
  it 'has defaults for every setting' do
    expect(described_class.new.to_h).to eq(max_connections: 5, ttl: 30, checkout_timeout: 5, idle_timeout: 2)
  end

  it 'accepts overrides' do
    settings = described_class.new(max_connections: 10, ttl: 60, checkout_timeout: 0.5, idle_timeout: 1)

    expect(settings.to_h).to eq(max_connections: 10, ttl: 60, checkout_timeout: 0.5, idle_timeout: 1)
  end

  it 'rejects unknown settings' do
    expect { described_class.new(size: 3) }.to raise_error(ArgumentError, /size/)
  end

  it 'rejects a max_connections that is not a positive Integer' do
    [0, -1, 2.5, '5', nil].each do |value|
      expect { described_class.new(max_connections: value) }
        .to raise_error(ArgumentError, /max_connections must be a positive Integer, got #{Regexp.escape(value.inspect)}/)
    end
  end

  it 'rejects durations that are not positive numbers' do
    %i[ttl checkout_timeout idle_timeout].each do |name|
      [0, -1, '30', nil].each do |value|
        expect { described_class.new(name => value) }
          .to raise_error(ArgumentError, /#{name} must be a positive number of seconds/)
      end
    end
  end
end
