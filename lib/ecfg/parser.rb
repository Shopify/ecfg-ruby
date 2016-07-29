module Ecfg
  module Parser
    autoload(:JSON, 'ecfg/parser/json')
    autoload(:TOML, 'ecfg/parser/toml')
    autoload(:YAML, 'ecfg/parser/yaml')

    autoload(:NodeType, 'ecfg/parser/node_type')
  end
end
