import BoundaryV2.SHA256Certificate
import Lean.Elab.Tactic.Cbv

open BoundaryV2.Profile
set_option cbv.warning false
set_option maxRecDepth 8192
-- Matcher reduction must not unfold the original compressor before the
-- numeric-key theorem can replace it with its kernel-checked digest.
attribute [cbv_opaque] SHA256.hashNumerals SHA256.hash
attribute [cbv_eval] SHA256.hash_as_numerals

private def digest : Digest := #[
  0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea, 0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
  0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c, 0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad].toVector

@[cbv_eval] private theorem known : SHA256.hashNumerals [97, 98, 99] = digest := SHA256.abc_digest

example : SHA256.hash [97, 98, 99] = digest := by decide_cbv

-- Computed UInt8 constructors and authored byte numerals must share the same
-- proved hash fact. Hash evaluation is opaque, so a cache miss cannot pass.
example : SHA256.hash (Wire.fixed 3 (97 + 256 * 98 + 65536 * 99)) = digest := by decide_cbv
