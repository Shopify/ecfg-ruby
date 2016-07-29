require 'parslet'
require 'ecfg/transformer/nodes'

module Ecfg
  class Transformer
    class ASTTransform < Parslet::Transform

      # These are borrowed from RbYAML:
      # https://github.com/opsb/rbyaml/blob/master/lib/rbyaml/resolver.rb
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

      Ecfg::Parser::NodeType::SCALAR_TYPES.each do |typ|
        rule(typ => simple(:text), ignore: subtree(:ignore)) {
          if ASTTransform.non_string_plain?(typ, text)
            Nodes::Ignore.new
          else
            Nodes::SCALAR_CLASS[typ].new(text)
          end
        }
        rule(typ => simple(:text)) {
          if ASTTransform.non_string_plain?(typ, text)
            Nodes::Ignore.new
          else
            Nodes::SCALAR_CLASS[typ].new(text)
          end
        }
      end

      rule(pair: subtree(:kv)) {
        Nodes::Pair.new(
          kv.detect { |k, _| k == :key }[1],
          kv.detect { |k, _| k == :value }[1]
        )
      }

      rule(seq: subtree(:items))  { Nodes::Seq.new(items) }
      rule(map: subtree(:pairs))  { Nodes::Map.new(pairs) }

      rule(ignore: simple(:text)) { Nodes::Ignore.new }
      rule(empty: simple(:text))  { Nodes::Ignore.new }
    end
  end
end
