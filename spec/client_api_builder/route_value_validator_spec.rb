# frozen_string_literal: true

require 'spec_helper'
require 'bigdecimal'
require 'date'

describe ClientApiBuilder::RouteValueValidator do
  describe '.validate!' do
    it 'accepts strings, numbers, booleans, nil, argument symbols and nested hashes and arrays' do
      value = { 'name' => 'x', count: 1, ratio: 0.5, on: true, off: false, none: nil, id: :id,
                list: [1, 'a', { deep: [:tag] }], 2 => 'integer key', 'content-type': 'json' }

      expect { described_class.validate!(:create_x, :body, value) }.not_to raise_error
    end

    {
      'Time' => Time.at(0).utc,
      'Date' => Date.new(2026, 1, 1),
      'Object' => Object.new,
      'Float::INFINITY' => Float::INFINITY,
      'Float::NAN' => Float::NAN,
      'Rational' => Rational(1, 3),
      'BigDecimal' => BigDecimal('0.1'),
      'Range' => (1..3)
    }.each do |label, value|
      it "rejects #{label} with the route, location and class" do
        expect { described_class.validate!(:create_x, :body, { v: value }) }
          .to raise_error(ArgumentError, /\Aroute :create_x: body value .* \(#{value.class}\) can't be written/)
      end
    end

    it 'rejects values nested in arrays and hashes' do
      expect { described_class.validate!(:get_x, :query, { a: [{ at: Time.at(0) }] }) }
        .to raise_error(ArgumentError, /route :get_x: query value .*\(Time\)/)
    end

    it 'rejects hash keys that cannot be written as literals' do
      expect { described_class.validate!(:create_x, :body, { Time.at(0) => 1 }) }
        .to raise_error(ArgumentError, /\(Time\)/)
    end

    it 'rejects symbol values that are not valid argument names' do
      expect { described_class.validate!(:create_x, :body, { v: :'foo-bar' }) }
        .to raise_error(ArgumentError, 'route :create_x: body argument :"foo-bar" is not a valid argument name')
    end

    it 'accepts a nil or string body' do
      expect { described_class.validate!(:create_x, :body, nil) }.not_to raise_error
      expect { described_class.validate!(:create_x, :body, 'raw') }.not_to raise_error
    end
  end
end
