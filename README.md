# Ecfg for Ruby *(WIP)*

This is an alternate implementation of the [`ecfg(5)`
spec](https://shopify.github.io/ecfg/ecfg.5.html)

**Don't use this yet.**

## 10-second demo:

```ruby
input = <<~'EOF'
  ---
  yaml: |
    stuff
    words

  # asdf
  h: [3, "yaml", !!str "so many features", null]

  # Just like with ejson, underscore prefix prevents encryption.
  _b: !!str c
  c:
    - 42
    - "a\tb"
    - 'a\tb'
    - true
    - c
  d:
EOF

encrypter   = Ecfg::Crypto::Encrypter.new("6ea8ba92a66f795c17f9ba4dd3d3f445c1e4b9c34728b17aea370479eff1246d")
parser      = Ecfg::Parser::YAML.new # or TOML, or JSON
transformer = Ecfg::Transformer.new

puts transformer.transform(input, parser, &encrypter)
```

String values are encrypted, preserving structure and comments.

```yaml
---
yaml: "EJ[1:QvMd4gferRRmyEvb81SI+i9QojuzqPnabxKu3g1eP00=:GLxcXxX/+c4IP76pq2+LnTBwIxmg9JLT:aWhsKYAFVMciiCZg3T2f/3NmbkyCBXX4IJkFCQ==]"
# asdf
h: [3, "EJ[1:QvMd4gferRRmyEvb81SI+i9QojuzqPnabxKu3g1eP00=:UKq1jKUUnMPE7/mcCwtAC/XKPszetqrG:U0QVfiE8IeCBx7bpkKuYyADyfi4=]", !!str "EJ[1:QvMd4gferRRmyEvb81SI+i9QojuzqPnabxKu3g1eP00=:m0amlXrx7Mv9p0CpRdTpv4CDNDvXyd5u:pIa0ql6FeM1ZhadSymShUKHuT/UXVwntusnuTE2G5lo=]", null]

# Just like with ejson, underscore prefix prevents encryption.
_b: !!str c
c:
  - 42
  - "EJ[1:QvMd4gferRRmyEvb81SI+i9QojuzqPnabxKu3g1eP00=:GlsopadN+GBnmiXOT9Gc4j44um+U1rbx:j69WBIobHzQKuyl7z5rlyrso5A==]"
  - "EJ[1:QvMd4gferRRmyEvb81SI+i9QojuzqPnabxKu3g1eP00=:XjytZAoIXqKNooj6P9FvMxGGH7egFYI4:06+JyXE5GTShdD78IHYGf2SsLfw=]"
  - true
  - "EJ[1:QvMd4gferRRmyEvb81SI+i9QojuzqPnabxKu3g1eP00=:Vd95Z4h//lkYZgVahe3MKUjb+A2ThEWw:m9dRCWKrXNTSypLLF/NqWkA=]"
d:

```
