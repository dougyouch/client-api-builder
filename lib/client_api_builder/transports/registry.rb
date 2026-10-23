# frozen_string_literal: true

module ClientApiBuilder
  module Transports
    # Which transport each client class uses. A class (or module) can have two kinds of entry:
    # one registered with use, normally at boot for the environment, and one declared by its
    # class body through ConnectionPools, ThreadConnections or HTTP2. A class uses the
    # registered transport of the nearest class in its ancestry, else the declared one of the
    # nearest, else the process default (OneShot unless use set another), so the environment's
    # choice wins whichever loads first.
    #
    # Entries are held weakly by class, so anonymous client classes can still be collected.
    class Registry
      def initialize(default_factory: -> { OneShot.new })
        @default_factory = default_factory
        @mutex = Mutex.new
        @default = nil
        @registered = ObjectSpace::WeakKeyMap.new
        @declared = ObjectSpace::WeakKeyMap.new
        @transports = ObjectSpace::WeakMap.new
      end

      # Sends requests through transport: for every client, or for client_class and its
      # subclasses (and the classes including it, for a module) when given
      def use(transport, client_class = nil)
        @mutex.synchronize do
          client_class ? @registered[client_class] = transport : @default = transport
          @transports[transport] = true
        end
      end

      # The transport a client class's own body chose; use takes precedence over it
      def declare(transport, client_class)
        @mutex.synchronize do
          @declared[client_class] = transport
          @transports[transport] = true
        end
      end

      # The transport registered or declared for the class or its nearest ancestor, or nil
      def registered_for(client_class)
        ancestors = client_class.ancestors
        @mutex.synchronize { nearest(@registered, ancestors) || nearest(@declared, ancestors) }
      end

      def for_class(client_class)
        registered_for(client_class) || default
      end

      def default
        @mutex.synchronize { @default ||= @default_factory.call }
      end

      # Closes every transport registered or declared, and the default
      def close_all
        transports = @mutex.synchronize { [*@transports.keys, @default].compact.uniq }
        transports.each(&:close)
      end

      # Forgets the transports set with use, and the default, closing nothing; declarations
      # belong to class bodies and stay. Meant for specs.
      def reset
        @mutex.synchronize do
          @registered = ObjectSpace::WeakKeyMap.new
          @default = nil
        end
      end

      private

      def nearest(entries, ancestors)
        ancestors.each do |ancestor|
          transport = entries[ancestor]
          return transport if transport
        end
        nil
      end
    end
  end
end
