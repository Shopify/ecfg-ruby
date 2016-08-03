require 'base64'
require 'rbnacl/libsodium'
require 'ecfg/crypto/util'

module Ecfg
  module Crypto
    class Decrypter
      MESSAGE_PATTERN = /EJ\[1:(.*?):(.*?):(.*?)\]/

      InvalidMessageFormat = Class.new(StandardError)

      def to_proc
        proc { |str| decrypt(str) }
      end

      def initialize(target_private_hex)
        @target_private_raw = Crypto::Util.base16_to_raw(target_private_hex)
      end

      def decrypt(boxed_message)
        encrypter_public_raw, nonce_raw, ciphertext_raw = load_message(boxed_message)

        box = RbNaCl::Box.new(encrypter_public_raw, @target_private_raw)
        box.decrypt(nonce_raw, ciphertext_raw)
      end

      def load_message(boxed_message)
        md = boxed_message.match(MESSAGE_PATTERN)
        unless md
          raise InvalidMessageFormat, "message has invalid format: #{boxed_message}"
        end
        [
          Base64.decode64(md[1]),
          Base64.decode64(md[2]),
          Base64.decode64(md[3])
        ]
      end
    end
  end
end
