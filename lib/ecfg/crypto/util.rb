require 'rbnacl/libsodium'

module Ecfg
  module Crypto
    module Util
      def self.base16_to_raw(hex)
        # rbnacl takes keys in binary format, whereas our keys are generally
        # presented to the user in base16.
        hex                                  # "1234beef"
          .each_char                         # %w(1 2 3 4 b e e f)
          .each_slice(2)                     # [%w(1 2), %w(3 4), %w(b e), %w(e f)]
          .map { |a, b| "#{a}#{b}".hex.chr } # ["\x12", "\x34", "\xBE", "\xEF"]
          .join                              # "\x12\x34\xBE\xEF"
      end

      def self.raw_to_base16(raw)
        raw                       # "\x12\x34\xBE\xEF"
          .bytes                  # [18, 52, 190, 239]
          .map { |b| b.to_s(16) } # ["12", "34", "be", "ef"]
          .join                   # "1234beef"
      end
    end
  end
end
