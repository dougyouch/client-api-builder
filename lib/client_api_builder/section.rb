# frozen_string_literal: true

module ClientApiBuilder
  module Section
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def section(name, &block)
        kls = InheritanceHelper::ClassBuilder::Utils.create_class(
          self,
          name,
          ::ClientApiBuilder::NestedRouter,
          nil,
          'NestedRouter',
          &block
        )

        code = <<CODE
def self.#{name}_router
  #{kls.name}
end

def #{name}
  @#{name} ||= self.class.#{name}_router.new(self)
end
CODE
        self.class_eval code, __FILE__, __LINE__
      end
    end
  end
end
