import BoundaryV2.ProfileCodec

namespace BoundaryV2.Profile.Images
open Wire

inductive Family where
  | bpi | pst | pki | pko | erq | ers
  deriving DecidableEq, Repr

def Family.magic : Family → Vector UInt8 8
  | .bpi => #[65, 66, 76, 95, 66, 80, 73, 50].toVector
  | .pst => #[65, 66, 76, 95, 80, 83, 84, 50].toVector
  | .pki => #[65, 66, 76, 95, 80, 75, 73, 50].toVector
  | .pko => #[65, 66, 76, 95, 80, 75, 79, 50].toVector
  | .erq => #[65, 66, 76, 95, 69, 82, 81, 50].toVector
  | .ers => #[65, 66, 76, 95, 69, 82, 83, 50].toVector

/-- Fixed magic, version 2, zero flags, and an exact u64LE body length. -/
def frameBytes (family : Family) : Codec Bytes :=
  (Codec.pair (Codec.constant (Codec.fixedBytes 8) family.magic rfl)
    (Codec.pair (Codec.constant (Codec.unsignedFixed 2) 2 (by decide))
      (Codec.pair (Codec.constant (Codec.unsignedFixed 2) 0 (by decide))
        (Codec.sizedBytes (Codec.unsignedFixed 8))))).iso
    (fun (_, _, _, body) => body)
    (fun body => ((), (), (), body))
    (by intro body; rfl)
    (by rintro ⟨⟨⟩, ⟨⟩, ⟨⟩, body⟩; rfl)

def framed (family : Family) (codec : Codec α) : Codec α :=
  Codec.enclosed (frameBytes family) codec

def rawState : Codec Graph.State := framed .pst Codecs.rawState.toCodec
def rawInput : Codec Protocol.Input := framed .pki Codecs.rawInput.toCodec
def rawOutcome : Codec Protocol.Outcome := framed .pko Codecs.rawOutcome.toCodec
def rawRequest : Codec Protocol.Request := framed .erq Codecs.rawRequest.toCodec
def rawResult : Codec Protocol.Result := framed .ers Codecs.rawResult.toCodec

/-- The nine independently exhausted BPI2 catalogs, in their declared order. -/
def sections (program : Target.Program) : List Bytes := [
  Codecs.programRoots.encode program.roots,
  (Codecs.schema .target).list.encode program.schemas,
  (Codecs.literal .target).list.encode program.constants,
  (Codecs.effect .target).list.encode program.effects,
  Codecs.function.list.encode program.functions,
  Codecs.block.list.encode program.blocks,
  (Codecs.handler .target).list.encode program.handlers,
  Codecs.scopeCatalog.encode program.scopes,
  Codecs.constructor.list.encode program.constructors]

def sizes (program : Target.Program) : List Nat := (sections program).map List.length

def directory : List Nat → Nat → Nat → Bytes
  | [], _, _ => []
  | length :: rest, index, offset =>
    Wire.natural index ++ Wire.natural offset ++ Wire.natural length ++
      directory rest (index + 1) (offset + length)

def encodeBody (program : Target.Program) : Bytes :=
  Wire.natural 9 ++ directory (sizes program) 1 0 ++ (sections program).flatten

def encodeImage (program : Target.Program) : Bytes := (frameBytes .bpi).encode (encodeBody program)

private def readEntries : Nat → Nat → Nat → Bytes → Option (List Nat × Bytes)
  | 0, _, _, input => some ([], input)
  | count + 1, index, offset, input => do
    let (actualIndex, input) ← readNatural input
    if actualIndex != index then none else do
      let (actualOffset, input) ← readNatural input
      if actualOffset != offset then none else do
        let (length, input) ← readNatural input
        if offset + length < wordLimit then do
          let (rest, input) ← readEntries count (index + 1) (offset + length) input
          return (length :: rest, input)
        else none

private def stripDirectory (input : Bytes) : Option Bytes := do
  let (count, input) ← readNatural input
  if count != 9 then none else do
    let (sizes, content) ← readEntries 9 1 0 input
    if sizes.sum = content.length then some content else none

/-- Raw decoding checks every record field, minimal numbers, section identities,
lengths, offsets and final exhaustion. Semantic program admission is subsequent;
this function does not label an arbitrary decoded CFG executable. -/
def decodeBody (input : Bytes) : Option Target.Program := do
  let content ← stripDirectory input
  let program ← Codecs.rawProgram.toCodec.decode content
  if program.roots.profile = 1 ∧ encodeBody program = input then some program else none

def decodeImage (input : Bytes) : Option Target.Program := do
  let body ← (frameBytes .bpi).decode input
  decodeBody body

/-- The raw record predicate includes bounds on every numeric field and u32
schema tags. It is distinct from the semantic/canonical Program predicate. -/
def WireAdmitted (program : Target.Program) : Prop :=
  Codecs.rawProgram.valid program = true ∧ program.roots.profile = 1

theorem decodeBody_sound (input : Bytes) (program : Target.Program)
    (read : decodeBody input = some program) : WireAdmitted program ∧ encodeBody program = input := by
  unfold decodeBody at read
  cases directory : stripDirectory input with
  | none => simp [directory] at read
  | some body =>
    cases decoded : Codecs.rawProgram.toCodec.decode body with
    | none => simp [directory, decoded] at read
    | some value =>
      have admitted := (Codecs.rawProgram.toCodec.decode_exact body value decoded).1
      simp [directory, decoded] at read
      rcases read with ⟨valid, rfl⟩
      exact ⟨⟨admitted, valid.1⟩, valid.2⟩

