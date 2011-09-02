module DocJS
  module Meta
    class File
      attr_accessor :name,
                    :path,
                    :modules,
                    :classes,
                    :functions

      def initialize(name = nil, path = nil)
        @name = name
        @path = path
      end
    end
  end
end