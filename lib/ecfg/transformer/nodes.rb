module Ecfg
  class Transformer
    module Nodes
      class Map
        attr_reader :pairs

        def initialize(pairs)
          @pairs = Array(pairs)
        end

        def visit(sc, suppress_transform = false)
          # suppression does not propagate downward.
          pairs.each { |pair| pair.visit(sc, false) }
        end
      end

      class Seq
        attr_reader :items

        def initialize(items)
          @items = Array(items)
        end

        def visit(sc, suppress_transform = false)
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
        def visit(sc, suppress_transform = false)
        end
      end

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

        def suppresses_encryption?
          value =~ /^_/
        end

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

      class PlainScalar < BaseScalar
        def value
          @content.str
        end
      end

      class UnquotedString < BaseScalar
        # If it required any interpretation, it wouldn't have parsed
        # as an unquoted string.
        def value
          @content.str
        end
      end

      class SingleQuoted < BaseScalar
        def value
          @content.str[1..-2]
        end
      end

      class DoubleQuoted < SingleQuoted
        def value
          unescape(super)
        end
      end

      class TOMLMultilineLiteral < BaseScalar
        def value
          @content
            .str
            .sub(/^"""\n?/, '')
            .sub(/"""$/, '')
        end
      end

      class TOMLMultilineBasic < TOMLMultilineLiteral
        def value
          unescape(super)
        end
      end

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
