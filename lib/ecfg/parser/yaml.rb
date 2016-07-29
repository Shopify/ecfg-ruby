require 'parslet'
require 'ecfg/parser/node_type'

module Ecfg
  module Parser
    # YAML implements a parser for Yaml, translated from the EBNF rules
    # comprising the YAML 1.2 spec.
    #
    # Most of what's here is a fairly mechanical translation, but several
    # productions required some creative interpretation, especially 170, 174,
    # 183, 185, and 187.
    #
    # See also http://www.yaml.org/spec/1.2/spec.html
    class YAML < Parslet::Parser
      class << self
        # parametric rules:
        #
        # The yaml spec uses parameterized productions to shoehorn a
        # mostly-context-free language into a context-free-grammar.
        #
        # Here we override parslet's default rule DSL method to support
        # parametric rules:
        #
        # Note that each combination of parameters passed to a rule generates a
        # new Atoms::Entity object. This is okay, since parameters in this
        # grammar are only used for indentation level and a special 'context'
        # token (with a cardinality of 6), meaning that each rule will have at
        # most 6 * max-indent-level rules generated.
        #
        # While this is not ideal, it shouldn't cause resource exhaustion or
        # anything. We're not going for performance here.
        def rule(name, &definition)
          define_method(name) do |*args|
            @rules ||= {}     # <name, rule> memoization
            key = [name, *args]
            return @rules[key] if @rules.has_key?(key)

            # Capture the self of the parser class along with the definition.
            definition_closure = proc {
              self.instance_exec(*args, &definition)
            }

            @rules[key] = Parslet::Atoms::Entity.new(name, &definition_closure)
            Parslet::Atoms::Entity.new(name, &definition_closure)
          end
        end
      end

      ## PARSE CONTEXT
      # Yaml is a context-lite language. These are the possible values for the
      # `t` and `c` context parameters from the YAML 1.2 spec.

      # values for `t` context parameter
      STRIP = :strip
      CLIP  = :clip
      KEEP  = :keep

      # values for `c` context parameter
      BLOCK_OUT = :block_out
      BLOCK_IN  = :block_in
      BLOCK_KEY = :block_key
      FLOW_OUT  = :flow_out
      FLOW_IN   = :flow_in
      FLOW_KEY  = :flow_key

      # Used to indicate no explicit nesting level was given with a block
      # literal, and we should auto-detect based on the following line.
      AUTO_DETECT = :auto_detect

      class BlockHeader
        T_VALUES = {
          '-' => STRIP,
          '+' => KEEP,
          ''  => CLIP,
        }

        M_VALUES = {
          '0' => 0,
          '1' => 1,
          '2' => 2,
          '3' => 3,
          '4' => 4,
          '5' => 5,
          '6' => 6,
          '7' => 7,
          '8' => 8,
          '9' => 9,
          ''  => AUTO_DETECT,
        }

        attr_reader :t_s, :m_s

        def initialize(t_s, m_s)
          @t_s = t_s
          @m_s = m_s
        end

        def t
          T_VALUES[t_s]
        end

        def m
          M_VALUES[m_s]
        end

        def match_length
          "#{t_s}#{m_s}".length
        end
      end

      # Used to parse block literals.
      BlockHeaders = BlockHeader::T_VALUES.keys.product(BlockHeader::M_VALUES.keys)
        .map { |t_s, m_s| BlockHeader.new(t_s, m_s) }
        .sort_by { |bh| -bh.match_length }
        .freeze

      rule(:start_of_line) {
        dynamic { |source, _context|
          if source.line_and_column[1] == 1
            any.present?
          else
            any.absent? # i.e. fail
          end
        }
      }

      ## YAML 1.2 SPEC
      # The rest of this file consists of translated productions from the spec.

      # [1] c-printable ::= #x9 | #xA | #xD | [#x20-#x7E] /* 8 bit */
      #                   | #x85 | [#xA0-#xD7FF] | [#xE000-#xFFFD] /* 16 bit */
      #                   | [#x10000-#x10FFFF] /* 32 bit */
      rule(:c_printable) {
        match["\t\n\r -~\u{e000}-\u{fffd}\u{10000}-\u{10ffff}"]
      }

      # [2] nb-json ::= #x9 | [#x20-#x10FFFF]
      rule(:nb_json) { match["\t -\u{10FFFF}"] }

      # [3] c-byte-order-mark ::= #xFEFF
      rule(:c_byte_order_mark) { str("\u{FEFF}") }

      # [4] c-sequence-entry ::= "-"
      # rule(:c_sequence_entry) { str('-') }

      # [5] c-mapping-key ::= "?"
      # rule(:c_mapping_key) { str('?') }

      # [6] c-mapping-value ::= ":"
      # rule(:c_mapping_value) { str(':') }

      # [7] c-collect-entry ::= ","
      # rule(:c_collect_entry) { str(',') }

      # [8] c-sequence-start ::= "["
      # rule(:c_sequence_start) { str('[') }

      # [9] c-sequence-end ::= "]"
      # rule(:c_sequence_end) { str(']') }

      # [10] c-mapping-start ::= "{"
      # rule(:c_mapping_start) { str('{') }

      # [11] c-mapping-end ::= "}"
      #rule(:c_mapping_end) { str('}') }

      # [12] c-comment ::= "#"
      # rule(:c_comment) { str('#') }

      # [13] c-anchor ::= "&"
      # rule(:c_anchor) { str('&') }

      # [14] c-alias ::= "*"
      # rule(:c_alias) { str('*') }

      # [15] c-tag ::= "!"
      # rule(:c_tag) { str('!') }

      # [16] c-literal ::= "|"
      # rule(:c_literal) { str('|') }

      # [17] c-folded ::= ">"
      # rule(:c_folded) { str('>') }

      # [18] c-single-quote ::= "'"
      # rule(:c_single_quote) { str("'") }

      # [19] c-double-quote ::= """
      # rule(:c_double_quote) { str('"') }

      # [20] c-directive ::= "%"
      # rule(:c_directive) { str('%') }

      # [21] c-reserved ::= "@" | "`"
      # rule(:c_reserved) { str('`') | str('@') }

      # [22] c-indicator ::= "-" | "?" | ":" | "," | "[" | "]" | "{" | "}"
      #                    | "#" | "&" | "*" | "!" | "|" | ">" | "'" | """
      #                    | "%" | "@" | "`"
      rule(:c_indicator) {
        str('-') | str('?') | str(':') | str(',') | str('[') |
        str(']') | str('{') | str('}') | str('#') | str('&') |
        str('*') | str('!') | str('|') | str('>') | str("'") |
        str('"') | str('%') | str('@') | str('`')
      }

      # [23] c-flow-indicator ::= "," | "[" | "]" | "{" | "}"
      rule(:c_flow_indicator) { str(',') | str('[') | str(']') | str('{') | str('}') }

      # [24] b-line-feed ::= #xA /* LF */
      rule(:b_line_feed) { str("\n") }

      # [25] b-carriage-return ::= #xD /* CR */
      rule(:b_carriage_return) { str("\r") }

      # [26] b-char ::= b-line-feed | b-carriage-return
      rule(:b_char) { b_line_feed | b_carriage_return }

      # [27] nb-char ::= c-printable - b-char - c-byte-order-mark
      rule(:nb_char) { (b_char | c_byte_order_mark).absent? >> c_printable }

      # [28] b-break ::= ( b-carriage-return b-line-feed ) /* DOS, Windows */
      #                | b-carriage-return /* MacOS upto 9.x */
      #                | b-line-feed /* UNIX, MacOS X */
      rule(:b_break) {
        (b_carriage_return >> b_line_feed) |
        b_carriage_return |
        b_line_feed
      }

      # [29] b-as-line-feed ::= b-break
      rule(:b_as_line_feed) { b_break }

      # [30] b-non-content ::= b-break
      rule(:b_non_content) { b_break }

      # [31] s-space ::= #x20 /* SP */
      rule(:s_space) { str(' ') }

      # [32] s-tab ::= #x9 /* TAB */
      rule(:s_tab) { str("\t") }

      # [33] s-white ::= s-space | s-tab
      rule(:s_white) { s_space | s_tab }

      # [34] ns-char ::= nb-char - s-white
      rule(:ns_char) { s_white.absent? >> nb_char }

      # [35] ns-dec-digit ::= [#x30-#x39] /* 0-9 */
      rule(:ns_dec_digit) { match('[0-9]') }

      # [36] ns-hex-digit ::= ns-dec-digit
      #                     | [#x41-#x46] /* A-F */ | [#x61-#x66] /* a-f */
      rule(:ns_hex_digit) { match('\h') }

      # [37] ns-ascii-letter ::= [#x41-#x5A] /* A-Z */ | [#x61-#x7A] /* a-z */
      rule(:ns_ascii_letter) { match('[A-z]') }

      # [38] ns-word-char ::= ns-dec-digit | ns-ascii-letter | "-"
      rule(:ns_word_char) { ns_dec_digit | ns_ascii_letter | str('-') }

      # [39] ns-uri-char ::= "%" ns-hex-digit ns-hex-digit | ns-word-char | "#"
      #                    | ";" | "/" | "?" | ":" | "@" | "&" | "=" | "+" | "$" | ","
      #                    | "_" | "." | "!" | "~" | "*" | "'" | "(" | ")" | "[" | "]"
      rule(:ns_uri_char) {
        (str('%') >> ns_hex_digit >> ns_hex_digit) | ns_word_char |
        str('#') | str(';') | str('/') | str('?') | str(':') | str('@') |
        str('&') | str('=') | str('+') | str('$') | str(',') | str('_') |
        str('.') | str('!') | str('~') | str('*') | str("'") | str('(') |
        str(')') | str('[') | str(']')
      }

      # [40] ns-tag-char ::= ns-uri-char - "!" - c-flow-indicator
      rule(:ns_tag_char) { (str('!') | c_flow_indicator).absent? >> ns_uri_char }

      # [41] c-escape ::= "\"
      rule(:c_escape) { str('\\') }

      # [42] ns-esc-null ::= "0"
      rule(:ns_esc_null) { str('0') }

      # [43] ns-esc-bell ::= "a"
      rule(:ns_esc_bell) { str('a') }

      # [44] ns-esc-backspace ::= "b"
      rule(:ns_esc_backspace) { str('b') }

      # [45] ns-esc-horizontal-tab ::= "t" | #x9
      rule(:ns_esc_horizontal_tab) { str('t') | str("\t") }

      # [46] ns-esc-line-feed ::= "n"
      rule(:ns_esc_line_feed) { str('n') }

      # [47] ns-esc-vertical-tab ::= "v"
      rule(:ns_esc_vertical_tab) { str('v') }

      # [48] ns-esc-form-feed ::= "f"
      rule(:ns_esc_form_feed) { str('f') }

      # [49] ns-esc-carriage-return ::= "r"
      rule(:ns_esc_carriage_return) { str('r') }

      # [50] ns-esc-escape ::= "e"
      rule(:ns_esc_escape) { str('e') }

      # [51] ns-esc-space ::= #x20
      rule(:ns_esc_space) { str(' ') }

      # [52] ns-esc-double-quote ::= """
      rule(:ns_esc_double_quote) { str('"') }

      # [53] ns-esc-slash ::= "/"
      rule(:ns_esc_slash) { str('/') }

      # [54] ns-esc-backslash ::= "\"
      rule(:ns_esc_backslash) { str('\\') }

      # [55] ns-esc-next-line ::= "N"
      rule(:ns_esc_next_line) { str('N') }

      # [56] ns-esc-non-breaking-space ::= "_"
      rule(:ns_esc_non_breaking_space) { str('_') }

      # [57] ns-esc-line-separator ::= "L"
      rule(:ns_esc_line_separator) { str('L') }

      # [58] ns-esc-paragraph-separator ::= "P"
      rule(:ns_esc_paragraph_separator) { str('P') }

      # [59] ns-esc-8-bit ::= "x" ns-hex-digit * 2
      rule(:ns_esc_8_bit) { ns_hex_digit.repeat(2,2) }

      # [60] ns-esc-16-bit ::= "u" ns-hex-digit * 4
      rule(:ns_esc_16_bit) { ns_hex_digit.repeat(4,4) }

      # [61] ns-esc-32-bit ::= "U" ns-hex-digit * 8
      rule(:ns_esc_32_bit) { ns_hex_digit.repeat(8,8) }

      # [62] c-ns-esc-char ::= "\" ( ns-esc-null | ns-esc-bell | ns-esc-backspace
      #                      | ns-esc-horizontal-tab | ns-esc-line-feed
      #                      | ns-esc-vertical-tab | ns-esc-form-feed
      #                      | ns-esc-carriage-return | ns-esc-escape | ns-esc-space
      #                      | ns-esc-double-quote | ns-esc-slash | ns-esc-backslash
      #                      | ns-esc-next-line | ns-esc-non-breaking-space
      #                      | ns-esc-line-separator | ns-esc-paragraph-separator
      #                      | ns-esc-8-bit | ns-esc-16-bit | ns-esc-32-bit )
      rule(:c_ns_esc_char) {
        str('\\') >> (
          ns_esc_null | ns_esc_bell | ns_esc_backspace | ns_esc_horizontal_tab |
          ns_esc_line_feed | ns_esc_vertical_tab | ns_esc_form_feed |
          ns_esc_carriage_return | ns_esc_escape | ns_esc_space |
          ns_esc_double_quote | ns_esc_slash | ns_esc_backslash |
          ns_esc_next_line | ns_esc_non_breaking_space | ns_esc_line_separator |
          ns_esc_paragraph_separator | ns_esc_8_bit | ns_esc_16_bit | ns_esc_32_bit
        )
      }

      # [63] s-indent(n) ::= s-space * n
      rule(:s_indent) { |n| n.zero? ? any.present? : s_space.repeat(n, n) }

      # [64] s-indent-lt(n) ::= s-space *< n /* Where m < n */
      rule(:s_indent_lt) { |n| n <= 1 ? any.present? : s_space.repeat(0, n - 1) }

      # [65] s-indent-le(n) ::= s-space *=< n /* Where m =< n */
      rule(:s_indent_le) { |n| n.zero? ? any.present? : s_space.repeat(0, n) }

      # [66] s-separate-in-line ::= s-white+ | /* Start of line */
      rule(:s_separate_in_line) {
        s_white.repeat(1) | start_of_line
      }

      # [67] s-line-prefix(n,c) ::= c = block-out => s-block-line-prefix(n)
      #                             c = block-in => s-block-line-prefix(n)
      #                             c = flow-out => s-flow-line-prefix(n)
      #                             c = flow-in => s-flow-line-prefix(n)
      rule(:s_line_prefix) { |n, c|
        case c
        when BLOCK_OUT, BLOCK_IN
          s_block_line_prefix(n)
        when FLOW_OUT, FLOW_IN
          s_flow_line_prefix(n)
        end
      }

      # [68] s-block-line-prefix(n) ::= s-indent(n)
      rule(:s_block_line_prefix) { |n| s_indent(n) }

      # [69] s-flow-line-prefix(n) ::= s-indent(n) s-separate-in-line?
      rule(:s_flow_line_prefix) { |n| s_indent(n) >> s_separate_in_line.maybe }

      # [70] l-empty(n,c) ::= ( s-line-prefix(n,c) | s-indent-lt(n) ) b-as-line-feed
      rule(:l_empty) { |n, c|
        (s_line_prefix(n, c) | s_indent_lt(n)) >> b_as_line_feed
      }

      # [71] b-l-trimmed(n,c) ::= b-non-content l-empty(n,c)+
      rule(:b_l_trimmed) { |n, c| b_non_content >> l_empty(n, c).repeat(1) }

      # [72] b-as-space ::= b-break
      rule(:b_as_space) { b_break }

      # [73] b-l-folded(n,c) ::= b-l-trimmed(n,c) | b-as-space
      rule(:b_l_folded) { |n, c| b_l_trimmed(n, c) | b_as_space }

      # [74] s-flow-folded(n) ::= s-separate-in-line? b-l-folded(n,flow-in)
      #                           s-flow-line-prefix(n)
      rule(:s_flow_folded) { |n|
        s_separate_in_line.maybe >> b_l_folded(n, FLOW_IN) >> s_flow_line_prefix(n)
      }

      # [75] c-nb-comment-text ::= "#" nb-char*
      rule(:c_nb_comment_text) { str('#') >> nb_char.repeat(0) }

      # [76] b-comment ::= b-non-content | /* End of file */
      rule(:b_comment) { b_non_content | any.absent? }

      # [77] s-b-comment ::= ( s-separate-in-line c-nb-comment-text? )? b-comment
      rule(:s_b_comment) { (s_separate_in_line >> c_nb_comment_text.maybe).maybe >> b_comment }

      # [78] l-comment ::= s-separate-in-line c-nb-comment-text? b-comment
      rule(:l_comment) { s_separate_in_line >> c_nb_comment_text.maybe >> b_comment }

      # [79] s-l-comments ::= ( s-b-comment | /* Start of line */ ) l-comment*
      rule(:s_l_comments) { (s_b_comment | start_of_line) >> l_comment.repeat(0, DONT_HANG) }

      # [80] s-separate(n,c) ::= c = block-out => s-separate-lines(n)
      #                          c = block-in => s-separate-lines(n)
      #                          c = flow-out => s-separate-lines(n)
      #                          c = flow-in => s-separate-lines(n)
      #                          c = block-key => s-separate-in-line
      #                          c = flow-key => s-separate-in-line
      rule(:s_separate) { |n, c|
        case c
        when BLOCK_OUT, BLOCK_IN, FLOW_OUT, FLOW_IN
          s_separate_lines(n)
        when BLOCK_KEY, FLOW_KEY
          s_separate_in_line
        else
          raise "unacceptable c: #{c.inspect}"
        end
      }

      # [81] s-separate-lines(n) ::= ( s-l-comments s-flow-line-prefix(n) )
      #                            | s-separate-in-line
      rule(:s_separate_lines) { |n|
        (s_l_comments >> s_flow_line_prefix(n)) | s_separate_in_line
      }

      # [82] l-directive ::= "%"
      #                    ( ns-yaml-directive
      #                    | ns-tag-directive
      #                    | ns-reserved-directive ) s-l-comments
      rule(:l_directive) {
        str('%') >> (ns_yaml_directive | ns_tag_directive | ns_reserved_directive) >> s_l_comments
      }

      # [83] ns-reserved-directive ::= ns-directive-name
      #                                ( s-separate-in-line ns-directive-parameter )*
      rule(:ns_reserved_directive) {
        ns_directive_name >> (s_separate_in_line >> ns_directive_parameter).repeat(0)
      }

      # [84] ns-directive-name ::= ns-char+
      rule(:ns_directive_name) { ns_char.repeat }

      # [85] ns-directive-parameter ::= ns-char+
      rule(:ns_directive_parameter) { ns_char.repeat }

      # [86] ns-yaml-directive ::= "Y" "A" "M" "L"
      #                            s-separate-in-line ns-yaml-version
      rule(:ns_yaml_directive) { str('YAML') >> s_separate_in_line >> ns_yaml_version }

      # [87] ns-yaml-version ::= ns-dec-digit+ "." ns-dec-digit+
      rule(:ns_yaml_version) { (ns_dec_digit.repeat >> str('.') >> ns_dec_digit.repeat) }

      # [88] ns-tag-directive ::= "T" "A" "G" s-separate-in-line c-tag-handle
      #                           s-separate-in-line ns-tag-prefix
      rule(:ns_tag_directive) {
        str('TAG') >> s_separate_in_line >>
        c_tag_handle >> s_separate_in_line >> ns_tag_prefix
      }

      # [89] c-tag-handle ::= c-named-tag-handle
      #                       | c-secondary-tag-handle
      #                       | c-primary-tag-handle
      rule(:c_tag_handle) { c_named_tag_handle | c_secondary_tag_handle | c_primary_tag_handle }

      # [90] c-primary-tag-handle ::= "!"
      rule(:c_primary_tag_handle) { str('!') }

      # [91] c-secondary-tag-handle ::= "!" "!"
      rule(:c_secondary_tag_handle) { str('!!') }

      # [92] c-named-tag-handle ::= "!" ns-word-char+ "!"
      rule(:c_named_tag_handle) {
        str('!') >> ns_word_char.repeat(1) >> str('!')
      }

      # [93] ns-tag-prefix ::= c-ns-local-tag-prefix | ns-global-tag-prefix
      rule(:ns_tag_prefix) { c_ns_local_tag_prefix | ns_global_tag_prefix }

      # [94] c-ns-local-tag-prefix ::= "!" ns-uri-char*
      rule(:c_ns_local_tag_prefix) {
        str('!') >> ns_uri_char.repeat(0)
      }

      # [95] ns-global-tag-prefix ::= ns-tag-char ns-uri-char*
      rule(:ns_global_tag_prefix) {
        (ns_tag_char >> ns_uri_char.repeat(0))
      }

      # [96] c-ns-properties(n,c) ::= ( c-ns-tag-property
      #                               ( s-separate(n,c) c-ns-anchor-property )? )
      #                               | ( c-ns-anchor-property
      #                               ( s-separate(n,c) c-ns-tag-property )? )
      rule(:c_ns_properties) { |n, c|
        (
          (
            c_ns_tag_property >> (s_separate(n, c) >> c_ns_anchor_property).maybe
          ) |
          (
            c_ns_anchor_property >> (s_separate(n, c) >> c_ns_tag_property).maybe
          )
        ).as(NodeType::IGNORE)
      }

      # [97] c-ns-tag-property ::= c-verbatim-tag
      #                            | c-ns-shorthand-tag
      #                            | c-non-specific-tag
      rule(:c_ns_tag_property) {
        c_verbatim_tag | c_ns_shorthand_tag | c_non_specific_tag
      }

      # [98] c-verbatim-tag ::= "!" "<" ns-uri-char+ ">"
      rule(:c_verbatim_tag) {
        str('!<') >> ns_uri_char.repeat(1) >> str('>')
      }

      # [99] c-ns-shorthand-tag ::= c-tag-handle ns-tag-char+
      rule(:c_ns_shorthand_tag) {
        c_tag_handle >> ns_tag_char.repeat(1)
      }

      # [100] c-non-specific-tag ::= "!"
      rule(:c_non_specific_tag) { str('!') }

      # [101] c-ns-anchor-property ::= "&" ns-anchor-name
      rule(:c_ns_anchor_property) { str('&') >> ns_anchor_name }

      # [102] ns-anchor-char ::= ns-char - c-flow-indicator
      rule(:ns_anchor_char) { c_flow_indicator.absent? >> ns_char }

      # [103] ns-anchor-name ::= ns-anchor-char+
      rule(:ns_anchor_name) { ns_anchor_char.repeat(1) }

      # [104] c-ns-alias-node ::= "*" ns-anchor-name
      rule(:c_ns_alias_node) { (str('*') >> ns_anchor_name).as(NodeType::IGNORE) }

      # [105] e-scalar ::= /* Empty */
      rule(:e_scalar) { str('').as(NodeType::EMPTY) }

      # [106] e-node ::= e-scalar
      rule(:e_node) { e_scalar }

      # [107] nb-double-char ::= c-ns-esc-char | ( nb-json - "\" - """ )
      rule(:nb_double_char) { c_ns_esc_char | ((str('\\') | str('"')).absent? >> nb_json) }

      # [108] ns-double-char ::= nb-double-char - s-white
      rule(:ns_double_char) { s_white.absent? >> nb_double_char }

      # [109] c-double-quoted(n,c) ::= """ nb-double-text(n,c) """
      rule(:c_double_quoted) { |n, c|
        (
          str('"') >> nb_double_text(n, c) >> str('"')
        ).as(NodeType::DOUBLE_QUOTED)
      }

      # [110] nb-double-text(n,c) ::= c = flow-out => nb-double-multi-line(n)
      #                               c = flow-in => nb-double-multi-line(n)
      #                               c = block-key => nb-double-one-line
      #                               c = flow-key => nb-double-one-line
      rule(:nb_double_text) { |n, c|
        case c
        when FLOW_OUT, FLOW_IN
          nb_double_multi_line(n)
        when BLOCK_KEY, FLOW_KEY
          nb_double_one_line
        end
      }

      # [111] nb-double-one-line ::= nb-double-char*
      rule(:nb_double_one_line) { nb_double_char.repeat(0) }

      # [112] s-double-escaped(n) ::= s-white* "\" b-non-content
      #                               l-empty(n,flow-in)* s-flow-line-prefix(n)
      rule(:s_double_escaped) { |n|
        s_white.repeat(0) >> str('\\') >> b_non_content >>
        l_empty(n, FLOW_IN).repeat(0) >> s_flow_line_prefix(n)
      }

      # [113] s-double-break(n) ::= s-double-escaped(n) | s-flow-folded(n)
      rule(:s_double_break) { |n| s_double_escaped(n) | s_flow_folded(n) }

      # [114] nb-ns-double-in-line ::= ( s-white* ns-double-char )*
      rule(:nb_ns_double_in_line) { (s_white.repeat(0) >> ns_double_char).repeat(0) }

      # [115] s-double-next-line(n) ::= s-double-break(n)
      #                                 ( ns-double-char nb-ns-double-in-line
      #                                 ( s-double-next-line(n) | s-white* ) )?
      rule(:s_double_next_line) { |n|
        s_double_break(n) >>
        (
          ns_double_char >> nb_ns_double_in_line >> (s_double_next_line(n) | s_white.repeat(0))
        ).maybe
      }

      # [116] nb-double-multi-line(n) ::= nb-ns-double-in-line
      #                                   ( s-double-next-line(n) | s-white* )
      rule(:nb_double_multi_line) { |n|
        nb_ns_double_in_line >> (s_double_next_line(n) | s_white.repeat(0))
      }

      # [117] c-quoted-quote ::= "'" "'"
      rule(:c_quoted_quote) { str("''") }

      # [118] nb-single-char ::= c-quoted-quote | ( nb-json - "'" )
      rule(:nb_single_char) { c_quoted_quote | (str("'").absent? >> nb_json) }

      # [119] ns-single-char ::= nb-single-char - s-white
      rule(:ns_single_char) { s_white.absent? >> nb_single_char }

      # [120] c-single-quoted(n,c) ::= "'" nb-single-text(n,c) "'"
      rule(:c_single_quoted) { |n, c|
        (
          str("'") >> nb_single_text(n, c) >> str("'")
        ).as(NodeType::SINGLE_QUOTED)
      }

      # [121] nb-single-text(n,c) ::= c = flow-out => nb-single-multi-line(n)
      #                               c = flow-in => nb-single-multi-line(n)
      #                               c = block-key => nb-single-one-line
      #                               c = flow-key => nb-single-one-line
      rule(:nb_single_text) { |n, c|
        case c
        when FLOW_OUT, FLOW_IN
          nb_single_multi_line(n)
        when BLOCK_KEY, FLOW_KEY
          nb_single_one_line
        end
      }

      # [122] nb-single-one-line ::= nb-single-char*
      rule(:nb_single_one_line) { nb_single_char.repeat(0) }

      # [123] nb-ns-single-in-line ::= ( s-white* ns-single-char )*
      rule(:nb_ns_single_in_line) { (s_white.repeat(0) >> ns_single_char).repeat(0) }

      # [124] s-single-next-line(n) ::= s-flow-folded(n)
      #                                 ( ns-single-char nb-ns-single-in-line
      #                                 ( s-single-next-line(n) | s-white* ) )?
      rule(:s_single_next_line) { |n|
        s_flow_folded(n) >> (
          ns_single_char >> nb_ns_single_in_line >> (s_single_next_line(n) | s_white.repeat(0))
        ).maybe
      }

      # [125] nb-single-multi-line(n) ::= nb-ns-single-in-line
      #                                   ( s-single-next-line(n) | s-white* )
      rule(:nb_single_multi_line) { |n|
        nb_ns_single_in_line >> (s_single_next_line(n) | s_white.repeat(0))
      }

      # [126] ns-plain-first(c) ::= ( ns-char - c-indicator )
      #                           | ( ( "?" | ":" | "-" )
      #                           /* Followed by an ns-plain-safe(c)) */ )
      rule(:ns_plain_first) { |c|
        c_indicator.absent? >> ns_char |
          (match('[\?:\-]') >> ns_plain_safe(c).present?)
      }

      # [127] ns-plain-safe(c) ::= c = flow-out => ns-plain-safe-out
      #                            c = flow-in => ns-plain-safe-in
      #                            c = block-key => ns-plain-safe-out
      #                            c = flow-key => ns-plain-safe-in
      rule(:ns_plain_safe) { |c|
        case c
        when FLOW_OUT, BLOCK_KEY
          ns_plain_safe_out
        when FLOW_IN, FLOW_KEY
          ns_plain_safe_in
        end
      }

      # [128] ns-plain-safe-out ::= ns-char
      rule(:ns_plain_safe_out) { ns_char }

      # [129] ns-plain-safe-in ::= ns-char - c-flow-indicator
      rule(:ns_plain_safe_in) { c_flow_indicator.absent? >> ns_char }

      # [130] ns-plain-char(c) ::= ( ns-plain-safe(c) - ":" - "#" )
      #                          | ( /* An ns-char preceding */ "#" )
      #                          | ( ":" /* Followed by an ns-plain-safe(c) */ )
      rule(:ns_plain_char) { |c|
        match('[:#]').absent? >> ns_plain_safe(c) |
          ns_char >> str('#').present? |
          str(':') >> ns_plain_safe(c).present?
      }

      # [131] ns-plain(n,c) ::= c = flow-out => ns-plain-multi-line(n,c)
      #                         c = flow-in => ns-plain-multi-line(n,c)
      #                         c = block-key => ns-plain-one-line(c)
      #                         c = flow-key => ns-plain-one-line(c)
      rule(:ns_plain) { |n, c|
        case c
        when FLOW_OUT, FLOW_IN
          ns_plain_multi_line(n,c)
        when BLOCK_KEY, FLOW_KEY
          ns_plain_one_line(c)
        end
      }

      # [132] nb-ns-plain-in-line(c) ::= ( s-white* ns-plain-char(c) )*
      rule(:nb_ns_plain_in_line) { |c|
        (s_white.repeat(0) >> ns_plain_char(c)).repeat(0)
      }

      # [133] ns-plain-one-line(c) ::= ns-plain-first(c) nb-ns-plain-in-line(c)
      rule(:ns_plain_one_line) { |c|
        (ns_plain_first(c) >> nb_ns_plain_in_line(c)).as(NodeType::PLAIN_SCALAR)
      }

      # [134] s-ns-plain-next-line(n,c) ::= s-flow-folded(n)
      #                                     ns-plain-char(c) nb-ns-plain-in-line(c)
      rule(:s_ns_plain_next_line) { |n, c|
        s_flow_folded(n) >> ns_plain_char(c) >> nb_ns_plain_in_line(c)
      }

      # [135] ns-plain-multi-line(n,c) ::= ns-plain-one-line(c)
      #                                    s-ns-plain-next-line(n,c)*
      rule(:ns_plain_multi_line) { |n, c|
        ns_plain_one_line(c) >> s_ns_plain_next_line(n, c).repeat(0)
      }

      # [136] in-flow(c) ::= c = flow-out => flow-in
      #                      c = flow-in => flow-in
      #                      c = block-key => flow-key
      #                      c = flow-key => flow-key
      def self.in_flow(c)
        case c
        when FLOW_OUT, FLOW_IN
          FLOW_IN
        when BLOCK_KEY, FLOW_KEY
          FLOW_KEY
        end
      end

      # [137] c-flow-sequence(n,c) ::= "[" s-separate(n,c)?
      #                                ns-s-flow-seq-entries(n,in-flow(c))? "]"
      rule(:c_flow_sequence) { |n, c|
        str('[') >>
        s_separate(n, c).maybe >>
        (ns_s_flow_seq_entries(n, YAML.in_flow(c)) | str('').as(NodeType::SEQ)) >>
        str(']')
      }

      # [138] ns-s-flow-seq-entries(n,c) ::= ns-flow-seq-entry(n,c) s-separate(n,c)?
      #                                      ( "," s-separate(n,c)?
      #                                      ns-s-flow-seq-entries(n,c)? )?
      rule(:ns_s_flow_seq_entries) { |n, c|
        (
          ns_flow_seq_entry(n, c) >> s_separate(n, c).maybe >>
          (
            str(',') >>
            s_separate(n, c).maybe >>
            ns_flow_seq_entry(n, c) >>
            s_separate(n, c).maybe
          ).repeat(0)
        ).as(NodeType::SEQ)
      }

      # [139] ns-flow-seq-entry(n,c) ::= ns-flow-pair(n,c) | ns-flow-node(n,c)
      rule(:ns_flow_seq_entry) { |n, c|
        ns_flow_pair(n, c) | ns_flow_node(n, c)
      }

      # [140] c-flow-mapping(n,c) ::= "{" s-separate(n,c)?
      #                               ns-s-flow-map-entries(n,in-flow(c))? "}"
      rule(:c_flow_mapping) { |n, c|
        str('{') >>
        s_separate(n, c).maybe >>
        (ns_s_flow_map_entries(n, YAML.in_flow(c)).maybe | str('').as(NodeType::MAP)) >>
        str('}')
      }

      # [141] ns-s-flow-map-entries(n,c) ::= ns-flow-map-entry(n,c) s-separate(n,c)?
      #                                      ( "," s-separate(n,c)?
      #                                      ns-s-flow-map-entries(n,c)? )?
      rule(:ns_s_flow_map_entries) { |n, c|
        (
          ns_flow_map_entry(n, c) >> s_separate(n, c).maybe >>
          (
            str(',') >>
            s_separate(n, c).maybe >>
            ns_flow_map_entry(n, c) >>
            s_separate(n, c).maybe
          ).repeat(0)
        ).as(NodeType::MAP)
      }

      # [142] ns-flow-map-entry(n,c) ::= ( "?" s-separate(n,c)
      #                                  ns-flow-map-explicit-entry(n,c) )
      #                                  | ns-flow-map-implicit-entry(n,c)
      rule(:ns_flow_map_entry) { |n, c|
        str('?') >> s_separate(n, c) >> ns_flow_map_implicit_entry(n, c) |
          ns_flow_map_implicit_entry(n, c)
      }

      # [143] ns-flow-map-explicit-entry(n,c) ::= ns-flow-map-implicit-entry(n,c)
      #                                           | ( e-node /* Key */
      #                                           e-node /* Value */ )
      rule(:ns_flow_map_explicit_entry) { |n, c|
        ((ns_flow_map_implicit_entry(n, c) | e_node).as(NodeType::KEY) >> e_node.as(NodeType::VALUE) ).as(NodeType::PAIR)
      }

      # [144] ns-flow-map-implicit-entry(n,c) ::= ns-flow-map-yaml-key-entry(n,c)
      #                                           | c-ns-flow-map-empty-key-entry(n,c)
      #                                           | c-ns-flow-map-json-key-entry(n,c)
      rule(:ns_flow_map_implicit_entry) { |n, c|
        ns_flow_map_yaml_key_entry(n, c) |
          c_ns_flow_map_empty_key_entry(n, c) |
          c_ns_flow_map_json_key_entry(n, c)
      }

      # [145] ns-flow-map-yaml-key-entry(n,c) ::= ns-flow-yaml-node(n,c)
      #                                           ( ( s-separate(n,c)?
      #                                           c-ns-flow-map-separate-value(n,c) )
      #                                           | e-node )
      rule(:ns_flow_map_yaml_key_entry) { |n, c|
        (
          ns_flow_yaml_node(n, c).as(NodeType::KEY) >>
          (s_separate(n, c).maybe >> c_ns_flow_map_separate_value(n, c).as(NodeType::VALUE) | e_node.as(NodeType::VALUE))
        ).as(NodeType::PAIR)
      }

      # [146] c-ns-flow-map-empty-key-entry(n,c) ::= e-node /* Key */
      #                                              c-ns-flow-map-separate-value(n,c)
      rule(:c_ns_flow_map_empty_key_entry) { |n, c|
        (e_node.as(NodeType::KEY) >> c_ns_flow_map_separate_value(n, c).as(NodeType::VALUE)).as(NodeType::PAIR)
      }

      # [147] c-ns-flow-map-separate-value(n,c) ::= ":" /* Not followed by an
      #                                             ns-plain-safe(c) */
      #                                           ( ( s-separate(n,c) ns-flow-node(n,c) )
      #                                           | e-node /* Value */ )
      rule(:c_ns_flow_map_separate_value) { |n, c|
        str(':') >> ns_plain_safe(c).absent? >> (
          s_separate(n, c) >> ns_flow_node(n, c) | e_node
        )
      }

      # [148] c-ns-flow-map-json-key-entry(n,c) ::= c-flow-json-node(n,c)
      #                                             ( ( s-separate(n,c)?
      #                                             c-ns-flow-map-adjacent-value(n,c) )
      #                                             | e-node )
      rule(:c_ns_flow_map_json_key_entry) { |n, c|
        (
          c_flow_json_node(n, c).as(NodeType::KEY) >>
          (
            s_separate(n, c).maybe >> c_ns_flow_map_adjacent_value(n, c) |
            e_node
          ).as(NodeType::VALUE)
        ).as(NodeType::PAIR)
      }

      # [149] c-ns-flow-map-adjacent-value(n,c) ::= ":" ( ( s-separate(n,c)?
      #                                             ns-flow-node(n,c) )
      #                                             | e-node ) /* Value */
      rule(:c_ns_flow_map_adjacent_value) { |n, c|
        str(':') >> (
          s_separate(n, c).maybe >> ns_flow_node(n, c) | e_node
        )
      }

      # [150] ns-flow-pair(n,c) ::= ( "?" s-separate(n,c)
      #                             ns-flow-map-explicit-entry(n,c) )
      #                             | ns-flow-pair-entry(n,c)
      rule(:ns_flow_pair) { |n, c|
        (str('?') >> s_separate(n, c) >> ns_flow_map_explicit_entry(n, c)) | ns_flow_pair_entry(n, c)
      }

      # [151] ns-flow-pair-entry(n,c) ::= ns-flow-pair-yaml-key-entry(n,c)
      #                                 | c-ns-flow-map-empty-key-entry(n,c)
      #                                 | c-ns-flow-pair-json-key-entry(n,c)
      rule(:ns_flow_pair_entry) { |n, c|
        ns_flow_pair_yaml_key_entry(n, c) |
          c_ns_flow_map_empty_key_entry(n, c) |
          c_ns_flow_pair_json_key_entry(n, c)
      }

      # [152] ns-flow-pair-yaml-key-entry(n,c) ::= ns-s-implicit-yaml-key(flow-key)
      #                                            c-ns-flow-map-separate-value(n,c)
      rule(:ns_flow_pair_yaml_key_entry) { |n, c|
        (
          ns_s_implicit_yaml_key(FLOW_KEY).as(NodeType::KEY) >> c_ns_flow_map_separate_value(n, c).as(NodeType::VALUE)
        ).as(NodeType::PAIR)
      }

      # [153] c-ns-flow-pair-json-key-entry(n,c) ::= c-s-implicit-json-key(flow-key)
      #                                              c-ns-flow-map-adjacent-value(n,c)
      rule(:c_ns_flow_pair_json_key_entry) { |n, c|
        (
          c_s_implicit_json_key(FLOW_KEY).as(NodeType::KEY) >> c_ns_flow_map_adjacent_value(n, c).as(NodeType::VALUE)
        ).as(NodeType::PAIR)
      }

      # [154] ns-s-implicit-yaml-key(c) ::= ns-flow-yaml-node(na,c) s-separate-in-line?
      #                                     /* At most 1024 characters altogether */
      rule(:ns_s_implicit_yaml_key) { |c|
        ns_flow_yaml_node(0, c) >> s_separate_in_line.maybe
      }

      # [155] c-s-implicit-json-key(c) ::= c-flow-json-node(na,c) s-separate-in-line?
      #                                    /* At most 1024 characters altogether */
      rule(:c_s_implicit_json_key) { |c|
        c_flow_json_node(0, c) >> s_separate_in_line.maybe
      }

      # [156] ns-flow-yaml-content(n,c) ::= ns-plain(n,c)
      rule(:ns_flow_yaml_content) { |n, c|
        ns_plain(n, c)
      }

      # [157] c-flow-json-content(n,c) ::= c-flow-sequence(n,c) | c-flow-mapping(n,c)
      #                                    | c-single-quoted(n,c) | c-double-quoted(n,c)
      rule(:c_flow_json_content) { |n, c|
        c_flow_sequence(n,c) | c_flow_mapping(n,c) |
        c_single_quoted(n,c) | c_double_quoted(n,c)
      }

      # [158] ns-flow-content(n,c) ::= ns-flow-yaml-content(n,c)
      #                              | c-flow-json-content(n,c)
      rule(:ns_flow_content) { |n, c|
        ns_flow_yaml_content(n, c) |
        c_flow_json_content(n, c)
      }

      # [159] ns-flow-yaml-node(n,c) ::= c-ns-alias-node
      #                                  | ns-flow-yaml-content(n,c)
      #                                  | ( c-ns-properties(n,c)
      #                                  ( ( s-separate(n,c)
      #                                  ns-flow-yaml-content(n,c) )
      #                                  | e-scalar ) )
      rule(:ns_flow_yaml_node) { |n, c|
        c_ns_alias_node |
        ns_flow_yaml_content(n, c) |
        c_ns_properties(n, c) >> (s_separate(n, c) >> ns_flow_yaml_content(n, c) | e_scalar)
      }

      # [160] c-flow-json-node(n,c) ::= ( c-ns-properties(n,c) s-separate(n,c) )?
      #                                 c-flow-json-content(n,c)
      rule(:c_flow_json_node) { |n, c|
        (c_ns_properties(n, c) >> s_separate(n, c)).maybe >> c_flow_json_content(n, c)
      }

      # [161] ns-flow-node(n,c) ::= c-ns-alias-node
      #                             | ns-flow-content(n,c)
      #                             | ( c-ns-properties(n,c)
      #                             ( ( s-separate(n,c) ns-flow-content(n,c) )
      #                             | e-scalar ) )
      rule(:ns_flow_node) { |n, c|
        c_ns_alias_node |
        ns_flow_content(n, c) |
        c_ns_properties(n, c) >> (s_separate(n, c) >> ns_flow_content(n, c) | e_scalar)
      }

      # [162] c-b-block-header(m,t) ::= ( ( c-indentation-indicator(m)
      #                                 c-chomping-indicator(t) )
      #                                 | ( c-chomping-indicator(t)
      #                                 c-indentation-indicator(m) ) )s-b-comment
      # (inlined in #170 and #174)

      # [163] c-indentation-indicator(m) ::= ns-dec-digit => m = ns-dec-digit - #x30
      #                                      /* Empty */ => m = auto-detect()
      # (inlined in #170 and #174)

      # [164] c-chomping-indicator(t) ::= "-" => t = strip
      #                                   "+" => t = keep
      #                                   /* Empty */ => t = clip
      # (inlined in #170 and #174)

      # [165] b-chomped-last(t) ::= t = strip => b-non-content | /* End of file */
      #                             t = clip => b-as-line-feed | /* End of file */
      #                             t = keep => b-as-line-feed | /* End of file */
      rule(:b_chomped_last) { |t|
        case t
        when STRIP
          b_non_content | any.absent?
        when CLIP, KEEP
          b_as_line_feed | any.absent?
        end
      }

      # [166] l-chomped-empty(n,t) ::= t = strip => l-strip-empty(n)
      #                                t = clip => l-strip-empty(n)
      #                                t = keep => l-keep-empty(n)
      rule(:l_chomped_empty) { |n, t|
        case t
        when STRIP
          l_strip_empty(n)
        when CLIP
          l_strip_empty(n)
        when KEEP
          l_keep_empty(n)
        end
      }

      # [167] l-strip-empty(n) ::= ( s-indent-le(n) b-non-content )* l-trail-comments(n)?
      rule(:l_strip_empty) { |n|
        (s_indent_le(n) >> b_non_content).maybe >> l_trail_comments(n).maybe
      }

      # [168] l-keep-empty(n) ::= l-empty(n,block-in)* l-trail-comments(n)?
      rule(:l_keep_empty) { |n|
        l_empty(n, BLOCK_IN).repeat(0) >> l_trail_comments(n).maybe
      }

      # [169] l-trail-comments(n) ::= s-indent-lt(n) c-nb-comment-text b-comment
      #                               l-comment*
      rule(:l_trail_comments) { |n|
        s_indent_lt(n) >> c_nb_comment_text >> b_comment >> l_comment.repeat(0)
      }

      # [170] c-l+literal(n) ::= "|" c-b-block-header(m,t) l-literal-content(n+m,t)
      rule(:c_l_literal) { |n|
        (
          str('|') >>
          BlockHeaders.reduce(nil) do |acc, bh|
            header = (
              (str(bh.t_s) >> str(bh.m_s)) | 
              (str(bh.m_s) >> str(bh.t_s))
            )
            content = case bh.m
            when AUTO_DETECT
              s_space.repeat(0).capture(:n_plus_m).present? >>
              dynamic { |_, context|
                indent = context.captures[:n_plus_m].length
                l_literal_content(indent, bh.t)
              }
            else
              l_literal_content(n + bh.m, bh.t)
            end

            full = header >> s_b_comment >> content
            acc.nil? ? full : (acc | full)
          end
        ).as(NodeType::BLOCK_LITERAL)
      }

      # [171] l-nb-literal-text(n) ::= l-empty(n,block-in)*
      #                                s-indent(n) nb-char+
      rule(:l_nb_literal_text) { |n|
        l_empty(n, BLOCK_IN).repeat(0) >> s_indent(n) >> nb_char.repeat(1)
      }

      # [172] b-nb-literal-next(n) ::= b-as-line-feed
      #                                l-nb-literal-text(n)
      rule(:b_nb_literal_next) { |n|
        b_as_line_feed >> l_nb_literal_text(n)
      }

      # [173] l-literal-content(n,t) ::= ( l-nb-literal-text(n) b-nb-literal-next(n)*
      #                                  b-chomped-last(t) )?
      #                                  l-chomped-empty(n,t)
      rule(:l_literal_content) { |n, t|
        (l_nb_literal_text(n) >> b_nb_literal_next(n).repeat(0) >> b_chomped_last(t)).maybe >>
        l_chomped_empty(n, t)
      }

      # [174] c-l+folded(n) ::= ">" c-b-block-header(m,t)
      #                         l-folded-content(n+m,t)
      rule(:c_l_folded) { |n|
        (
          str('>') >>
          BlockHeaders.reduce(nil) do |acc, bh|
            header = (
              (str(bh.t_s) >> str(bh.m_s)) | 
              (str(bh.m_s) >> str(bh.t_s))
            )
            content = case bh.m
            when AUTO_DETECT
              s_space.repeat(0).capture(:n_plus_m).present? >>
              dynamic { |_, context|
                indent = context.captures[:n_plus_m].length
                l_folded_content(indent, bh.t)
              }
            else
              l_folded_content(n + bh.m, bh.t)
            end

            full = header >> s_b_comment >> content
            acc.nil? ? full : (acc | full)
          end
        ).as(NodeType::BLOCK_FOLDED)
      }

      # [175] s-nb-folded-text(n) ::= s-indent(n) ns-char nb-char*
      rule(:s_nb_folded_text) { |n|
        s_indent(n) >> (ns_char >> nb_char.repeat(0))
      }

      # [176] l-nb-folded-lines(n) ::= s-nb-folded-text(n)
      #                                ( b-l-folded(n,block-in) s-nb-folded-text(n) )*
      rule(:l_nb_folded_lines) { |n|
        s_nb_folded_text(n) >> (b_l_folded(n, BLOCK_IN) >> s_nb_folded_text(n)).repeat(0)
      }

      # [177] s-nb-spaced-text(n) ::= s-indent(n) s-white nb-char*
      rule(:s_nb_spaced_text) { |n|
        s_indent(n) >> s_white >> nb_char.repeat(0)
      }

      # [178] b-l-spaced(n) ::= b-as-line-feed
      #                         l-empty(n,block-in)*
      rule(:b_l_spaced) { |n|
        b_as_line_feed >> l_empty(n, BLOCK_IN).repeat(0)
      }

      # [179] l-nb-spaced-lines(n) ::= s-nb-spaced-text(n)
      #                                ( b-l-spaced(n) s-nb-spaced-text(n) )*
      rule(:l_nb_spaced_lines) { |n|
        s_nb_spaced_text(n) >> (b_l_spaced(n) >> s_nb_spaced_text(n)).repeat(0)
      }

      # [180] l-nb-same-lines(n) ::= l-empty(n,block-in)*
      #                              ( l-nb-folded-lines(n) | l-nb-spaced-lines(n) )
      rule(:l_nb_same_lines) { |n|
        l_empty(n, BLOCK_IN).repeat(0) >> (l_nb_folded_lines(n) | l_nb_spaced_lines(n))
      }

      # [181] l-nb-diff-lines(n) ::= l-nb-same-lines(n)
      #                              ( b-as-line-feed l-nb-same-lines(n) )*
      rule(:l_nb_diff_lines) { |n|
        l_nb_same_lines(n) >> (b_as_line_feed >> l_nb_same_lines(n)).repeat(0)
      }

      # [182] l-folded-content(n,t) ::= ( l-nb-diff-lines(n) b-chomped-last(t) )?
      #                                 l-chomped-empty(n,t)
      rule(:l_folded_content) { |n, t|
        (l_nb_diff_lines(n) >> b_chomped_last(t)).maybe >> l_chomped_empty(n, t)
      }

      # [183] l+block-sequence(n) ::= ( s-indent(n+m) c-l-block-seq-entry(n+m) )+
      #                               /* For some fixed auto-detected m > 0 */
      rule(:l_block_sequence) { |n|
        s_space.repeat(n).capture(:n_plus_m).present? >>
        dynamic { |_source, context|
          n_plus_m = context.captures[:n_plus_m].length
          (
            s_space.repeat(n_plus_m) >>
            c_l_block_seq_entry(n_plus_m)
          ).repeat(1).as(NodeType::SEQ)
        }
      }

      # [184] c-l-block-seq-entry(n) ::= "-" /* Not followed by an ns-char */
      #                                  s-l+block-indented(n,block-in)
      rule(:c_l_block_seq_entry) { |n|
        str('-') >> ns_char.absent? >> s_l_block_indented(n, BLOCK_IN)
      }

      # [185] s-l+block-indented(n,c) ::= ( s-indent(m)
      #                                   ( ns-l-compact-sequence(n+1+m)
      #                                   | ns-l-compact-mapping(n+1+m) ) )
      #                                   | s-l+block-node(n,c)
      #                                   | ( e-node s-l-comments )
      rule(:s_l_block_indented) { |n, c|
        (
          s_space.repeat(0).capture(:m) >>
          dynamic { |_source, context|
            m = context.captures[:m].length
            ns_l_compact_sequence(n + 1 + m) | ns_l_compact_mapping(n + 1 + m)
          }
        ) |
        s_l_block_node(n, c) |
        (e_node >> s_l_comments)
      }

      # [186] ns-l-compact-sequence(n) ::= c-l-block-seq-entry(n)
      #                                    ( s-indent(n) c-l-block-seq-entry(n) )*
      rule(:ns_l_compact_sequence) { |n|
        (
          c_l_block_seq_entry(n) >> (s_indent(n) >> c_l_block_seq_entry(n)).repeat(0)
        ).as(NodeType::SEQ)
      }

      # [187] l+block-mapping(n) ::= ( s-indent(n+m) ns-l-block-map-entry(n+m) )+
      #                              /* For some fixed auto-detected m > 0 */
      rule(:l_block_mapping) { |n|
        s_space.repeat(n).capture(:n_plus_m) >>
        dynamic { |_source, context|
          n_plus_m = context.captures[:n_plus_m].length

          ns_l_block_map_entry(n_plus_m) >>
          (
            s_indent(n_plus_m) >>
            ns_l_block_map_entry(n_plus_m)
          ).repeat(0)
        }.as(NodeType::MAP)
      }

      # [188] ns-l-block-map-entry(n) ::= c-l-block-map-explicit-entry(n)
      #                                   | ns-l-block-map-implicit-entry(n)
      rule(:ns_l_block_map_entry) { |n|
        c_l_block_map_explicit_entry(n) |
        ns_l_block_map_implicit_entry(n)
      }

      # [189] c-l-block-map-explicit-entry(n) ::= c-l-block-map-explicit-key(n)
      #                                           ( l-block-map-explicit-value(n)
      #                                           | e-node )
      rule(:c_l_block_map_explicit_entry) { |n|
        (
          c_l_block_map_explicit_key(n).as(NodeType::KEY) >>
          (l_block_map_explicit_value(n) | e_node).as(NodeType::VALUE)
        ).as(NodeType::PAIR)
      }

      # [190] c-l-block-map-explicit-key(n) ::= "?" s-l+block-indented(n,block-out)
      rule(:c_l_block_map_explicit_key) { |n|
        str('?') >> s_l_block_indented(n, BLOCK_OUT)
      }

      # [191] l-block-map-explicit-value(n) ::= s-indent(n)
      #                                         ":" s-l+block-indented(n,block-out)
      rule(:l_block_map_explicit_value) { |n|
        s_indent(n) >> str(':') >> s_l_block_indented(n, BLOCK_OUT)
      }

      # [192] ns-l-block-map-implicit-entry(n) ::= ( ns-s-block-map-implicit-key
      #                                            | e-node )
      #                                            c-l-block-map-implicit-value(n)
      rule(:ns_l_block_map_implicit_entry) { |n|
        (
          (ns_s_block_map_implicit_key | e_node).as(NodeType::KEY) >>
          c_l_block_map_implicit_value(n).as(NodeType::VALUE)
        ).as(NodeType::PAIR)
      }

      # [193] ns-s-block-map-implicit-key ::= c-s-implicit-json-key(block-key)
      #                                       | ns-s-implicit-yaml-key(block-key)
      rule(:ns_s_block_map_implicit_key) {
        c_s_implicit_json_key(BLOCK_KEY) | ns_s_implicit_yaml_key(BLOCK_KEY)
      }

      # [194] c-l-block-map-implicit-value(n) ::= ":" ( s-l+block-node(n,block-out)
      #                                               | ( e-node s-l-comments ) )
      rule(:c_l_block_map_implicit_value) { |n|
        str(':') >> (s_l_block_node(n, BLOCK_OUT) | e_node >> s_l_comments)
      }

      # [195] ns-l-compact-mapping(n) ::= ns-l-block-map-entry(n)
      #                                   ( s-indent(n) ns-l-block-map-entry(n) )*
      rule(:ns_l_compact_mapping) { |n|
        (
          ns_l_block_map_entry(n) >> (s_indent(n) >> ns_l_block_map_entry(n)).repeat(0)
        ).as(NodeType::MAP)
      }

      # [196] s-l+block-node(n,c) ::= s-l+block-in-block(n,c) | s-l+flow-in-block(n)
      rule(:s_l_block_node) { |n, c|
        s_l_block_in_block(n, c) | s_l_flow_in_block(n)
      }

      # [197] s-l+flow-in-block(n) ::= s-separate(n+1,flow-out)
      #                                ns-flow-node(n+1,flow-out) s-l-comments
      rule(:s_l_flow_in_block) { |n|
        s_separate(n + 1, FLOW_OUT) >> ns_flow_node(n + 1, FLOW_OUT) >> s_l_comments
      }

      # [198] s-l+block-in-block(n,c) ::= s-l+block-scalar(n,c)
      #                                   | s-l+block-collection(n,c)
      rule(:s_l_block_in_block) { |n, c|
        s_l_block_scalar(n, c) | s_l_block_collection(n, c)
      }

      # [199] s-l+block-scalar(n,c) ::= s-separate(n+1,c)
      #                                 ( c-ns-properties(n+1,c) s-separate(n+1,c) )?
      #                                 ( c-l+literal(n) | c-l+folded(n) )
      rule(:s_l_block_scalar) { |n, c|
        s_separate(n + 1, c) >>
        (c_ns_properties(n + 1, c) >> s_separate(n + 1, c)).maybe >>
        (c_l_literal(n) | c_l_folded(n))
      }

      # [200] s-l+block-collection(n,c) ::= ( s-separate(n+1,c) c-ns-properties(n+1,c) )?
      #                                     s-l-comments
      #                                     ( l+block-sequence(seq-spaces(n,c))
      #                                     | l+block-mapping(n) )
      rule(:s_l_block_collection) { |n, c|
        (s_separate(n + 1, c) >> c_ns_properties(n + 1, c)).maybe >>
        s_l_comments >> (l_block_sequence(YAML.seq_spaces(n, c)) | l_block_mapping(n))
      }

      # [201] seq-spaces(n,c) ::= c = block-out => n-1
      #                            c = block-in => n
      def self.seq_spaces(n, c)
        case c
        when BLOCK_OUT
          n - 1
        when BLOCK_IN
          n
        end
      end

      # [202] l-document-prefix ::= c-byte-order-mark? l-comment*
      rule(:l_document_prefix) { c_byte_order_mark.maybe >> l_comment.repeat(0, DONT_HANG) }

      # [203] c-directives-end ::= "-" "-" "-"
      rule(:c_directives_end) { str('---') }

      # [204] c-document-end ::= "." "." "."
      rule(:c_document_end) { str('...') }

      # [205] l-document-suffix ::= c-document-end s-l-comments
      rule(:l_document_suffix) { c_document_end | s_l_comments }

      # [206] c-forbidden ::= /* Start of line */ ( c-directives-end |
      #                       c-document-end ) ( b-char | s-white | /* End of file */ )
      rule(:c_forbidden) {
        start_of_line >> (c_directives_end | c_document_end) >> (b_char | s_white | any.absent?)
      }

      # [207] l-bare-document ::= s-l+block-node(-1,block-in)
      #                           /* Excluding c-forbidden content */
      rule(:l_bare_document) { s_l_block_node(-1, BLOCK_IN) }

      # [208] l-explicit-document ::= c-directives-end ( l-bare-document
      #                             | ( e-node s-l-comments ) )
      rule(:l_explicit_document) {
        c_directives_end >> (l_bare_document | e_node >> s_l_comments)
      }

      # [209] l-directive-document ::= l-directive+ l-explicit-document
      rule(:l_directive_document) { l_directive.repeat(1) >> l_explicit_document }

      # [210] l-any-document ::= l-directive-document
      #                        | l-explicit-document | l-bare-document
      rule(:l_any_document) {
        l_directive_document | l_explicit_document | l_bare_document
      }

      DONT_HANG = 5

      # [211] l-yaml-stream ::= l-document-prefix* l-any-document?
      #                         ( l-document-suffix+ l-document-prefix* l-any-document?
      #                         | l-document-prefix* l-explicit-document? )*
      rule(:l_yaml_stream) {
        l_document_prefix.repeat(0,DONT_HANG) >> l_any_document.maybe >>
        (
          l_document_suffix.repeat(1,DONT_HANG) >> l_document_prefix.repeat(0,DONT_HANG) >> l_any_document.maybe |
          l_document_prefix.repeat(0,DONT_HANG) >> l_explicit_document.maybe
        ).repeat(0,DONT_HANG)
      }

      root(:l_yaml_stream)
    end
  end
end
