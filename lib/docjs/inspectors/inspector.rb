require 'rkelly'
require 'find'
require_relative '../meta/file'
require_relative '../meta/project'

module DocJS
  module Inspectors
    class Inspector
      attr_accessor :visitor_type

      def initialize(visitor_type)
        @visitor_type = visitor_type
      end

      def inspect_file(path)
        process_file(path)
      end

      def inspect_path(path, recursive = true, &block)
        project = Meta::Project.new(path)

        iterate_path(path, recursive) do |file|
          next if block_given? && !yield(file)

          project.files << process_file(file)
        end

        project
      end

      protected
      def iterate_path(path, recursive = true)
        Find.find(path) do |file|
          next if file == path

          if FileTest.directory? file
            throw :prune if !recursive
          else
            yield file
          end
        end
      end

      def process_file(path)
        File.open(path) do |file|
          content = file.read

          # todo: remove and add logging functionality
          print "#{path}"

          parser = RKelly::Parser.new

          begin
            ast = parser.parse(content)
          rescue Exception
            ast = nil
          end

          if ast.nil?
            # todo: remove and add logging functionality
            print " (ERROR)\n"
            next
          end

          # todo: remove and add logging functionality
          print "\n"

          source_file = Meta::File.new(File.basename(path), path)

          visitor = @visitor_type.new()

          ast.accept(visitor)

          source_file.modules = visitor.modules
          source_file.classes = visitor.classes
          source_file.functions = visitor.functions
          source_file
        end
      end
    end
  end
end