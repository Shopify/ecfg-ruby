require 'ecfg'

# TODO:
# * folded literals aren't folded properly
# * the rest of the API

input = <<~'EOF'
  ---
  a: |
    asdf
    zzxcv

  # asdf
  h: [3, "zxcv", !!str "asdf", null]
  # Just like with ejson, underscore prefix prevents encryption.
  _b: !!str c
  g: true
  c:
    - a
    # double vs. single quoted strings are interpreted correctly.
    - "asdf\tzxcv"
    - 'asdf\tzxcv'
    - b
    - c
  d:
EOF

encrypter   = Ecfg::Encrypter.new("6ea8ba92a66f795c17f9ba4dd3d3f445c1e4b9c34728b17aea370479eff1246d")
parser      = Ecfg::Parser::YAML.new
transformer = Ecfg::Transformer.new

out = transformer.transform(input, parser, &encrypter)

decrypter   = Ecfg::Decrypter.new("b07b4ff938bd5abed0dea6fa717b4942c4782a9ba71264468fce5094a1e0c397")
parser      = Ecfg::Parser::YAML.new
transformer = Ecfg::Transformer.new

re_out = transformer.transform(out, parser, &decrypter)

puts re_out

# Looks like:
=begin
---
a: "EJ[1:lr1+EQM9Uif9qxar7qu+RVvkIxt65gl7RFfFi3EYVmk=:cMBLAZXrAo0UXHnFHe5dYMfFkGHr9Rne:TYkaLYGOytRNvgWEaSuz7t079oE4DPtNXoH1]"
# asdf
h: [3, "EJ[1:lr1+EQM9Uif9qxar7qu+RVvkIxt65gl7RFfFi3EYVmk=:VVznE/DMszclj1b+w3XCpFl1PqGB2RfF:w+ALQj4OdwoqFAoWKTvxnKBTBRY=]", !!str "EJ[1:lr1+EQM9Uif9qxar7qu+RVvkIxt65gl7RFfFi3EYVmk=:chcOxndBdTXx+kH4Xl5re8Utq4iBrJGg:qlfkrvTopVRlZrntB+l5mDZuZnQ=]", null]
# Just like with ejson, underscore prefix prevents encryption.
_b: !!str c
g: true
c:
  - "EJ[1:lr1+EQM9Uif9qxar7qu+RVvkIxt65gl7RFfFi3EYVmk=:b97yZhxLYb+VNPaLxTvJaVEjcQpHU6QK:iYpG1QF/ZMOvJKDj2muLLpI=]"
  # double vs. single quoted strings are interpreted correctly.
  - "EJ[1:lr1+EQM9Uif9qxar7qu+RVvkIxt65gl7RFfFi3EYVmk=:vk54WmRD0FO6lF+xyXZ1IBTZP29JyV05:uIlmLS+Z679lIZbZDhVTXRL/Po38UhQV7A==]"
  - "EJ[1:lr1+EQM9Uif9qxar7qu+RVvkIxt65gl7RFfFi3EYVmk=:fctacjUjqyPwI3REy/mnmoq7RxpmwPeI:zahSzjYEPO9meGlKMKOtff0xo6Xu/lZE2kI=]"
  - "EJ[1:lr1+EQM9Uif9qxar7qu+RVvkIxt65gl7RFfFi3EYVmk=:XX2rLkgG7CBrR30R8dvTUL/QiANxRtvV:6S05JtqREq6bb52hgFngiGQ=]"
  - "EJ[1:lr1+EQM9Uif9qxar7qu+RVvkIxt65gl7RFfFi3EYVmk=:MnEijpO2amuODIVZmBIaAYDJoktZoy3a:11kEwZ/bHrS3rzJSCFwkAX0=]"
d:
=end
