require 'rkelly'
require_relative '../meta/module'
require_relative '../meta/class'
require_relative '../meta/function'
require_relative '../meta/property'

module DocJS
  module Visitors
    class DojoAmdInspectionVisitor < Visitor
      def visit_FunctionCallNode(node)
        if is_module_declaration?(node)
          @modules << create_module_from_node(node)
        end
        super
      end

      def is_module_declaration?(node)
        return false unless node.value.is_a? RKelly::Nodes::ResolveNode
        return false unless node.value.value == "define"
        return false unless node.arguments.is_a? RKelly::Nodes::ArgumentsNode
        return false unless node.arguments.value.length.between?(1,3)

        true
      end

      def create_module_from_node(node)
        result = Meta::Module.new
        result.comment = get_comment_for_node(node.arguments)

        factory_node = nil

        case node.arguments.value.length
          when 3 then # named module
            factory_node = node.arguments.value[2]

            result.name = get_value_for_node(node.arguments.value[0])
            result.imports = get_value_for_node(node.arguments.value[1])
          when 2 then # anonymous module
            factory_node = node.arguments.value[1]

            result.imports = get_value_for_node(node.arguments.value[0])
          when 1 then # anonymous, no dependencies
            factory_node = node.arguments.value[0]
        end

        if factory_node.is_a? RKelly::Nodes::ObjectLiteralNode
          factory_node.value.each do |property|
            name = property.name
            type = get_type_for_node(property.value)
            value = get_value_for_node(property.value)
            comment = get_comment_for_node(property)
            case true
              when property.value.is_a?(RKelly::Nodes::FunctionExprNode) then
                result.methods << Meta::Function.new(name, comment)
              else
                result.properties << Meta::Property.new(name, comment, type, value)
            end
          end
        end

        result
      end

      def visit_DotAccessorNode(node)
        if is_class_declaration?(node)
          @classes << create_class_from_node(node)
        end
        super
      end

      def is_class_declaration?(node)
        return false unless node.accessor == 'declare'
        return false unless node.value.is_a? RKelly::Nodes::ResolveNode
        return false unless node.value.value == 'dojo'
        return false unless node.parent.is_a? RKelly::Nodes::FunctionCallNode
        return false unless node.parent.arguments.value.length == 3
        return false unless node.parent.arguments.value.first.is_a? RKelly::Nodes::StringNode
        true
      end

      def create_class_from_node(node)
        declare_call = node.parent

        result = Meta::Class.new
        result.comment = get_comment_for_node(node)

        case declare_call.arguments.value.length
          when 3 then
            name_node = declare_call.arguments.value[0]
            inherited_node = declare_call.arguments.value[1]
            properties_node = declare_call.arguments.value[2]
          else
            raise 'Could not understand type declaration.'
        end

        result.name = remove_quotes(name_node.value)

        if inherited_node.is_a? RKelly::Nodes::DotAccessorNode
          result.extends << node_to_path(inherited_node)
        elsif inherited_node.is_a? RKelly::Nodes::ArrayNode
          inherited_node.value.each do |inherited|
            result.extends << node_to_path(inherited.value)
          end
        end

        properties_node.value.each do |property|
          name = property.name
          type = get_type_for_node(property.value)
          value = get_value_for_node(property.value)
          comment = get_comment_for_node(property)
          case true
            when property.value.is_a?(RKelly::Nodes::FunctionExprNode) then
              result.methods << Meta::Function.new(name, comment)
            else
              result.properties << Meta::Property.new(name, comment, type, value)
          end
        end

        result
      end
    end
  end
end
