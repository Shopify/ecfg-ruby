require 'test_helper'

module Ecfg
  module Parser
    class YAMLTest < MiniTest::Test
      include Helpers::AST

      def test_asdf
        input = <<~EOF
          ---
          a: b
          c: 'd'
          e: |
            asdf
          f: >
            zxcv
        EOF
        exp = {
          map: [
            {
              pair: {
                key: {plain_scalar: 'a@4'},
                value: {plain_scalar: 'b@7'}
              }
            },
            {
              pair: {
                key: {plain_scalar: 'c@9'},
                value: {single_quoted: 'd@13'}
              }
            },
            {
              pair: {
                key: {plain_scalar: 'e@16'},
                value: {
                  block_literal: "|\n  asdf\n@19"
                }
              }
            },
            {
              pair: {
                key: {plain_scalar: 'f@28'},
                value: {
                  block_folded: ">\n  zxcv\n@31"
                }
              }
            }
          ]
        }
        assert_ast(exp, input)
      end

      private

      def parser
        Ecfg::Parser::YAML.new
      end
    end
  end
end
