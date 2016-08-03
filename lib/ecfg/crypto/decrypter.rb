require 'base64'
require 'rbnacl/libsodium'
require 'ecfg/crypto/util'

module Ecfg
  module Crypto
    class Decrypter
      MESSAGE_PATTERN = /EJ\[1:(.*?):(.*?):(.*?)\]/

      # Indicates the message we tried to decrypt was not a valid encrypted
      # message.  Note that this can happen if there are secrets that have not
      # yet been encrypted.  This case is intended, as that may indicate
      # plaintext secrets were committed to source control, and the situation
      # warrants some attention.
      InvalidMessageFormat = Class.new(StandardError)

      # Ecfg::Crypto::Decrypter is initialized with the private key to be used
      # for decryption. In normal operation, we look up the public key from the
      # ecfg file we're about to decrypt, then search for the corresponding
      # private key, which is then passed in here.
      def initialize(target_private_hex)
        @target_private_raw = Crypto::Util.base16_to_raw(target_private_hex)
      end

      # decrypt a message, presumably encrypted to the private key we
      # initialized with, which must be in the "EJ[1:...]" format. Returns the
      # plaintext as a string.
      def decrypt(boxed_message)
        encrypter_public_raw, nonce_raw, ciphertext_raw = load_message(boxed_message)

        box = RbNaCl::Box.new(encrypter_public_raw, @target_private_raw)
        box.decrypt(nonce_raw, ciphertext_raw)
      end

      # cast to a block/proc (e.g. Transformer.transform(..., &encrypter))
      def to_proc
        proc { |str| decrypt(str) }
      end

      private

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
