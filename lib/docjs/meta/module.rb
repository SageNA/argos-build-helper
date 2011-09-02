module DocJS
  module Meta
    class Module
      attr_accessor :name,
                    :imports,
                    :methods,
                    :properties,
                    :comment

      def initialize(name = nil, comment = nil)
        @name = name
        @comment = comment
        @imports = []
        @methods = []
        @properties = []
      end
    end
  end
end
