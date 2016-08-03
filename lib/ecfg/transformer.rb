require 'ecfg/transformer/ast_transform'

module Ecfg
  class Transformer
    # parse the given input with the given parser, determine which values in
    # that document are encryptable, and generate a new copy of the document
    # with those values replaced by the result of applying them to the given
    # block (i.e. encrypt or decrypt them).
    #
    # Example:
    #
    #   input       = "---\na: b\n_c: d\ne: f"
    #   key         = "6ea8ba92a66f795c17f9ba4dd3d3f445c1e4b9c34728b17aea370479eff1246d"
    #   encrypter   = Ecfg::Crypto::Encrypter.new(key)
    #   parser      = Ecfg::Parser::YAML.new
    #   transformer = Ecfg::Transformer.new
    #
    #   puts transformer.transform(input, parser, &encrypter)
    #
    def transform(input, parser, &block)
      ast = parser.parse(input)

      xform = Ecfg::Transformer::ASTTransform.new
      node = xform.apply(ast)

      sc = Struct.new(:slices).new([])
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
