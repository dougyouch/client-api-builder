# frozen_string_literal: true

# Purpose is to encapsulate adding nested routers
module ClientApiBuilder
  module Section
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def section(name, nested_router_options = {}, &)
        kls = InheritanceHelper::ClassBuilder::Utils.create_class(
          self,
          name,
          ::ClientApiBuilder::NestedRouter,
          nil,
          'NestedRouter',
          &
        )

        code = <<~CODE
          def self.#{name}_router
            #{kls.name}
          end

          def #{name}
            @#{name} ||= self.class.#{name}_router.new(self.root_router, #{nested_router_options.inspect})
          end
        CODE
        class_eval code, __FILE__, __LINE__
      end
    end
  end
end
