import BoundaryV2.SHA256

namespace BoundaryV2.Profile.SHA256

/-- Proof evaluation can represent a byte as a numeral or as its bit-vector
constructor. Natural-number keys give both forms the same checked lookup. -/
def hashNumerals (input : List Nat) : Digest := hash (input.map UInt8.ofNat)

theorem hash_as_numerals (input : Bytes) : hash input = hashNumerals (input.map UInt8.toNat) := by
  have roundtrip : (input.map UInt8.toNat).map UInt8.ofNat = input := by
    simp [List.map_map, Function.comp_def]
  exact (congrArg hash roundtrip).symm

private def checkTransitions (step : Bytes → Working → Working) (input : Bytes) (prior : Working) :
    List Working → Option Working
  | [] => if input.isEmpty then some prior else none
  | next :: rest =>
    if input.length < 64 then none
    else if step input prior = next then checkTransitions step (input.drop 64) next rest
    else none

private theorem transitions_sound (step : Bytes → Working → Working) (input : Bytes)
    (prior final : Working) (witness : List Working)
    (accepted : checkTransitions step input prior witness = some final) :
    input.length = 64 * witness.length ∧ iterateBlocks step input witness.length prior = final := by
  induction witness generalizing input prior with
  | nil =>
    change (if input.isEmpty then some prior else none) = some final at accepted
    split at accepted
    · rename_i empty
      have empty : input = [] := by simpa using empty
      cases accepted
      exact ⟨by simp [empty], rfl⟩
    · cases accepted
  | cons next rest ih =>
    change (if input.length < 64 then none else if step input prior = next then
      checkTransitions step (input.drop 64) next rest else none) = some final at accepted
    split at accepted
    · cases accepted
    · rename_i enough
      split at accepted
      · rename_i computed
        have remaining := ih (input.drop 64) next accepted
        have enough : 64 ≤ input.length := Nat.le_of_not_lt enough
        have tailLength : input.length - 64 = 64 * rest.length := by
          simpa only [List.length_drop] using remaining.1
        refine ⟨?_, ?_⟩
        · change input.length = 64 * (rest.length + 1)
          calc
            input.length = (input.length - 64) + 64 := (Nat.sub_add_cancel enough).symm
            _ = 64 * rest.length + 64 := congrArg (· + 64) tailLength
            _ = 64 * (rest.length + 1) := (Nat.mul_succ 64 rest.length).symm
        · change iterateBlocks step (input.drop 64) rest.length (step input prior) = final
          exact (congrArg (iterateBlocks step (input.drop 64) rest.length) computed).trans remaining.2
      · cases accepted

/-- Each intermediate compression value is untrusted finite data. Its literal
predecessor prevents repeated expansion of preceding compressions during kernel
checking. The checker verifies every block and the exact exhaustion of bytes. -/
def checkBlocks (input : Bytes) (prior : Working) (witness : List Working) : Option Working :=
  checkTransitions compressionStep input prior witness

theorem checkBlocks_sound (input : Bytes) (prior final : Working) (witness : List Working)
    (accepted : checkBlocks input prior witness = some final) :
    input.length = 64 * witness.length ∧ blocks input witness.length prior = final := by
  exact transitions_sound compressionStep input prior final witness accepted

def checkHash (input : Bytes) (witness : List Working) (expected : Digest) : Bool :=
  (checkBlocks (padding input) initial witness).any (fun final => output final == expected)

theorem checkHash_sound (input : Bytes) (witness : List Working) (expected : Digest)
    (accepted : checkHash input witness expected = true) : hash input = expected := by
  unfold checkHash at accepted
  cases checked : checkBlocks (padding input) initial witness with
  | none => simp [checked] at accepted
  | some final =>
    have exact := checkBlocks_sound _ _ _ _ checked
    have count : (padding input).length / 64 = witness.length := by rw [exact.1]; omega
    have result : output final = expected := by simpa [checked] using accepted
    simpa only [hash, count, exact.2] using result

theorem compressionStep_append (block tail : Bytes) (prior : Working)
    (complete : block.length = 64) :
    compressionStep (block ++ tail) prior = compressionStep block prior := by
  unfold compressionStep
  apply congrArg (compress prior)
  ext index bound
  simp only [Vector.getElem_ofFn]
  rw [List.getElem?_append_left (by omega)]

/-- Each node checks one complete compression block. The tail proof may be a
separately compiled theorem, so kernel checking need not retain the reduction
of the entire hash computation in one declaration. -/
inductive BlockDerivation : Bytes → Working → Working → Prop where
  | done (work : Working) : BlockDerivation [] work work
  | step (block tail : Bytes) (prior next final : Working)
      (complete : block.length = 64)
      (computed : compressionStep block prior = next)
      (rest : BlockDerivation tail next final) :
      BlockDerivation (block ++ tail) prior final

theorem BlockDerivation.sound (accepted : BlockDerivation input prior final) :
    ∃ count, input.length = 64 * count ∧ blocks input count prior = final := by
  induction accepted with
  | done work => exact ⟨0, rfl, rfl⟩
  | step block tail prior next final complete computed rest ih =>
    obtain ⟨count, length, result⟩ := ih
    refine ⟨count + 1, ?_, ?_⟩
    · simp only [List.length_append, complete, length]
      omega
    · rw [blocks_successor, compressionStep_append block tail prior complete, computed]
      have dropped : (block ++ tail).drop 64 = tail := by
        rw [← complete, List.drop_left]
      rw [dropped]
      exact result

theorem hash_of_block_derivation (input padded : Bytes) (final : Working)
    (exactPadding : padding input = padded)
    (accepted : BlockDerivation padded initial final) : hash input = output final := by
  obtain ⟨count, length, result⟩ := accepted.sound
  change output (blocks (padding input) ((padding input).length / 64) initial) = output final
  have countExact : padded.length / 64 = count := by rw [length]; omega
  rw [exactPadding, countExact, result]

end BoundaryV2.Profile.SHA256
