require 'test_helper'

module Ecfg
  module Parser
    class JSONTest < MiniTest::Test
      include Helpers::AST

      def test_asdf
        input = '{"a": "b"}'
        exp = {
          map: [
            {
              pair: {
                key: {double_quoted: '"a"@1'},
                value: {double_quoted: '"b"@6'}
              }
            }
          ]
        }
        assert_ast(exp, input)
      end

      private

      def parser
        Ecfg::Parser::JSON.new
      end
    end
  end
end
