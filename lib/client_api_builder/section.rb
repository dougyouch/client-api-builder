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
      # inherit: opts the section into root client settings (see NestedRouter.inherit_from_root);
      # the remaining options are passed to the section as nested_router_options.
      def section(name, nested_router_options = {}, &block)
        raise ArgumentError, "Invalid section name: #{name.inspect}" unless name.to_s.match?(SECTION_NAME)

        nested_router_options = nested_router_options.dup
        inherit = ::ClientApiBuilder::NestedRouter.normalize_inherited_settings(Array(nested_router_options.delete(:inherit)))

        kls = InheritanceHelper::ClassBuilder::Utils.create_class(
          self,
          name,
          ::ClientApiBuilder::NestedRouter,
          nil,
          'NestedRouter'
        )
        kls.inherit_from_root(inherit)
        kls.class_eval(&block) if block

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
