module DocJS
  module Meta
    class Class
      attr_accessor :name,
                    :extends,
                    :methods,
                    :properties,
                    :comment

      def initialize(name = nil, comment = nil)
        @name = name
        @comment = comment
        @extends = []
        @methods = []
        @properties = []
      end
    end
  end
end
