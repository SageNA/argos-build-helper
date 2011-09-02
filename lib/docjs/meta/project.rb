module DocJS
  module Meta
    class Project
      attr_accessor :name,
                    :files

      def initialize(name = nil)
        @name = name
        @files = []
      end

      def classes
        if block_given?
          @files.each do |file|
            file.classes.each do |cls|
              yield cls, file
            end
          end
        else
          (@files.map do |file| file.classes end).flatten
        end
      end

      def modules
        if block_given?
          @files.each do |file|
            file.modules.each do |cls|
              yield cls, file
            end
          end
        else
          (@files.map do |file| file.modules end).flatten
        end
      end

      def functions
        if block_given?
          @files.each do |file|
            file.functions.each do |cls|
              yield cls, file
            end
          end
        else
          (@files.map do |file| file.functions end).flatten
        end
      end
    end
  end
end
