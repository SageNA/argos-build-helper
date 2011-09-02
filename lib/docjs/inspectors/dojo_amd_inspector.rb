require 'rkelly'
require 'find'
require_relative 'inspector'
require_relative '../visitors/dojo_amd_inspection_visitor'

module DocJS
  module Inspectors
    class DojoAmdInspector < Inspector
      def initialize
        super(Visitors::DojoAmdInspectionVisitor)
      end
    end
  end
end
