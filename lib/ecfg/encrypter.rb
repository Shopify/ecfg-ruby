require 'base64'
require 'rbnacl/libsodium'

module Ecfg
  class Encrypter
    def to_proc
      proc { |str| encrypt(str) }
    end

    def encrypt(str)
      "ENC[#{str}]"
    end

    def initialize(peer_public)
      # rbnacl takes keys in binary format, whereas our keys are embedded in
      # ecfg files in base16.
      peer_public = peer_public           # "1234beef"
        .each_char                         # %w(1 2 3 4 b e e f)
        .each_slice(2)                     # [%w(1 2), %w(3 4), %w(b e), %w(e f)]
        .map { |a, b| "#{a}#{b}".hex.chr } # ["\x12", "\x34", "\xBE", "\xEF"]
        .join                              # "\x12\x34\xBE\xEF"

      ephemeral_private = RbNaCl::PrivateKey.generate
      @ephemeral_public  = ephemeral_private.public_key

      @box = RbNaCl::Box.new(peer_public, ephemeral_private)
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

