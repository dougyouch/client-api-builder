# frozen_string_literal: true

# Purpose is to encapsulate adding nested routers
module ClientApiBuilder
  module Section
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      SECTION_NAME = /\A[a-z_][a-z0-9_]*\z/i

      # Defines <name>_router (the section's NestedRouter class) and <name> (its router for a
      # client instance) with closures, so anonymous client classes and any option values work.
      def section(name, nested_router_options = {}, &)
        raise ArgumentError, "Invalid section name: #{name.inspect}" unless name.to_s.match?(SECTION_NAME)

        kls = InheritanceHelper::ClassBuilder::Utils.create_class(
          self,
          name,
          ::ClientApiBuilder::NestedRouter,
          nil,
          'NestedRouter',
          &
        )

        define_singleton_method(:"#{name}_router") { kls }
        define_section_accessor(name, nested_router_options)
      end

      private

      # Memoized per client instance; each instance gets its own copy of the options
      def define_section_accessor(name, nested_router_options)
        router_method = :"#{name}_router"
        ivar = :"@#{name}"

        define_method(name) do
          instance_variable_get(ivar) ||
            instance_variable_set(ivar, self.class.public_send(router_method)
                                              .new(root_router, nested_router_options.dup))
        end
      end
    end
  end
end
