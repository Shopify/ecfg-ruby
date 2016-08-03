require 'base64'
require 'rbnacl/libsodium'

module Ecfg
  class Decrypter
    MESSAGE_PATTERN = /EJ\[1:(.*?):(.*?):(.*?)\]/

    InvalidMessageFormat = Class.new(StandardError)

    def to_proc
      proc { |str| decrypt(str) }
    end

    def initialize(target_private)
      # rbnacl takes keys in binary format, whereas our keys are provided to
      # the user in base16.
      @target_private = target_private     # "1234beef"
        .each_char                         # %w(1 2 3 4 b e e f)
        .each_slice(2)                     # [%w(1 2), %w(3 4), %w(b e), %w(e f)]
        .map { |a, b| "#{a}#{b}".hex.chr } # ["\x12", "\x34", "\xBE", "\xEF"]
        .join                              # "\x12\x34\xBE\xEF"

    end

    def decrypt(boxed_message)
      encrypter_public, nonce, ciphertext = load_message(boxed_message)

      box = RbNaCl::Box.new(encrypter_public, @target_private)
      box.decrypt(nonce, ciphertext)
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

    def encrypt(plaintext)
      nonce = RbNaCl::Random.random_bytes(@box.nonce_bytes)
      ciphertext = @box.encrypt(nonce, plaintext)
      format_message(@ephemeral_public, nonce, ciphertext)
    end

    def format_message(ephemeral_public, nonce, ciphertext)
      v = 1
      p = base64_encode(ephemeral_public)
      n = base64_encode(nonce)
      m = base64_encode(ciphertext)

      msg = [v, p, n, m].join(':')

      "EJ[#{msg}]"
    end

    def base64_encode(data)
      Base64.encode64(data).gsub(/\n/, '')
    end
  end
end

