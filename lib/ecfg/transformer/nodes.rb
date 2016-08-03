module Ecfg
  class Transformer
    # Nodes are nodes in our transformed parse tree that support `visit(x)` with
    # an `x` used to collect encryption-eligible string slices in the source
    # document.
    #
    # Each node calls its children recursively, so it is only necessary to call
    # `visit` once on the final transformed parse tree.
    #
    # Example:
    #
    #   node = ASTTransform.transform(tree)
    #   slice_collector = Struct.new(:slices).new([])
    #   node.visit(slice_collector)
    #   puts slice_collector.slices.size
    #
    # The additional parameter to `visit`, 'suppress_transform', indicates
    # whether the previous hash/map key began with an underscore, as this is
    # defined by the ecfg spec to suppress encryption of the attached values.
    module Nodes
      class Map
        attr_reader :pairs

        def initialize(pairs)
          @pairs = Array(pairs)
        end

        def visit(sc, suppress_transform = false)
          # suppression does not propagate downward; that is, each pair is going
          # to have its own key, which either will or will not start with an
          # underscore, resetting the context of whether or not values should be
          # suppressed.
          #
          # Therefore, we just pass suppress=false.
          pairs.each { |pair| pair.visit(sc, false) }
        end
      end

      class Seq
        attr_reader :items

        def initialize(items)
          @items = Array(items)
        end

        def visit(sc, suppress_transform = false)
          # If we have a situation such as:
          #
          # _a:
          #   - b
          #   - c
          #
          # we have a <Map:[<Pair:_a,<Seq:[...]>]>
          #
          # The items in the seq should not be encrypted, as long as they don't
          # open a new hash/map.
          items.each { |item| item.visit(sc, suppress_transform) }
        end
      end

      class Pair
        attr_reader :key, :value

        def initialize(key, value)
          @key = key
          @value = value
        end

        def visit(sc, suppress_transform = false)
          suppress = key.is_a?(BaseScalar) && key.suppresses_encryption?
          # Nothing in a key is ever encrypted.
          value.visit(sc, suppress)
        end
      end

      class Ignore
        # Ignore indicates a subtree that will never contain any encryptable
        # values.
        def visit(sc, suppress_transform = false)
        end
      end

      # Base class for all scalar types.
      class BaseScalar
        def initialize(content)
          @content = content
        end

        def value
          raise NotImplementedError
        end

        def start_index
          @content.offset + left_adjustment
        end

        def end_index
          @content.offset + @content.str.length + right_adjustment
        end

        def left_adjustment
          0
        end

        def right_adjustment
          0
        end

        # If this scalar is a key, does it indicate that attached values should
        # remain unencrypted? That is, does it begin with an underscore?
        def suppresses_encryption?
          value =~ /^_/
        end

        # since we've finally recursed all the way to an actual scalar value,
        # add it to the list of encryptable slices unless it's suppressed by an
        # underscore-prefixed key.
        def visit(sc, suppress_transform = false)
          sc.slices << self unless suppress_transform
        end

        protected

        UNESCAPES = {
          'a' => "\x07", 'b' => "\x08", 't' => "\x09",
          'n' => "\x0a", 'v' => "\x0b", 'f' => "\x0c",
          'r' => "\x0d", 'e' => "\x1b", "\\\\" => "\x5c",
          "\"" => "\x22", "'" => "\x27"
        }

        # unescape double-quoted strings. This is just copy/pasted from
        # StackOverflow.
        def unescape(str)
          # Escape all the things
          str.gsub(/\\(?:([#{UNESCAPES.keys.join}])|u([\da-fA-F]{4}))|\\0?x([\da-fA-F]{2})/) {
            if $1
              if $1 == '\\' then '\\' else UNESCAPES[$1] end
            elsif $2 # escape \u0000 unicode
              ["#$2".hex].pack('U*')
            elsif $3 # escape \0xff or \xff
              [$3].pack('H2')
            end
          }
        end
      end

      # YAML unquoted strings. e.g.:
      #
      # a: words here
      class PlainScalar < BaseScalar
        def value
          @content.str
        end
      end

      # An unquoted string like YAML's unquoted strings, except guaranteed to
      # actually represent a string
      # (e.g. ON means "ON" :: String, not true :: Bool)
      class UnquotedString < BaseScalar
        # If it required any interpretation, it wouldn't have parsed
        # as an unquoted string.
        def value
          @content.str
        end
      end

      # Since the parsers capture the whole value including the quotes, we leave
      # out the exterior quotes when interpreting the value.
      class SingleQuoted < BaseScalar
        def value
          @content.str[1..-2]
        end
      end

      # double-quoted strings are more complex. We drop the surrounding quotes
      # (through inheritance), then unescape and escaped characters in the
      # string.
      class DoubleQuoted < SingleQuoted
        def value
          unescape(super)
        end
      end

      # TOML multiline literals begin with ''', which is not part of the value.
      # If a newline follows immediately, it is also not considered part of the
      # value.
      class TOMLMultilineLiteral < BaseScalar
        def value
          @content
            .str
            .sub(/^'''\n?/, '')
            .sub(/'''$/, '')
        end
      end

      # Same as the literal, but must be unescaped just like a normal
      # double-quoted string
      class TOMLMultilineBasic < BaseScalar
        def value
          val = @content
            .str
            .sub(/^"""\n?/, '')
            .sub(/"""$/, '')
          unescape(val)
        end
      end

      # YAML block literals. Lots of complexity here to deal with the various
      # chomp modes and manual or inferred identation levels.
      #
      # http://www.yaml.org/spec/1.2/spec.html
      class BlockLiteral < BaseScalar
        def value
          chomp_mode, indentation = parse_header(@content.str.lines.first)

          processed_lines = []
          @content.str.lines[1..-1].each do |line|
            if indentation == :auto_detect
              indentation = line.scan(/^ */).flatten[0].size
            end
            processed_lines << line.sub(/^ {#{indentation}}/, '')
          end

          processed = processed_lines.join

          case chomp_mode
          when :strip
            processed.sub!(/\n+\z/m, '')
          when :clip
            processed.sub!(/\n+\z/m, "\n")
          end

          processed
        end

        def parse_header(str)
          #pipe = str[0]
          #raise unless pipe == '|'
          modifiers = ""

          [1, 2].each do |idx|
            if str[idx] && str[idx] =~ /[0-9+\-]/
              modifiers << str[idx]
            end
          end

          chomp_mode = :clip
          if modifiers.include?('-')
            chomp_mode = :strip
          elsif modifiers.include?('+')
            chomp_mode = :keep
          end

          indentation = :auto_detect
          if modifiers =~ /([0-9])/
            indentation = $1.to_i
          end

          [chomp_mode, indentation]
        end

        def right_adjustment
          -1
        end
      end

      # TODO(burke): folding doesn't work properly yet, so we kind of mangle
      # strings before encrypting them if a folded literal was used.
      class BlockFolded < BlockLiteral
        def value
          unfolded = super
          ls = unfolded.lines
          folding = false
          donefolding = false
          ls.each.with_index do |line, index|
            if line =~ /\S\n\z/m && ls[index+1] && ls[index+1] =~ /^\S/
              folding = true
              ls[index][-1] = ' '
            else
              if donefolding
                if ls[index] == "\n"
                  ls[index] = ""
                end
                donefolding = false
              end
              if folding
                donefolding = true
              end
              folding = false
            end
          end
          ls.join
        end
      end

      # Mappings from parser types to transformed node types.
      SCALAR_CLASS = {
        Parser::NodeType::PLAIN_SCALAR           => PlainScalar,
        Parser::NodeType::UNQUOTED_STRING        => UnquotedString,
        Parser::NodeType::DOUBLE_QUOTED          => DoubleQuoted,
        Parser::NodeType::SINGLE_QUOTED          => SingleQuoted,
        Parser::NodeType::TOML_MULTILINE_BASIC   => TOMLMultilineBasic,
        Parser::NodeType::TOML_MULTILINE_LITERAL => TOMLMultilineLiteral,
        Parser::NodeType::BLOCK_LITERAL          => BlockLiteral,
        Parser::NodeType::BLOCK_FOLDED           => BlockFolded,
      }.freeze

    end
  end
end
