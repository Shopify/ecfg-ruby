require 'parslet'
require 'ecfg/transformer/nodes'

module Ecfg
  class Transformer
    # Load an AST from the YAML, JSON, or TOML parser to a form we can interact
    # with more easily. This transforms a bunch of nested hashes into an
    # Ecfg::Transformer::Nodes::* object, which we later call visit() on to
    # collect a list of encryptable strings in the document.
    class ASTTransform < Parslet::Transform
      # These are borrowed from RbYAML:
      # https://github.com/opsb/rbyaml/blob/master/lib/rbyaml/resolver.rb
      #
      # Since yaml support unquoted strings, we have to do a bunch of checks to
      # determine what type an unquoted value actually represents.
      #
      # Nothing that is determined to be any of these types will be considered
      # eligible for encryption.
      NON_STRING_PLAIN = {
        bool:      /^(?:yes|Yes|YES|no|No|NO|true|True|TRUE|false|False|FALSE|on|On|ON|off|Off|OFF)$/,
        float:     /^(?:[-+]?(?:[0-9][0-9_]*)\.[0-9_]*(?:[eE][-+][0-9]+)?|[-+]?(?:[0-9][0-9_]*)?\.[0-9_]+(?:[eE][-+][0-9]+)?|[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+\.[0-9_]*|[-+]?\.(?:inf|Inf|INF)|\.(?:nan|NaN|NAN))$/,
        int:       /^(?:[-+]?0b[0-1_]+|[-+]?0[0-7_]+|[-+]?(?:0|[1-9][0-9_]*)|[-+]?0x[0-9a-fA-F_]+|[-+]?[1-9][0-9_]*(?::[0-5]?[0-9])+)$/,
        merge:     /^(?:<<)$/,
        null:      /^(?:~|null|Null|NULL| )$/,
        timestamp: /^(?:[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]|[0-9][0-9][0-9][0-9]-[0-9][0-9]?-[0-9][0-9]?(?:[Tt]|[ \t]+)[0-9][0-9]?:[0-9][0-9]:[0-9][0-9](?:\.[0-9]*)?(?:[ \t]*(?:Z|[-+][0-9][0-9]?(?::[0-9][0-9])?))?)$/,
        value:     /^(?:=)$/
      }.freeze

      # YAML supports unquoted strings, and we have to do an extra pass
      # to determine whether they're strings or some other data type
      # (non-strings are never encrypted)
      def self.non_string_plain?(typ, text)
        return false unless typ == Ecfg::Parser::NodeType::PLAIN_SCALAR
        NON_STRING_PLAIN.any? do |_, pat|
          pat =~ text
        end
      end

      def self.scalar_or_ignore(typ, text)
        if non_string_plain?(typ, text)
          Nodes::Ignore.new
        else
          Nodes::SCALAR_CLASS[typ].new(text)
        end
      end

      # Various types of scalar nodes parse to various types, but they're all
      # terminal nodes (i.e. scalar); see ./nodes.rb for more detail.
      Ecfg::Parser::NodeType::SCALAR_TYPES.each do |typ|
        rule(typ => simple(:text)) {
          ASTTransform.scalar_or_ignore(typ, text)
        }
        rule(typ => simple(:text), ignore: subtree(:ignore)) {
          ASTTransform.scalar_or_ignore(typ, text)
        }
      end

      # hashes are generally parsed to:
      # {map: [{pair: ...}, {pair: ...}]}
      rule(map: subtree(:pairs))  { Nodes::Map.new(pairs) }
      # {seq: [{...}, ...]}
      rule(seq: subtree(:items))  { Nodes::Seq.new(items) }

      # pairs look like:
      # {pair: {key: ..., value: ...}}
      rule(pair: subtree(:kv)) {
        Nodes::Pair.new(
          kv.detect { |k, _| k == :key }[1],
          kv.detect { |k, _| k == :value }[1]
        )
      }

      # ignore and empty both indicate irrelevant subtrees that we can prune.
      rule(ignore: simple(:text)) { Nodes::Ignore.new }
      rule(empty: simple(:text))  { Nodes::Ignore.new }
    end
  end
end
