module Ecfg
  module Parser
    # NodeType enumerates the node types we use to construct our parse-output
    # AST. Generally what we're going for is to loosely preserve hierarchy in
    # terms of MAP and SEQ nodes.
    #
    # Preserving hierarchy, though, is pretty much just to prevent conflicts
    # when parslet merges subtrees. We discard it pretty quickly in the next
    # pass.
    #
    # Other than the various scalar types, everything else is just here to
    # generate a non-overlapping AST, or, in the case of the IGNORE nodes, to
    # limit the scope of captures (e.g. to exclude YAML tags).
    module NodeType
      # {map: [{pair: {key: ..., value: ...}}]}
      MAP   = :map
      PAIR  = :pair
      KEY   = :key
      VALUE = :value

      # {seq: [..., ...]}
      SEQ = :seq

      # numbers, booleans, null, datetimes are not encryptable.
      IGNORE = :ignore
      # empty is treated as ignore, but needs its own node type to prevent
      # overlapping subtrees in yaml parsing.
      EMPTY  = :empty

      # scalar nodes in this parser always include any relevant quote characters.

      # {plain_scalar: words@42}
      # {double_quoted: "words"@42}
      # {single_quoted: 'words'@42}
      PLAIN_SCALAR    = :plain_scalar
      UNQUOTED_STRING = :unquoted_string
      DOUBLE_QUOTED   = :double_quoted
      SINGLE_QUOTED   = :single_quoted

      ## TOML-specific types
      # These are interesting in that they have three-wide quotes (e.g.
      # '''\nwords\n''')
      TOML_MULTILINE_BASIC   = :toml_multiline_basic
      TOML_MULTILINE_LITERAL = :toml_multiline_literal

      ## YAML-specific types

      # Reading the spec on block and folded literals will help understand this
      # one. Note that we have to do some interpretation later on to get the
      # indentation, clipping, and folding right. This is by far the most
      # complex part of the YAML spec -- which is actually saying rather a lot.
      #
      # {block_literal: "|\n  asdf\n"@32}
      # {block_folded: ">+2\n  zxcv\n"@42}
      BLOCK_LITERAL = :block_literal
      BLOCK_FOLDED  = :block_folded

      SCALAR_TYPES = [
        PLAIN_SCALAR,
        UNQUOTED_STRING,
        DOUBLE_QUOTED,
        SINGLE_QUOTED,
        TOML_MULTILINE_BASIC,
        TOML_MULTILINE_LITERAL,
        BLOCK_LITERAL,
        BLOCK_FOLDED
      ].freeze
    end
  end
end
