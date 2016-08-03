require 'ecfg/crypto/encrypter'
require 'ecfg/crypto/decrypter'
require 'ecfg/crypto/util'

module Ecfg
  module Crypto
    # generate_keypair returns a hex-encoded keypair as (public, private)
    def self.generate_keypair
      private_obj = RbNaCl::PrivateKey.generate
      public_obj   = private_raw.public_key

      public_hex  = Crypto::Util.raw_to_base16(public_obj.to_bytes)
      private_hex = Crypto::Util.raw_to_base16(private_obj.to_bytes)

      [public_hex, private_hex]
    end
  end
end