theorem decodeImage_sound (input : Bytes) (program : Target.Program)
    (read : decodeImage input = some program) : WireAdmitted program ∧ encodeImage program = input := by
  unfold decodeImage at read
  cases header : (frameBytes .bpi).decode input with
  | none => simp [header] at read
  | some body =>
    have framed := (frameBytes .bpi).decode_exact input body header
    have parsed : decodeBody body = some program := by simpa [header] using read
    have decoded := decodeBody_sound body program parsed
    exact ⟨decoded.1, by simpa [encodeImage, decoded.2] using framed.2⟩

theorem sections_are_raw_record (program : Target.Program) :
    (sections program).flatten = Codecs.rawProgram.encode program := by
  change _ = Codecs.programRoots.encode program.roots ++
    ((Codecs.schema .target).list.encode program.schemas ++
    ((Codecs.literal .target).list.encode program.constants ++
    ((Codecs.effect .target).list.encode program.effects ++
    (Codecs.function.list.encode program.functions ++
    (Codecs.block.list.encode program.blocks ++
    ((Codecs.handler .target).list.encode program.handlers ++
    (Codecs.scopeCatalog.encode program.scopes ++ Codecs.constructor.list.encode program.constructors)))))))
  simp [sections]

private theorem entries_roundtrip (lengths : List Nat) (index offset : Nat) (rest : Bytes)
    (indices : index + lengths.length < wordLimit) (capacity : offset + lengths.sum < wordLimit) :
    readEntries lengths.length index offset (directory lengths index offset ++ rest) = some (lengths, rest) := by
  induction lengths generalizing index offset with
  | nil => rfl
  | cons length lengths ih =>
    have indexBound : index < wordLimit := by simp only [List.length_cons] at indices; omega
    have offsetBound : offset < wordLimit := by omega
    have lengthBound : length < wordLimit := by simp only [List.sum_cons] at capacity; omega
    have nextBound : offset + length < wordLimit := by simp only [List.sum_cons] at capacity; omega
    have restCapacity : offset + length + lengths.sum < wordLimit := by
      simpa [List.sum_cons, Nat.add_assoc] using capacity
    have restIndices : index + 1 + lengths.length < wordLimit := by
      simpa [List.length_cons, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using indices
    simp [directory, readEntries, List.append_assoc, readNatural_complete _ _ indexBound,
      readNatural_complete _ _ offsetBound, readNatural_complete _ _ lengthBound, nextBound,
      ih (index + 1) (offset + length) restIndices restCapacity]

theorem decodeBody_complete (program : Target.Program) (admitted : WireAdmitted program)
    (capacity : (sections program).flatten.length < wordLimit) :
    decodeBody (encodeBody program) = some program := by
  have count : (sizes program).length = 9 := by simp [sizes, sections]
  have total : (sizes program).sum = (sections program).flatten.length := by simp [sizes, List.length_flatten]
  have directoryRead := entries_roundtrip (sizes program) 1 0 ((sections program).flatten)
    (by simp [count, wordLimit]) (by simpa [total] using capacity)
  have rootRead : readNatural (encodeBody program) =
      some (9, directory (sizes program) 1 0 ++ (sections program).flatten) := by
    simpa only [encodeBody, List.append_assoc] using readNatural_complete 9
      (directory (sizes program) 1 0 ++ (sections program).flatten) (by decide)
  have content : stripDirectory (encodeBody program) = some ((sections program).flatten) := by
    simp [stripDirectory, rootRead, ← count, directoryRead, total]
  have decoded := Codecs.rawProgram.toCodec.decode_encode program admitted.1
  rw [← sections_are_raw_record] at decoded
  simp [decodeBody, content, decoded, admitted.2]


theorem frameBytes_valid (family : Family) (bytes : Bytes) :
    (frameBytes family).valid bytes = decide (bytes.length < wordLimit) := by
  change (true && (true && (true && (decide (bytes.length < 256 ^ 8) && true)))) =
    decide (bytes.length < wordLimit)
  simp only [Bool.true_and, Bool.and_true]
  rfl

theorem decodeImage_complete (program : Target.Program) (admitted : WireAdmitted program)
    (capacity : (encodeBody program).length < wordLimit) :
    decodeImage (encodeImage program) = some program := by
  have size : (sections program).flatten.length ≤ (encodeBody program).length := by
    simp only [encodeBody, List.length_append]
    omega
  have body := decodeBody_complete program admitted (Nat.lt_of_le_of_lt size capacity)
  have framedValid : (frameBytes .bpi).valid (encodeBody program) = true := by
    simp [frameBytes_valid, capacity]
  have header := (frameBytes .bpi).decode_encode (encodeBody program) framedValid
  simp [decodeImage, encodeImage, header, body]

theorem nonminimal_natural_rejected : Wire.Codec.natural.decode [128, 0] = none := by decide +kernel

theorem overflowing_natural_rejected :
    Wire.Codec.natural.decode [255, 255, 255, 255, 255, 255, 255, 255, 255, 2] = none := by decide +kernel

theorem maximum_natural_decoded_exactly :
    Wire.Codec.natural.decode [255, 255, 255, 255, 255, 255, 255, 255, 255, 1] =
      some 18446744073709551615 := by decide +kernel

theorem boolean_extra_byte_rejected : Wire.Codec.boolean.decode [1, 0] = none := by decide +kernel

theorem empty_enumeration_has_no_wire_tag :
    (Wire.Codec.enumeration ([] : List Empty) (by intro value; cases value) (by decide) (by decide)).decode [0] = none := by decide +kernel

end BoundaryV2.Profile.Images
