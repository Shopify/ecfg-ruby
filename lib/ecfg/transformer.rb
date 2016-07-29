require 'ecfg/transformer/ast_transform'

module Ecfg
  class Transformer
    SliceCollector = Struct.new(:slices)

    def transform(input, parser, &block)
      ast = parser.parse(input)

      xform = Ecfg::Transformer::ASTTransform.new
      node = xform.apply(ast)

      sc = SliceCollector.new([])
      node.visit(sc)
      slices = sc.slices

      transform_slices(input, slices, &block)
    end

    private

    # Iterate through the input text, but each time we reach the bounds of one
    # of the identified slices, yield its value and write the result, instead
    # of the original text of the slice from the input document.
    def transform_slices(input, slices)
      prev = 0
      out = ''
      slices.each do |slice|
        out += input[prev...slice.start_index]
        out += yield(slice.value).to_s.inspect
        prev = slice.end_index
      end
      out += input[prev..-1]
      out
    end
  end
end
