# frozen_string_literal: true

require 'spec_helper'

describe ClientApiBuilder::Transports::Registry do
  let(:registry) { described_class.new }
  let(:base_class) { Class.new }
  let(:child_class) { Class.new(base_class) }
  let(:transport) { ClientApiBuilder::Transports::OneShot.new }
  let(:other) { ClientApiBuilder::Transports::OneShot.new }

  describe '#default' do
    it 'is a OneShot, created once' do
      default = registry.default

      expect(default).to be_a(ClientApiBuilder::Transports::OneShot)
      expect(registry.default).to be(default)
    end

    it 'comes from the default factory' do
      registry = described_class.new(default_factory: -> { transport })

      expect(registry.default).to be(transport)
    end
  end

  describe '#use' do
    it 'sets the process default without a class' do
      registry.use(transport)

      expect(registry.for_class(base_class)).to be(transport)
      expect(registry.registered_for(base_class)).to be_nil
    end

    it 'registers a transport for a class and its subclasses' do
      registry.use(transport, base_class)

      expect(registry.for_class(child_class)).to be(transport)
      expect(registry.for_class(Class.new)).to be(registry.default)
    end

    it 'uses the nearest registered class' do
      registry.use(transport, base_class)
      registry.use(other, child_class)

      expect(registry.for_class(child_class)).to be(other)
      expect(registry.for_class(base_class)).to be(transport)
    end

    it 'registers a transport for a module and the classes including it' do
      mod = Module.new
      registry.use(transport, mod)

      expect(registry.for_class(Class.new { include mod })).to be(transport)
    end
  end

  describe '#declare' do
    it 'is used when nothing is registered' do
      registry.declare(transport, base_class)

      expect(registry.for_class(child_class)).to be(transport)
    end

    it 'gives way to a registration anywhere in the ancestry, whichever came first' do
      registry.use(other, base_class)
      registry.declare(transport, child_class)

      expect(registry.for_class(child_class)).to be(other)
    end

    it 'takes precedence over the process default' do
      registry.use(other)
      registry.declare(transport, base_class)

      expect(registry.for_class(base_class)).to be(transport)
    end
  end

  describe '#close_all' do
    it 'closes the default and every registered and declared transport once' do
      transports = Array.new(3) { instance_double(ClientApiBuilder::Transports::OneShot, close: nil) }
      registry.use(transports[0])
      registry.use(transports[1], base_class)
      registry.use(transports[1], child_class)
      registry.declare(transports[2], child_class)

      registry.close_all

      expect(transports).to all(have_received(:close).once)
    end

    it 'leaves a default that was never used uncreated' do
      registry = described_class.new(default_factory: -> { raise 'default created' })

      expect { registry.close_all }.not_to raise_error
    end
  end

  describe '#reset' do
    it 'forgets registrations and the default but keeps declarations' do
      registry.use(other)
      registry.use(other, child_class)
      registry.declare(transport, base_class)

      registry.reset

      expect(registry.for_class(child_class)).to be(transport)
      expect(registry.default).not_to be(other)
    end
  end
end
