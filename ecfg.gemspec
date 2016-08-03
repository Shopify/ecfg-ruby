# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ecfg/version'

Gem::Specification.new do |spec|
  spec.name          = "ecfg"
  spec.version       = Ecfg::VERSION
  spec.authors       = ["Burke Libbey"]
  spec.email         = ["burke.libbey@shopify.com"]

  spec.summary       = %q{stuff}
  spec.description   = %q{more stuff}
  spec.homepage      = "https://github.com/Shopify/ecfg-ruby"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler",  "~> 1.12"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "mocha",    "~> 1.1.0"

  spec.add_dependency "parslet",          "~> 1.7.1"
  spec.add_dependency "rbnacl-libsodium", "~> 1.0.10"
end
