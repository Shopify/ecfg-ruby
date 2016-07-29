require 'parslet'
require 'ecfg/parser/node_type'

module Ecfg
  module Parser
    # https://www.ietf.org/rfc/rfc4627.txt
    class JSON < Parslet::Parser
      # JSON-text = object / array
      root(:json)
      rule(:json) { object | array }

      # begin-array     = ws %x5B ws  ; [ left square bracket
      rule(:begin_array) { ws >> str('[') >> ws }
      # begin-object    = ws %x7B ws  ; { left curly bracket
      rule(:begin_object) { ws >> str('{') >> ws }
      # end-array       = ws %x5D ws  ; ] right square bracket
      rule(:end_array) { ws >> str(']') >> ws }
      # end-object      = ws %x7D ws  ; } right curly bracket
      rule(:end_object) { ws >> str('}') >> ws }
      # name-separator  = ws %x3A ws  ; : colon
      rule(:name_separator) { ws >> str(':') >> ws }
      # value-separator = ws %x2C ws  ; , comma
      rule(:value_separator) { ws >> str(',') >> ws }

      # ws = *(
      #           %x20 /              ; Space
      #           %x09 /              ; Horizontal tab
      #           %x0A /              ; Line feed or New line
      #           %x0D                ; Carriage return
      #       )
      rule(:ws) { match[" \t\n\r"].repeat(0) }

      # value = false / null / true / object / array / number / string
      rule(:value) {
        bool_false | null | bool_true | object | array | number | string
      }
      # false = %x66.61.6c.73.65   ; false
      rule(:bool_false) { str('false').as(NodeType::IGNORE) }
      # null  = %x6e.75.6c.6c      ; null
      rule(:null) { str('null').as(NodeType::IGNORE) }
      # true  = %x74.72.75.65      ; true
      rule(:bool_true) { str('true').as(NodeType::IGNORE) }

      # object = begin-object [ member *( value-separator member ) ] end-object
      rule(:object) {
        begin_object >>
        (
          member >> (value_separator >> member).repeat(0)
        ).repeat(0,1).as(NodeType::MAP) >>
        end_object
      }

      # member = string name-separator value
      rule(:member) {
        (
          string.as(NodeType::KEY) >>
          name_separator >>
          value.as(NodeType::VALUE)
        ).as(NodeType::PAIR)
      }

      # array = begin-array [ value *( value-separator value ) ] end-array
      rule(:array) {
        begin_array >>
        (
          value >> (value_separator >> value).repeat(0)
        ).repeat(0,1).as(NodeType::SEQ) >>
        end_array
      }

      # number = [ minus ] int [ frac ] [ exp ]
      rule(:number) {
        (
          minus.maybe >> int >> frac.maybe >> exp.maybe
        ).as(NodeType::IGNORE)
      }
      # decimal-point = %x2E       ; .
      rule(:decimal_point) { str('.') }
      # digit1-9 = %x31-39         ; 1-9
      rule(:digit1_9) { match['1-9'] }
      # e = %x65 / %x45            ; e E
      rule(:e) { match['eE'] }
      # exp = e [ minus / plus ] 1*DIGIT
      rule(:exp) { e >> (minus | plus).maybe >> digit.repeat(1) }
      # frac = decimal-point 1*DIGIT
      rule(:frac) { decimal_point >> digit.repeat(1) }
      # int = zero / ( digit1-9 *DIGIT )
      rule(:int) { zero | (digit1_9 >> digit.repeat(0)) }
      # minus = %x2D               ; -
      rule(:minus) { str('-') }
      # plus = %x2B                ; +
      rule(:plus) { str('+') }
      # zero = %x30                ; 0
      rule(:zero) { str('0') }

      # string = quotation-mark *char quotation-mark
      rule(:string) {
        (
          quotation_mark >>
          char.repeat(0) >>
          quotation_mark
        ).as(NodeType::DOUBLE_QUOTED)
      }

      # char = unescaped /
      #   escape (
      #       %x22 /          ; "    quotation mark  U+0022
      #       %x5C /          ; \    reverse solidus U+005C
      #       %x2F /          ; /    solidus         U+002F
      #       %x62 /          ; b    backspace       U+0008
      #       %x66 /          ; f    form feed       U+000C
      #       %x6E /          ; n    line feed       U+000A
      #       %x72 /          ; r    carriage return U+000D
      #       %x74 /          ; t    tab             U+0009
      #       %x75 4HEXDIG )  ; uXXXX                U+XXXX
      rule(:char) {
        unescaped |
        escape >> (
          match["\x22\x5c/bfnrt"] |
          str('u') >> hexdig.repeat(4,4)
        )
      }

      # escape = %x5C              ; \
      rule(:escape) { str("\x5c") }

      # quotation-mark = %x22      ; "
      rule(:quotation_mark) { str('"') }

      # unescaped = %x20-21 / %x23-5B / %x5D-10FFFF
      rule(:unescaped) { match[" !#-\\[\\]-\u{10ffff}"] }

      # ABNF builtins
      rule(:digit) { match['0-9'] }
      rule(:hexdig) { match('\h') }
    end
  end
end
