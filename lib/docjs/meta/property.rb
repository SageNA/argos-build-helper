module DocJS
  module Meta
    class Property
      attr_accessor :name,
                    :comment,
                    :type,
                    :value

      def initialize(name = nil, comment = nil, type = nil, value = nil)
        @name = name
        @comment = comment
        @type = type
        @value = value
      end
    end
  end
end
