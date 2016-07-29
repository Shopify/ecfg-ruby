require 'test_helper'

module Ecfg
  module Parser
    class TOMLTest < MiniTest::Test
      include Helpers::AST

      def test_asdf
        input = <<~EOF
          [asdf]
          a = "b"
          c = 3
          d = """
          asdf
          """
          t = false
        EOF
        exp = [
          {map: {unquoted_string: "asdf@1"}},
          {
            pair: {
              key: {unquoted_string: "a@7"},
              value: {double_quoted: '"b"@11'}
            },
          },
          {
            pair: {
              key: {unquoted_string: "c@15"},
              value: {ignore: "3@19"}
            }
          },
          {
            pair: {
              key: {unquoted_string: "d@21"},
              value: {toml_multiline_basic: "\"\"\"\nasdf\n\"\"\"@25"}
            }
          },
          {
            pair: {
              key: {unquoted_string: "t@38"},
              value: {ignore: 'false@42'}
            }
          }
        ]
        assert_ast(exp, input)
      end

      private

      def parser
        Ecfg::Parser::TOML.new
      end
    end
  end
end
