import BoundaryV2.Profile
import BoundaryV2.Wire

namespace BoundaryV2.Profile.SHA256

/- Byte-oriented SHA-256, FIPS 180-4 sections 4.1.2, 4.2.2, 5 and 6.2.
   https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf
   The function is total. The standard message domain has fewer than 2^64
   bits; the fixed-width length field truncates outside that domain.
   No collision-resistance or injectivity assertion is made. -/
abbrev Word := BitVec 32

def constants : Vector Word 64 := #[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2].toVector

def choose (x y z : Word) : Word := (x &&& y) ^^^ (~~~x &&& z)
def majority (x y z : Word) : Word := (x &&& y) ^^^ (x &&& z) ^^^ (y &&& z)
def big0 (x : Word) : Word := x.rotateRight 2 ^^^ x.rotateRight 13 ^^^ x.rotateRight 22
def big1 (x : Word) : Word := x.rotateRight 6 ^^^ x.rotateRight 11 ^^^ x.rotateRight 25
def small0 (x : Word) : Word := x.rotateRight 7 ^^^ x.rotateRight 18 ^^^ (x >>> 3)
def small1 (x : Word) : Word := x.rotateRight 17 ^^^ x.rotateRight 19 ^^^ (x >>> 10)

structure Working where
  a : Word
  b : Word
  c : Word
  d : Word
  e : Word
  f : Word
  g : Word
  h : Word
  deriving DecidableEq, Repr

def initial : Working :=
  ⟨0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19⟩

def round (work : Working) (constant word : Word) : Working :=
  let t1 := work.h + big1 work.e + choose work.e work.f work.g + constant + word
  let t2 := big0 work.a + majority work.a work.b work.c
  ⟨t1 + t2, work.a, work.b, work.c, work.d + t1, work.e, work.f, work.g⟩

def extend (first : Vector Word 16) : (count : Nat) → Vector Word (16 + count)
  | 0 => first
  | count + 1 =>
    let prior := extend first count
    let next := small1 (prior[count + 14]'(by omega)) + prior[count + 9]'(by omega) +
      small0 (prior[count + 1]'(by omega)) + prior[count]'(by omega)
    prior.push next

def words (block : Vector UInt8 64) : Vector Word 16 :=
  Vector.ofFn fun index =>
    BitVec.ofNat 32 (block[4 * index.val]'(by omega)).toNat * 0x1000000 +
    BitVec.ofNat 32 (block[4 * index.val + 1]'(by omega)).toNat * 0x10000 +
    BitVec.ofNat 32 (block[4 * index.val + 2]'(by omega)).toNat * 0x100 +
    BitVec.ofNat 32 (block[4 * index.val + 3]'(by omega)).toNat

def feedForward (left right : Working) : Working :=
  ⟨left.a + right.a, left.b + right.b, left.c + right.c, left.d + right.d,
    left.e + right.e, left.f + right.f, left.g + right.g, left.h + right.h⟩

def compress (prior : Working) (block : Vector UInt8 64) : Working :=
  let schedule := extend (words block) 48
  let final := (List.finRange 64).foldl (fun work index => round work constants[index] schedule[index]) prior
  feedForward prior final

def padding (input : Bytes) : Bytes :=
  input ++ [128] ++ List.replicate ((55 + 64 - input.length % 64) % 64) 0 ++
    (Wire.fixed 8 (input.length * 8)).reverse

def compressionStep (input : Bytes) (prior : Working) : Working :=
  compress prior (Vector.ofFn fun index => input[index.val]?.getD 0)

def iterateBlocks (step : Bytes → Working → Working) : Bytes → Nat → Working → Working
  | _, 0, prior => prior
  | input, count + 1, prior => iterateBlocks step (input.drop 64) count (step input prior)

def blocks (input : Bytes) (count : Nat) (prior : Working) : Working :=
  iterateBlocks compressionStep input count prior

theorem iterateBlocks_successor (step : Bytes → Working → Working) (input : Bytes)
    (count : Nat) (prior : Working) :
    iterateBlocks step input (count + 1) prior = iterateBlocks step (input.drop 64) count (step input prior) := rfl

theorem blocks_successor (input : Bytes) (count : Nat) (prior : Working) :
    blocks input (count + 1) prior = blocks (input.drop 64) count (compressionStep input prior) :=
  iterateBlocks_successor compressionStep input count prior

def output (work : Working) : Digest :=
  let words : Vector Word 8 := #[work.a, work.b, work.c, work.d, work.e, work.f, work.g, work.h].toVector
  Vector.ofFn fun index =>
    UInt8.ofNat ((words[index.val / 4]'(by omega)).toNat.shiftRight (8 * (3 - index.val % 4)))

def hash (input : Bytes) : Digest :=
  let padded := padding input
  output (blocks padded (padded.length / 64) initial)

theorem padding_length (input : Bytes) : (padding input).length % 64 = 0 := by
  simp only [padding, List.length_append, List.length_singleton, List.length_replicate,
    List.length_reverse, Wire.fixed_length]
  omega

theorem padding_contains_input (input : Bytes) : input <+: padding input := by
  exact ⟨[128] ++ List.replicate ((55 + 64 - input.length % 64) % 64) 0 ++
    (Wire.fixed 8 (input.length * 8)).reverse, by simp [padding, List.append_assoc]⟩

theorem padding_exact_blocks (input : Bytes) :
    64 * ((padding input).length / 64) = (padding input).length := by
  have divisible := padding_length input
  omega

/-- Every compression in a complete block stream reads 64 present bytes.
The default in the total helper is never reached by `hash`. -/
theorem complete_block_present (input : Bytes) (count : Nat)
    (complete : input.length = 64 * (count + 1)) (index : Fin 64) :
    input[index.val]?.getD 0 = input[index.val]'(by omega) := by
  simp [show index.val < input.length by omega]

theorem complete_block_tail (input : Bytes) (count : Nat)
    (complete : input.length = 64 * (count + 1)) :
    (input.drop 64).length = 64 * count := by
  simp only [List.length_drop]
  omega

theorem empty_digest : hash [] = #[
  0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14, 0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
  0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c, 0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55].toVector := by
  decide +kernel

theorem abc_digest : hash [97, 98, 99] = #[
  0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea, 0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
  0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c, 0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad].toVector := by
  decide +kernel

theorem two_block_digest :
    hash "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".toUTF8.data.toList = #[
      0x24, 0x8d, 0x6a, 0x61, 0xd2, 0x06, 0x38, 0xb8, 0xe5, 0xc0, 0x26, 0x93, 0x0c, 0x3e, 0x60, 0x39,
      0xa3, 0x3c, 0xe4, 0x59, 0x64, 0xff, 0x21, 0x67, 0xf6, 0xec, 0xed, 0xd4, 0x19, 0xdb, 0x06, 0xc1].toVector := by
  decide +kernel

end BoundaryV2.Profile.SHA256
