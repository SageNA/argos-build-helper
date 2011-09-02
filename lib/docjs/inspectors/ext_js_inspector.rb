require 'rkelly'
require 'find'
require_relative 'inspector'
require_relative '../visitors/ext_js_inspection_visitor'

module DocJS
  module Inspectors
    class ExtJsInspector < Inspector
      def initialize
        super(Visitors::ExtJsInspectionVisitor)
      end
    end
  end
end
