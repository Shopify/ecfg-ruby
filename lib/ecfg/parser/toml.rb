require 'parslet'
require 'ecfg/parser/node_type'

module Ecfg
  module Parser
    # https://github.com/toml-lang/toml/blob/532a4668/toml.abnf
    class TOML < Parslet::Parser
      # ;; TOML

      # toml = expression *( newline expression )
      root(:toml)
      rule(:toml) { expression >> (newline >> expression).repeat(0) }

      # expression = (
      #   ws /
      #   ws comment /
      #   ws keyval ws [ comment ] /
      #   ws table ws [ comment ]
      # )
      rule(:expression) {
        (ws >> keyval >> ws >> comment.maybe) |
        (ws >> table >> ws >> comment.maybe) |
        (ws >> comment) |
        ws
      }

      # ;; Newline

      # newline = (
      #   %x0A /              ; LF
      #   %x0D.0A             ; CRLF
      # )
      rule(:newline) { str("\n") | str("\r\n") }

      # newlines = 1*newline
      rule(:newlines) { newline.repeat(1) }

      # ;; Whitespace

      # ws = *(
      #   %x20 /              ; Space
      #   %x09                ; Horizontal tab
      # )
      rule(:ws) { match[" \t"].repeat(0) }

      # ;; Comment

      # comment-start-symbol = %x23 ; #
      rule(:comment_start_symbol) { str('#') }
      # non-eol = %x09 / %x20-10FFFF
      rule(:non_eol) { str("\t") | match[" -\u{10FFFF}"] }
      # comment = comment-start-symbol *non-eol
      rule(:comment) { comment_start_symbol >> non_eol.repeat(0) }

      # ;; Key-Value pairs

      # keyval-sep = ws %x3D ws ; =
      rule(:keyval_sep) { ws >> str('=') >> ws }
      # keyval = key keyval-sep val
      rule(:keyval) {
        (
          key.as(NodeType::KEY) >>
          keyval_sep >>
          val.as(NodeType::VALUE)
        ).as(NodeType::PAIR)
      }

      # key = unquoted-key / quoted-key
      rule(:key) { unquoted_key | quoted_key }
      # unquoted-key = 1*( ALPHA / DIGIT / %x2D / %x5F ) ; A-Z / a-z / 0-9 / - / _
      rule(:unquoted_key) {
        match['A-Za-z0-9\-_'].repeat(1).as(NodeType::UNQUOTED_STRING)
      }
      # quoted-key = quotation-mark 1*basic-char quotation-mark ; See Basic Strings
      rule(:quoted_key) {
        (
          quotation_mark >> basic_char.repeat(1) >> quotation_mark
        ).as(NodeType::DOUBLE_QUOTED)
      }

      # val = integer / float / string / boolean / date-time / array / inline-table
      rule(:val) {
        integer | float | string | boolean | date_time | array | inline_table
      }

      # ;; Table

      # table = std-table / array-table
      rule(:table) { std_table | array_table }

      # ;; Standard Table

      # std-table-open  = %x5B ws     ; [ Left square bracket
      rule(:std_table_open) { str('[') >> ws }
      # std-table-close = ws %x5D     ; ] Right square bracket
      rule(:std_table_close) { ws >> str(']') }
      # table-key-sep   = ws %x2E ws  ; . Period
      rule(:table_key_sep) { ws >> str('.') >> ws }
      # std-table = std-table-open key *( table-key-sep key) std-table-close
      rule(:std_table) {
        std_table_open >>
        (
          key >> (table_key_sep >> key).repeat(0)
        ).maybe.as(NodeType::MAP) >>
        std_table_close
      }

      # ;; Array Table

      # array-table-open  = %x5B.5B ws  ; [[ Double left square bracket
      rule(:array_table_open) { str('[[') >> ws }
      # array-table-close = ws %x5D.5D  ; ]] Double right quare bracket
      rule(:array_table_close) { ws >> str(']]') }
      # array-table = array-table-open key *( table-key-sep key) array-table-close
      rule(:array_table) {
        # NB. This is tagged with the same node type as the non-array table,
        # just because the distinction isn't important in ecfg.
        array_table_open >>
        (
          key >> (table_key_sep >> key).repeat(0)
        ).repeat(0,1).as(NodeType::MAP) >>
        array_table_close
      }

      # ;; Integer

      # integer = [ minus / plus ] int
      rule(:integer) {
        ((minus | plus).maybe >> int).as(NodeType::IGNORE)
      }
      # minus = %x2D                       ; -
      rule(:minus) { str('-') }
      # plus = %x2B                        ; +
      rule(:plus) { str('+') }
      # digit1-9 = %x31-39                 ; 1-9
      rule(:digit_1_9) { match['1-9'] }
      # underscore = %x5F                  ; _
      rule(:underscore) { str('_') }
      # int = DIGIT / digit1-9 1*( DIGIT / underscore DIGIT )
      rule(:int) {
        digit |
        digit_1_9 >> (digit | underscore >> digit).repeat(1)
      }

      # ;; Float

      # float = integer ( frac / frac exp / exp )
      rule(:float) {
        (integer >> (frac | frac >> exp | exp)).as(NodeType::IGNORE)
      }
      # zero-prefixable-int = DIGIT *( DIGIT / underscore DIGIT )
      rule(:zero_prefixable_int) {
        digit >> (digit | underscore >> digit).repeat(0)
      }
      # frac = decimal-point zero-prefixable-int
      rule(:frac) { decimal_point >> zero_prefixable_int }
      # decimal-point = %x2E               ; .
      rule(:decimal_point) { str('.') }
      # exp = e integer
      rule(:exp) { e >> integer }
      # e = %x65 / %x45                    ; e E
      rule(:e) { match['eE'] }

      # ;; String

      # string = basic-string / ml-basic-string / literal-string / ml-literal-string
      rule(:string) {
        ml_basic_string |
        ml_literal_string |
        basic_string |
        literal_string
      }

      # ;; Basic String

      # basic-string = quotation-mark *basic-char quotation-mark
      rule(:basic_string) {
        (
          quotation_mark >> basic_char.repeat(0) >> quotation_mark
        ).as(NodeType::DOUBLE_QUOTED)
      }

      # quotation-mark = %x22            ; "
      rule(:quotation_mark) { str('"') }

      # basic-char = basic-unescaped / escaped
      rule(:basic_char) { basic_unescaped | escaped }
      # escaped = escape ( %x22 /          ; "    quotation mark  U+0022
      #                    %x5C /          ; \    reverse solidus U+005C
      #                    %x2F /          ; /    solidus         U+002F
      #                    %x62 /          ; b    backspace       U+0008
      #                    %x66 /          ; f    form feed       U+000C
      #                    %x6E /          ; n    line feed       U+000A
      #                    %x72 /          ; r    carriage return U+000D
      #                    %x74 /          ; t    tab             U+0009
      #                    %x75 4HEXDIG /  ; uXXXX                U+XXXX
      #                    %x55 8HEXDIG )  ; UXXXXXXXX            U+XXXXXXXX
      rule(:escaped) {
        escape >> (
          match["\x22\x5c/bfnrt"] |
          str('u') >> hexdig.repeat(4,4) |
          str('U') >> hexdig.repeat(8,8)
        )
      }

      # basic-unescaped = %x20-21 / %x23-5B / %x5D-10FFFF
      rule(:basic_unescaped) { match[" !#-\\[\\]-\u{10ffff}"] }

      # escape = %x5C                    ; \
      rule(:escape) { str('\\') }


      # ;; Multiline Basic String

      # ml-basic-string-delim = quotation-mark quotation-mark quotation-mark
      rule(:ml_basic_string_delim) { str('"""') }
      # ml-basic-string = ml-basic-string-delim ml-basic-body ml-basic-string-delim
      rule(:ml_basic_string) {
        (
          ml_basic_string_delim >> ml_basic_body >> ml_basic_string_delim
        ).as(NodeType::TOML_MULTILINE_BASIC)
      }

      # ml-basic-body = *( ml-basic-char / newline / ( escape newline ))
      rule(:ml_basic_body) {
        (
          ml_basic_string_delim.absent? >> # slight modification to make non-blind
          (ml_basic_char | newline | (escape >> newline))
        ).repeat(0)
      }

      # ml-basic-char = ml-basic-unescaped / escaped
      rule(:ml_basic_char) { ml_basic_unescaped | escaped }
      # ml-basic-unescaped = %x20-5B / %x5D-10FFFF
      rule(:ml_basic_unescaped) { match[" -\\[\\]-\u{10ffff}"] }

      # ;; Literal String

      # literal-string = apostraphe *literal-char apostraphe
      rule(:literal_string) {
        (
          apostrophe >> literal_char.repeat(0) >> apostrophe
        ).as(NodeType::SINGLE_QUOTED)
      }

      # apostraphe = %x27 ; ' Apostraphe
      rule(:apostrophe) { str("'") }

      # literal-char = %x09 / %x20-26 / %x28-10FFFF
      rule(:literal_char) { match["\t -&\(-\u{10ffff}"] }

      # ;; Multiline Literal String

      # ml-literal-string-delim = apostraphe apostraphe apostraphe
      rule(:ml_literal_string_delim) { str("'''") }
      # ml-literal-string = ml-literal-string-delim ml-literal-body ml-literal-string-delim
      rule(:ml_literal_string) {
        (
          ml_literal_string_delim >> ml_literal_body >> ml_literal_string_delim
        ).as(NodeType::TOML_MULTILINE_LITERAL)
      }

      # ml-literal-body = *( ml-literal-char / newline )
      rule(:ml_literal_body) {
        (
          ml_literal_string_delim.absent? >>
          (ml_literal_char | newline)
        ).repeat(0)
      }

      # ml-literal-char = %x09 / %x20-10FFFF
      rule(:ml_literal_char) { match["\t -\u{10ffff}"] }

      # ;; Boolean

      # boolean = true / false
      rule(:boolean) { bool_true | bool_false }
      # true    = %x74.72.75.65     ; true
      rule(:bool_true) { str('true').as(NodeType::IGNORE) }
      # false   = %x66.61.6C.73.65  ; false
      rule(:bool_false) { str('false').as(NodeType::IGNORE) }

      # ;; Datetime (as defined in RFC 3339)

      # date-fullyear  = 4DIGIT
      rule(:date_fullyear) { digit.repeat(4,4) }
      # date-month     = 2DIGIT  ; 01-12
      rule(:date_month) { digit.repeat(2,2) }
      # date-mday      = 2DIGIT  ; 01-28, 01-29, 01-30, 01-31 based on month/year
      rule(:date_mday) { digit.repeat(2,2) }
      # time-hour      = 2DIGIT  ; 00-23
      rule(:time_hour) { digit.repeat(2,2) }
      # time-minute    = 2DIGIT  ; 00-59
      rule(:time_minute) { digit.repeat(2,2) }
      # time-second    = 2DIGIT  ; 00-58, 00-59, 00-60 based on leap second rules
      rule(:time_second) { digit.repeat(2,2) }
      # time-secfrac   = "." 1*DIGIT
      rule(:time_second) { str('.') >> digit.repeat(1) }
      # time-numoffset = ( "+" / "-" ) time-hour ":" time-minute
      rule(:time_numoffset) {
        match["+\-"] >> time_hour >> str(':') >> time_minute
      }
      # time-offset    = "Z" / time-numoffset
      rule(:time_offset) { str('Z') | time_numoffset }

      # partial-time   = time-hour ":" time-minute ":" time-second [time-secfrac]
      rule(:partial_time) {
        date_fullyear >> str('-') >> date_month >> str('-') >> date_mday
      }
      # full-date      = date-fullyear "-" date-month "-" date-mday
      rule(:full_date) {
        date_fullyear >> str('-') >>
        date_month >> str('-') >>
        date_mday
      }
      # full-time      = partial-time time-offset
      rule(:full_time) { partial_time >> time_offset }

      # date-time      = full-date "T" full-time
      rule(:date_time) { full_date >> str('T') >> full_time }

      # ;; Array

      # array-open  = %x5B ws  ; [
      rule(:array_open) { str('[') }
      # array-close = ws %x5D  ; ]
      rule(:array_close) { str(']') }

      # array = array-open array-values array-close
      rule(:array) { array_open >> array_values >> array_close }

      # array-values = [ val [ array-sep ] [ ( comment newlines) / newlines ] /
      #                  val array-sep [ ( comment newlines) / newlines ] array-values ]
      rule(:array_values) {
        (
          val >> array_sep.maybe >> ((comment >> newlines) | newlines).maybe |
          val >> array_sep >> ((comment >> newlines) | newlines).maybe > array_values
        ).maybe
      }

      # array-sep = ws %x2C ws  ; , Comma
      rule(:array_sep) { ws >> str(',') >> ws }

      # ;; Inline Table

      # inline-table-open  = %x7B ws     ; {
      rule(:inline_table_open) { str('{') }
      # inline-table-close = ws %x7D     ; }
      rule(:inline_table_close) { str('}') }
      # inline-table-sep   = ws %x2C ws  ; , Comma
      rule(:inline_table_sep) { str(',') }

      # inline-table = inline-table-open inline-table-keyvals inline-table-close
      rule(:inline_table) {
        inline_table_open >> inline_table_keyvals >> inline_table_close
      }

      # inline-table-keyvals = [ inline-table-keyvals-non-empty ]
      rule(:inline_table_keyvals) { inline_table_keyvals_non_empty.maybe }
      # inline-table-keyvals-non-empty = key keyval-sep val /
      #                                  key keyval-sep val inline-table-sep inline-table-keyvals-non-empty
      rule(:inline_table_keyvals_non_empty) {
        key >> keyval_sep >> val |
        key >> keyval_sep >> val >> inline_table_sep >> inline_table_keyvals_non_empty
      }

      # Built-in ABNF terms, reproduced here for clarity
      rule(:alpha) { match['A-z'] }
      rule(:digit) { match['0-9'] }
      rule(:hexdig) { match['\h'] }
    end
  end
end
