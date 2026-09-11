import BoundaryV2.SHA256Certificate

namespace BoundaryV2.Profile.SHA256.Examples

set_option maxRecDepth 4096
set_option maxHeartbeats 0

private def abcFinal : Working :=
  ⟨0xba7816bf, 0x8f01cfea, 0x414140de, 0x5dae2223,
   0xb00361a3, 0x96177a9c, 0xb410ff61, 0xf20015ad⟩

theorem valid_compression_witness :
    checkHash [97, 98, 99] [abcFinal] (output abcFinal) = true := by decide +kernel

theorem changed_message_rejected :
    checkHash [97, 98, 100] [abcFinal] (output abcFinal) = false := by decide +kernel

theorem omitted_compression_rejected :
    checkHash [97, 98, 99] [] (output abcFinal) = false := by decide +kernel

theorem extra_compression_rejected :
    checkHash [97, 98, 99] [abcFinal, abcFinal] (output abcFinal) = false := by decide +kernel

theorem changed_intermediate_rejected :
    checkHash [97, 98, 99] [{ abcFinal with a := 0 }] (output abcFinal) = false := by decide +kernel

theorem changed_digest_rejected :
    checkHash [97, 98, 99] [abcFinal] (output { abcFinal with a := 0 }) = false := by decide +kernel

theorem truncated_block_rejected :
    checkBlocks ((padding [97, 98, 99]).take 63) initial [abcFinal] = none := by decide +kernel

theorem trailing_byte_rejected :
    checkBlocks (padding [97, 98, 99] ++ [0]) initial [abcFinal] = none := by decide +kernel

end BoundaryV2.Profile.SHA256.Examples
