require 'minitest/autorun'

require 'ecfg'

module Helpers
  module AST
    def assert_ast(expected, input)
      tree = parser.parse(input)
      tree = stringify_slices(tree)
      assert_equal(expected, tree)
    end

    private

    def stringify_slices(tree)
      case tree
      when Hash
        out = tree.map do |k, v|
          [stringify_slices(k), stringify_slices(v)]
        end
        Hash[out]
      when Array
        tree.map { |t| stringify_slices(t) }
      when Parslet::Slice
        "#{tree.str}@#{tree.offset}"
      else
        tree
      end
    end

    def parser
      raise NotImplementedError
    end
  end
end
