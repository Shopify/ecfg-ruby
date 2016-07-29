module Ecfg
  module Parser
    module NodeType
      # These are the node types that show up in the AST.

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
      TOML_MULTILINE_BASIC   = :toml_multiline_basic
      TOML_MULTILINE_LITERAL = :toml_multiline_literal

      ## YAML-specific types

      # Reading the spec on block and folded literals will help understand this
      # one.  Note that we have to do some interpretation later on to get the
      # indentation and clipping right.  Also, we need to exclude the last
      # newline, which was hard to not capture in the parser.
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
