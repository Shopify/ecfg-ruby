require 'base64'
require 'rbnacl/libsodium'
require 'ecfg/crypto/util'

module Ecfg
  module Crypto
    class Encrypter
      def to_proc
        proc { |str| encrypt(str) }
      end

      def initialize(peer_public_hex)
        peer_public_raw = Crypto::Util.base16_to_raw(peer_public_hex)

        ephemeral_private_raw = RbNaCl::PrivateKey.generate
        @ephemeral_public_raw = ephemeral_private_raw.public_key

        @box = RbNaCl::Box.new(peer_public_raw, ephemeral_private_raw)
      end

      def encrypt(plaintext)
        nonce_raw = RbNaCl::Random.random_bytes(@box.nonce_bytes)
        ciphertext_raw = @box.encrypt(nonce_raw, plaintext)
        format_message(@ephemeral_public_raw, nonce_raw, ciphertext_raw)
      end

      private

      def format_message(ephemeral_public_raw, nonce_raw, ciphertext_raw)
        v = 1
        p = base64_encode(ephemeral_public_raw)
        n = base64_encode(nonce_raw)
        m = base64_encode(ciphertext_raw)

        msg = [v, p, n, m].join(':')

        "EJ[#{msg}]"
      end

      def base64_encode(data_raw)
        Base64.encode64(data_raw).gsub(/\n/, '')
      end
    end
  end
end
