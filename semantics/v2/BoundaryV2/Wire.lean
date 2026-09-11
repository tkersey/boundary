import BoundaryV2.Profile

namespace BoundaryV2.Profile.Wire

/-- Minimal unsigned base-128 encoding. Word validity is checked separately. -/
def natural (value : Nat) : Bytes :=
  if value < 128 then [UInt8.ofNat value]
  else UInt8.ofNat (value % 128 + 128) :: natural (value / 128)
termination_by value
decreasing_by omega

/-- This bound is the wire format's ten-byte u64 bound, not machine execution
fuel. The parser retains the exact consumed prefix for canonicality checking. -/
def rawNatural : Nat → Bytes → Option (Nat × Bytes × Bytes)
  | 0, _ => none
  | _ + 1, [] => none
  | remaining + 1, byte :: rest =>
    if byte.toNat < 128 then some (byte.toNat, [byte], rest)
    else do
      let (value, encoded, suffix) ← rawNatural remaining rest
      return (byte.toNat % 128 + 128 * value, byte :: encoded, suffix)

def readNatural (bytes : Bytes) : Option (Nat × Bytes) := do
  let (value, encoded, rest) ← rawNatural 10 bytes
  if value < wordLimit ∧ natural value = encoded then some (value, rest) else none

private theorem byte_toNat (n : Nat) (bound : n < 256) : (UInt8.ofNat n).toNat = n := by
  simp [Nat.mod_eq_of_lt bound]

private theorem rawNatural_exact (fuel : Nat) (input : Bytes) (value : Nat) (encoded rest : Bytes)
    (read : rawNatural fuel input = some (value, encoded, rest)) : encoded ++ rest = input := by
  induction fuel generalizing input value encoded rest with
  | zero => simp [rawNatural] at read
  | succ fuel ih =>
    cases input with
    | nil => simp [rawNatural] at read
    | cons byte tail =>
      simp only [rawNatural] at read
      split at read
      · cases read; rfl
      · cases next : rawNatural fuel tail with
        | none => simp [next] at read
        | some parsed =>
          rcases parsed with ⟨number, consumed, suffix⟩
          simp [next] at read
          rcases read with ⟨rfl, rfl, rfl⟩
          simpa using congrArg (List.cons byte) (ih tail number consumed suffix next)

private theorem rawNatural_complete (fuel : Nat) (value : Nat) (suffix : Bytes)
    (positive : 0 < fuel) (bounded : value < 128 ^ fuel) :
    rawNatural fuel (natural value ++ suffix) = some (value, natural value, suffix) := by
  induction fuel generalizing value with
  | zero => omega
  | succ fuel ih =>
    by_cases small : value < 128
    · have byte := byte_toNat value (by omega)
      simp [natural, small, rawNatural, byte]
    · have byte := byte_toNat (value % 128 + 128) (by omega)
      have tailFuel : 0 < fuel := by
        cases fuel with
        | zero => simp at bounded; omega
        | succ => omega
      have tailBound : value / 128 < 128 ^ fuel := by
        apply (Nat.div_lt_iff_lt_mul (by decide : 0 < 128)).mpr
        simpa [Nat.pow_succ, Nat.mul_comm] using bounded
      have tail := ih (value / 128) tailFuel tailBound
      rw [natural, if_neg small]
      simp only [List.cons_append, rawNatural, byte]
      rw [if_neg (by omega), tail]
      dsimp
      have number : (value % 128 + 128) % 128 + 128 * (value / 128) = value := by omega
      rw [number]

/-- Accepted naturals have their unique minimal prefix and retain all following
bytes for the next field. There is no accepted overflow or redundant digit. -/
theorem readNatural_sound (input rest : Bytes) (value : Nat)
    (read : readNatural input = some (value, rest)) :
    value < wordLimit ∧ natural value ++ rest = input := by
  unfold readNatural at read
  cases raw : rawNatural 10 input with
  | none => simp [raw] at read
  | some parsed =>
    rcases parsed with ⟨number, consumed, suffix⟩
    simp only [raw] at read
    change (if number < wordLimit ∧ natural number = consumed then some (number, suffix) else none) = some (value, rest) at read
    split at read
    · rename_i valid
      have exactRaw := rawNatural_exact 10 input number consumed suffix raw
      cases read
      exact ⟨valid.1, valid.2 ▸ exactRaw⟩
    · cases read

theorem readNatural_complete (value : Nat) (suffix : Bytes) (valid : value < wordLimit) :
    readNatural (natural value ++ suffix) = some (value, suffix) := by
  have bound : value < 128 ^ 10 := by
    have limit : wordLimit ≤ 128 ^ 10 := by decide
    omega
  simp [readNatural, rawNatural_complete 10 value suffix (by decide) bound, valid]

theorem natural_nonempty (value : Nat) : 0 < (natural value).length := by
  rw [natural]
  split <;> simp

/-- Fixed-width little endian. It intentionally exposes truncation only in the
raw encoder; its decoding and scalar contracts establish representability. -/
def fixed : Nat → Nat → Bytes
  | 0, _ => []
  | width + 1, value => UInt8.ofNat (value % 256) :: fixed width (value / 256)

def unsigned : Bytes → Nat
  | [] => 0
  | byte :: rest => byte.toNat + 256 * unsigned rest

theorem fixed_length (width value : Nat) : (fixed width value).length = width := by
  induction width generalizing value with
  | zero => rfl
  | succ width ih => simp [fixed, ih]

theorem unsigned_fixed (width value : Nat) (bound : value < 256 ^ width) :
    unsigned (fixed width value) = value := by
  induction width generalizing value with
  | zero => simp at bound; simp [fixed, unsigned, bound]
  | succ width ih =>
    have low := byte_toNat (value % 256) (by omega)
    have high : value / 256 < 256 ^ width := by
      apply (Nat.div_lt_iff_lt_mul (by decide : 0 < 256)).mpr
      simpa [Nat.pow_succ, Nat.mul_comm] using bound
    simp only [fixed, unsigned, low, ih _ high]
    omega

theorem unsigned_bound (bytes : Bytes) : unsigned bytes < 256 ^ bytes.length := by
  induction bytes with
  | nil => simp [unsigned]
  | cons byte rest ih =>
    have low := byte.toNat_lt
    simp only [unsigned, List.length_cons, Nat.pow_succ]
    omega

theorem fixed_unsigned (bytes : Bytes) : fixed bytes.length (unsigned bytes) = bytes := by
  induction bytes with
  | nil => rfl
  | cons byte rest ih =>
    have low := byte.toNat_lt
    simp only [List.length_cons, unsigned, fixed]
    have digit : (byte.toNat + 256 * unsigned rest) % 256 = byte.toNat := by omega
    have next : (byte.toNat + 256 * unsigned rest) / 256 = unsigned rest := by omega
    rw [digit, next, UInt8.ofNat_toNat, ih]


/-- A wire codec proves exact consumption, admission of decoded values, and
round-trip decoding with an arbitrary following field. These laws compose;
framing never treats a successfully decoded prefix as the complete input. -/
structure Codec (α : Type) where
  valid : α → Bool
  encode : α → Bytes
  read : Bytes → Option (α × Bytes)
  readExact : ∀ input value rest, read input = some (value, rest) → encode value ++ rest = input
  readValid : ∀ input value rest, read input = some (value, rest) → valid value = true
  readComplete : ∀ value rest, valid value = true → read (encode value ++ rest) = some (value, rest)

namespace Codec

def natural : Codec Nat where
  valid value := decide (value < wordLimit)
  encode := Wire.natural
  read := readNatural
  readExact input value rest read := (readNatural_sound input rest value read).2
  readValid input value rest read := by simpa using (readNatural_sound input rest value read).1
  readComplete value rest valid := readNatural_complete value rest (by simpa using valid)

def byte : Codec UInt8 where
  valid _ := true
  encode value := [value]
  read | [] => none | value :: rest => some (value, rest)
  readExact input value rest read := by cases input <;> simp_all
  readValid _ _ _ _ := rfl
  readComplete _ _ _ := rfl

private def pairRead (left : Codec α) (right : Codec β) (input : Bytes) : Option ((α × β) × Bytes) :=
  match left.read input with
  | none => none
  | some (a, tail) => match right.read tail with
    | none => none
    | some (b, rest) => some ((a, b), rest)

def pair (left : Codec α) (right : Codec β) : Codec (α × β) where
  valid value := left.valid value.1 && right.valid value.2
  encode value := left.encode value.1 ++ right.encode value.2
  read := pairRead left right
  readExact input value rest read := by
    rcases value with ⟨a, b⟩
    cases first : left.read input with
    | none => simp [pairRead, first] at read
    | some head =>
      rcases head with ⟨decodedA, tail⟩
      cases second : right.read tail with
      | none => simp [pairRead, first, second] at read
      | some after =>
        rcases after with ⟨decodedB, suffix⟩
        have l := left.readExact input decodedA tail first
        have r := right.readExact tail decodedB suffix second
        simp only [pairRead, first, second, Option.some.injEq, Prod.mk.injEq] at read
        rcases read with ⟨⟨rfl, rfl⟩, rfl⟩
        simpa [List.append_assoc, r] using l
  readValid input value rest read := by
    rcases value with ⟨a, b⟩
    cases first : left.read input with
    | none => simp [pairRead, first] at read
    | some head =>
      rcases head with ⟨decodedA, tail⟩
      cases second : right.read tail with
      | none => simp [pairRead, first, second] at read
      | some after =>
        rcases after with ⟨decodedB, suffix⟩
        have l := left.readValid input decodedA tail first
        have r := right.readValid tail decodedB suffix second
        simp only [pairRead, first, second, Option.some.injEq, Prod.mk.injEq] at read
        rcases read with ⟨⟨rfl, rfl⟩, rfl⟩
        simp [l, r]
  readComplete value rest valid := by
    rcases value with ⟨a, b⟩
    have both : left.valid a = true ∧ right.valid b = true := by simpa using valid
    simp [pairRead, List.append_assoc, left.readComplete _ _ both.1, right.readComplete _ _ both.2]

/-- Repackage a record without changing a single byte or admission condition.
Both directions are proved inverse, including every record field. -/
def iso (codec : Codec α) (pack : α → β) (unpack : β → α)
    (packUnpack : ∀ value, pack (unpack value) = value)
    (unpackPack : ∀ value, unpack (pack value) = value) : Codec β where
  valid value := codec.valid (unpack value)
  encode value := codec.encode (unpack value)
  read input := (codec.read input).map fun (value, rest) => (pack value, rest)
  readExact input value rest read := by
    cases parsed : codec.read input with
    | none => simp [parsed] at read
    | some decoded =>
      rcases decoded with ⟨original, tail⟩
      have exactRead := codec.readExact input original tail parsed
      simp only [parsed, Option.map_some, Option.some.injEq, Prod.mk.injEq] at read
      rcases read with ⟨rfl, rfl⟩
      simpa [unpackPack] using exactRead
  readValid input value rest read := by
    cases parsed : codec.read input with
    | none => simp [parsed] at read
    | some decoded =>
      rcases decoded with ⟨original, tail⟩
      have validRead := codec.readValid input original tail parsed
      simp only [parsed, Option.map_some, Option.some.injEq, Prod.mk.injEq] at read
      rcases read with ⟨rfl, rfl⟩
      simpa [unpackPack] using validRead
  readComplete value rest valid := by simp [codec.readComplete _ _ valid, packUnpack]

def reference (space : Space) (domain : Domain) : Codec (Ref space domain) :=
  natural.iso Ref.mk Ref.value (by intro value; cases value; rfl) (by intro value; rfl)

/-- The final input must be exhausted. The theorem below makes trailing-byte
rejection an invariant of every codec consumer using this entry point. -/
def decode (codec : Codec α) (bytes : Bytes) : Option α :=
  match codec.read bytes with
  | some (value, []) => some value
  | _ => none

theorem decode_exact (codec : Codec α) (bytes : Bytes) (value : α)
    (accepted : codec.decode bytes = some value) : codec.valid value = true ∧ codec.encode value = bytes := by
  unfold decode at accepted
  cases read : codec.read bytes with
  | none => simp [read] at accepted
  | some decoded =>
    rcases decoded with ⟨decoded, rest⟩
    cases rest with
    | cons => simp [read] at accepted
    | nil =>
      simp only [read, Option.some.injEq] at accepted
      subst decoded
      exact ⟨codec.readValid bytes value [] read, by simpa using codec.readExact bytes value [] read⟩

theorem decode_encode (codec : Codec α) (value : α) (valid : codec.valid value = true) :
    codec.decode (codec.encode value) = some value := by
  have read := codec.readComplete value [] valid
  simp only [List.append_nil] at read
  simp [decode, read]

theorem encode_injective (codec : Codec α) (left right : α)
    (leftValid : codec.valid left = true) (rightValid : codec.valid right = true)
    (same : codec.encode left = codec.encode right) : left = right := by
  have readings := congrArg codec.decode same
  simpa [codec.decode_encode left leftValid, codec.decode_encode right rightValid] using readings


def encodeMany (codec : Codec α) (values : List α) : Bytes := values.flatMap codec.encode

private def readCount (codec : Codec α) : Nat → Bytes → Option (List α × Bytes)
  | 0, input => some ([], input)
  | count + 1, input => match codec.read input with
    | none => none
    | some (value, tail) => match readCount codec count tail with
      | none => none
      | some (values, rest) => some (value :: values, rest)

private theorem readCount_sound (codec : Codec α) (count : Nat) (input : Bytes)
    (values : List α) (rest : Bytes) (read : readCount codec count input = some (values, rest)) :
    values.length = count ∧ values.all codec.valid = true ∧ encodeMany codec values ++ rest = input := by
  induction count generalizing input values rest with
  | zero => cases read; simp [encodeMany]
  | succ count ih =>
    cases first : codec.read input with
    | none => simp [readCount, first] at read
    | some head =>
      rcases head with ⟨value, tail⟩
      cases second : readCount codec count tail with
      | none => simp [readCount, first, second] at read
      | some after =>
        rcases after with ⟨decoded, suffix⟩
        have l := codec.readExact input value tail first
        have v := codec.readValid input value tail first
        have r := ih tail decoded suffix second
        simp only [readCount, first, second, Option.some.injEq, Prod.mk.injEq] at read
        rcases read with ⟨rfl, rfl⟩
        refine ⟨by simp [r.1], by simp [v, r.2.1], ?_⟩
        simpa [encodeMany, List.append_assoc, ← l] using congrArg (codec.encode value ++ ·) r.2.2

private theorem readCount_complete (codec : Codec α) (values : List α) (rest : Bytes)
    (valid : values.all codec.valid = true) :
    readCount codec values.length (encodeMany codec values ++ rest) = some (values, rest) := by
  induction values with
  | nil => rfl
  | cons value values ih =>
    have both : codec.valid value = true ∧ values.all codec.valid = true := by simpa using valid
    have tail := ih both.2
    simp only [encodeMany] at tail
    simp [encodeMany, readCount, List.append_assoc, codec.readComplete _ _ both.1, tail]

def Positive (codec : Codec α) : Prop := ∀ value, codec.valid value = true → 0 < (codec.encode value).length

private theorem count_le_encoded (codec : Codec α) (positive : codec.Positive)
    (values : List α) (valid : values.all codec.valid = true) :
    values.length ≤ (encodeMany codec values).length := by
  induction values with
  | nil => simp [encodeMany]
  | cons value values ih =>
    have both : codec.valid value = true ∧ values.all codec.valid = true := by simpa using valid
    have head := positive value both.1
    have tail := ih both.2
    simp only [encodeMany, List.flatMap_cons, List.length_append, List.length_cons] at *
    omega

private def listRead (codec : Codec α) (input : Bytes) : Option (List α × Bytes) :=
  match readNatural input with
  | none => none
  | some (count, tail) => if count ≤ tail.length then readCount codec count tail else none

def list (codec : Codec α) (positive : codec.Positive) : Codec (List α) where
  valid values := decide (values.length < wordLimit) && values.all codec.valid
  encode values := Wire.natural values.length ++ encodeMany codec values
  read := listRead codec
  readExact input values rest read := by
    cases first : readNatural input with
    | none => simp [listRead, first] at read
    | some header =>
      rcases header with ⟨count, tail⟩
      simp only [listRead, first] at read
      split at read
      · have headerExact := (readNatural_sound input tail count first).2
        have body := readCount_sound codec count tail values rest read
        simp only [List.append_assoc, body.1, body.2.2]
        exact headerExact
      · cases read
  readValid input values rest read := by
    cases first : readNatural input with
    | none => simp [listRead, first] at read
    | some header =>
      rcases header with ⟨count, tail⟩
      simp only [listRead, first] at read
      split at read
      · have headerValid := (readNatural_sound input tail count first).1
        have body := readCount_sound codec count tail values rest read
        simp [body.1, body.2.1, headerValid]
      · cases read
  readComplete values rest valid := by
    have both : values.length < wordLimit ∧ values.all codec.valid = true := by simpa using valid
    have countBound := count_le_encoded codec positive values both.2
    have enough : values.length ≤ (encodeMany codec values).length + rest.length := by omega
    simp [listRead, List.append_assoc, List.length_append, readNatural_complete _ _ both.1, enough,
      readCount_complete _ _ _ both.2]

theorem natural_positive : natural.Positive := by
  intro value _
  exact natural_nonempty value

theorem byte_positive : byte.Positive := by intro value _; simp [byte]

theorem pair_positive_left (left : Codec α) (right : Codec β) (positive : left.Positive) :
    (pair left right).Positive := by
  intro value valid
  have both : left.valid value.1 = true ∧ right.valid value.2 = true := by simpa [pair] using valid
  have first := positive value.1 both.1
  simp only [pair, List.length_append]
  omega

theorem iso_positive (codec : Codec α) (pack : α → β) (unpack : β → α)
    (packUnpack : ∀ value, pack (unpack value) = value)
    (unpackPack : ∀ value, unpack (pack value) = value) (positive : codec.Positive) :
    (codec.iso pack unpack packUnpack unpackPack).Positive := by
  intro value valid
  exact positive (unpack value) valid

theorem list_positive (codec : Codec α) (positive : codec.Positive) : (codec.list positive).Positive := by
  intro value _
  have head := natural_nonempty value.length
  simp only [list, List.length_append]
  omega

private def fixedRead (width : Nat) (input : Bytes) : Option (Vector UInt8 width × Bytes) :=
  if bound : width ≤ input.length then
    some (⟨(input.take width).toArray, by simp [List.length_take, Nat.min_eq_left bound]⟩, input.drop width)
  else none

def fixedBytes (width : Nat) : Codec (Vector UInt8 width) where
  valid _ := true
  encode value := value.toList
  read := fixedRead width
  readExact input value rest read := by
    unfold fixedRead at read
    split at read
    · cases read
      simp [Vector.toList]
    · cases read
  readValid _ _ _ _ := rfl
  readComplete value rest _ := by
    have size : value.toList.length = width := by simp
    have enough : width ≤ (value.toList ++ rest).length := by simp
    have take : (value.toList ++ rest).take width = value.toList := List.take_left' size
    have drop : (value.toList ++ rest).drop width = rest := List.drop_left' size
    simp only [fixedRead, dif_pos enough, take, drop]
    congr


def unit : Codec Unit where
  valid _ := true
  encode _ := []
  read input := some ((), input)
  readExact input value rest read := by cases read; rfl
  readValid _ _ _ _ := rfl
  readComplete value _ _ := by cases value; rfl

private def enumRead (values : List α) (input : Bytes) : Option (α × Bytes) :=
  match readNatural input with
  | none => none
  | some (index, rest) => (values[index]?).map fun value => (value, rest)

/-- The wire number is the index in one complete, duplicate-free constructor
inventory. Adding a constructor makes the completeness proof fail until the
inventory and codec support have been extended. -/
def enumeration [DecidableEq α] (values : List α) (complete : ∀ value, value ∈ values)
    (unique : values.Nodup) (bounded : values.length ≤ wordLimit) : Codec α where
  valid _ := true
  encode value := Wire.natural (values.idxOf value)
  read := enumRead values
  readExact input value rest read := by
    cases header : readNatural input with
    | none => simp [enumRead, header] at read
    | some parsed =>
      rcases parsed with ⟨index, suffix⟩
      cases selected : values[index]? with
      | none => simp [enumRead, header, selected] at read
      | some found =>
        obtain ⟨inside, same⟩ := List.getElem?_eq_some_iff.mp selected
        have indexEq : values.idxOf found = index := by simpa [same] using unique.idxOf_getElem index inside
        have exactRead := (readNatural_sound input suffix index header).2
        simp only [enumRead, header, selected, Option.map_some, Option.some.injEq, Prod.mk.injEq] at read
        rcases read with ⟨rfl, rfl⟩
        simpa [indexEq] using exactRead
  readValid _ _ _ _ := rfl
  readComplete value rest _ := by
    have inside := List.idxOf_lt_length_of_mem (complete value)
    have size : values.idxOf value < wordLimit := Nat.lt_of_lt_of_le inside bounded
    have found : values[values.idxOf value]? = some value := by
      simp [List.getElem?_eq_getElem inside, List.getElem_idxOf inside]
    simp [enumRead, readNatural_complete _ _ size, found]

theorem enumeration_positive [DecidableEq α] (values : List α) (complete : ∀ value, value ∈ values)
    (unique : values.Nodup) (bounded : values.length ≤ wordLimit) :
    (enumeration values complete unique bounded).Positive := by
  intro value _
  exact natural_nonempty (values.idxOf value)

private def dependentRead {ι : Type} {α : ι → Type} (tags : Codec ι) (fields : ∀ tag, Codec (α tag))
    (input : Bytes) : Option ((Sigma α) × Bytes) :=
  match tags.read input with
  | none => none
  | some (tag, tail) => match (fields tag).read tail with
    | none => none
    | some (value, rest) => some (⟨tag, value⟩, rest)

def dependent {ι : Type} {α : ι → Type} (tags : Codec ι) (fields : ∀ tag, Codec (α tag)) : Codec (Sigma α) where
  valid value := tags.valid value.1 && (fields value.1).valid value.2
  encode value := tags.encode value.1 ++ (fields value.1).encode value.2
  read := dependentRead tags fields
  readExact input value rest read := by
    cases header : tags.read input with
    | none => simp [dependentRead, header] at read
    | some first =>
      rcases first with ⟨tag, tail⟩
      cases payload : (fields tag).read tail with
      | none => simp [dependentRead, header, payload] at read
      | some second =>
        rcases second with ⟨data, suffix⟩
        have h := tags.readExact input tag tail header
        have p := (fields tag).readExact tail data suffix payload
        simp only [dependentRead, header, payload, Option.some.injEq] at read
        cases read
        simpa [List.append_assoc, p] using h
  readValid input value rest read := by
    cases header : tags.read input with
    | none => simp [dependentRead, header] at read
    | some first =>
      rcases first with ⟨tag, tail⟩
      cases payload : (fields tag).read tail with
      | none => simp [dependentRead, header, payload] at read
      | some second =>
        rcases second with ⟨data, suffix⟩
        have h := tags.readValid input tag tail header
        have p := (fields tag).readValid tail data suffix payload
        simp only [dependentRead, header, payload, Option.some.injEq] at read
        cases read
        simp [h, p]
  readComplete value rest valid := by
    have both : tags.valid value.1 = true ∧ (fields value.1).valid value.2 = true := by simpa using valid
    simp [dependentRead, List.append_assoc, tags.readComplete _ _ both.1, (fields value.1).readComplete _ _ both.2]

theorem dependent_positive {ι : Type} {α : ι → Type} (tags : Codec ι) (fields : ∀ tag, Codec (α tag)) (positive : tags.Positive) :
    (dependent tags fields).Positive := by
  intro value valid
  have both : tags.valid value.1 = true ∧ (fields value.1).valid value.2 = true := by simpa [dependent] using valid
  have head := positive value.1 both.1
  simp only [dependent, List.length_append]
  omega

private def checkedRead (codec : Codec α) (condition : α → Bool) (input : Bytes) : Option (α × Bytes) :=
  match codec.read input with
  | none => none
  | some (value, rest) => if condition value then some (value, rest) else none

/-- Additional wire-field constraints, such as u32 tags or fixed version
numbers, are checked on decoded data before it can acquire the refined codec. -/
def checked (codec : Codec α) (condition : α → Bool) : Codec α where
  valid value := codec.valid value && condition value
  encode := codec.encode
  read := checkedRead codec condition
  readExact input value rest read := by
    cases decoded : codec.read input with
    | none => simp [checkedRead, decoded] at read
    | some pair =>
      rcases pair with ⟨result, suffix⟩
      have exactRead := codec.readExact input result suffix decoded
      simp only [checkedRead, decoded] at read
      split at read
      · cases read; exact exactRead
      · cases read
  readValid input value rest read := by
    cases decoded : codec.read input with
    | none => simp [checkedRead, decoded] at read
    | some pair =>
      rcases pair with ⟨result, suffix⟩
      have validRead := codec.readValid input result suffix decoded
      simp only [checkedRead, decoded] at read
      split at read
      · rename_i conditionTrue
        cases read
        simp [validRead, conditionTrue]
      · cases read
  readComplete value rest valid := by
    have both : codec.valid value = true ∧ condition value = true := by simpa using valid
    simp [checkedRead, codec.readComplete _ _ both.1, both.2]

theorem checked_positive (codec : Codec α) (condition : α → Bool) (positive : codec.Positive) :
    (codec.checked condition).Positive := by
  intro value valid
  have both : codec.valid value = true ∧ condition value = true := by simpa [checked] using valid
  exact positive value both.1

def boolean : Codec Bool := enumeration [false, true]
  (by intro value; cases value <;> simp) (by decide) (by decide)

def optional (codec : Codec α) : Codec (Option α) :=
  let fields : Bool → Type := fun present => if present then α else Unit
  let child : ∀ present, Codec (fields present) := fun present => match present with
    | false => unit
    | true => codec
  let pack : (Sigma fields) → Option α := fun value => match value with
    | ⟨false, _⟩ => none
    | ⟨true, value⟩ => some value
  let unpack : Option α → Sigma fields
    | none => ⟨false, ()⟩
    | some value => ⟨true, value⟩
  (dependent boolean child).iso pack unpack
    (by intro value; cases value <;> rfl)
    (by intro value; rcases value with ⟨present, value⟩; cases present with
        | false => cases value; rfl
        | true => rfl)


/-- Fixed-width scalar fields use a representability predicate. In particular,
encoding a value larger than the field cannot justify a decoded smaller value. -/
def unsignedFixed (width : Nat) : Codec Nat where
  valid value := decide (value < 256 ^ width)
  encode := Wire.fixed width
  read input := ((fixedBytes width).read input).map fun (bytes, rest) => (Wire.unsigned bytes.toList, rest)
  readExact input value rest read := by
    cases decoded : (fixedBytes width).read input with
    | none => simp [decoded] at read
    | some pair =>
      rcases pair with ⟨bytes, suffix⟩
      have exactRead := (fixedBytes width).readExact input bytes suffix decoded
      simp only [decoded, Option.map_some, Option.some.injEq, Prod.mk.injEq] at read
      rcases read with ⟨rfl, rfl⟩
      have encoded : Wire.fixed width (Wire.unsigned bytes.toList) = bytes.toList := by
        simpa using fixed_unsigned bytes.toList
      rw [encoded]
      exact exactRead
  readValid input value rest read := by
    cases decoded : (fixedBytes width).read input with
    | none => simp [decoded] at read
    | some pair =>
      rcases pair with ⟨bytes, suffix⟩
      have bounded := unsigned_bound bytes.toList
      simp only [decoded, Option.map_some, Option.some.injEq, Prod.mk.injEq] at read
      rcases read with ⟨rfl, rfl⟩
      simpa using bounded
  readComplete value rest valid := by
    have bounded : value < 256 ^ width := by simpa using valid
    let bytes : Vector UInt8 width := ⟨(Wire.fixed width value).toArray, by simp [fixed_length]⟩
    have exactBytes : bytes.toList = Wire.fixed width value := by simp [bytes, Vector.toList]
    have parsed := (fixedBytes width).readComplete bytes rest rfl
    change (fixedBytes width).read (bytes.toList ++ rest) = some (bytes, rest) at parsed
    rw [exactBytes] at parsed
    rw [parsed]
    simp only [Option.map_some, exactBytes, unsigned_fixed width value bounded]

/-- A dependent length carries an intrinsically sized body, so the codec checks
its bound before taking or allocating the body. -/
def sizedBytes (lengthCodec : Codec Nat) : Codec Bytes :=
  (dependent lengthCodec fixedBytes).iso
    (fun value => value.2.toList)
    (fun bytes => ⟨bytes.length, ⟨bytes.toArray, by simp⟩⟩)
    (by intro bytes; simp [Vector.toList])
    (by intro value; rcases value with ⟨size, ⟨bytes, sizeProof⟩⟩; cases sizeProof; simp [Vector.toList])

def blob : Codec Bytes := sizedBytes natural

theorem sizedBytes_positive (lengthCodec : Codec Nat) (positive : lengthCodec.Positive) :
    (sizedBytes lengthCodec).Positive := by
  apply iso_positive
  exact dependent_positive lengthCodec fixedBytes positive

theorem unsignedFixed_positive (width : Nat) (positive : 0 < width) : (unsignedFixed width).Positive := by
  intro value _
  simpa only [unsignedFixed, fixed_length] using positive

theorem reference_positive (space : Space) (domain : Domain) : (reference space domain).Positive := by
  intro value _
  exact natural_nonempty value.value

theorem optional_positive (codec : Codec α) : (optional codec).Positive := by
  unfold optional
  exact iso_positive _ _ _ _ _ (dependent_positive _ _ (enumeration_positive _ _ _ _))


/-- A fixed header field is discarded only after proving it equals its required
value. This retains its complete bytes in the codec's exact-consumption law. -/
def constant [DecidableEq α] (codec : Codec α) (expected : α) (valid : codec.valid expected = true) : Codec Unit where
  valid _ := true
  encode _ := codec.encode expected
  read input := match codec.read input with
    | some (value, rest) => if value = expected then some ((), rest) else none
    | none => none
  readExact input value rest read := by
    cases parsed : codec.read input with
    | none => simp [parsed] at read
    | some result =>
      rcases result with ⟨decoded, suffix⟩
      have exactRead := codec.readExact input decoded suffix parsed
      simp only [parsed] at read
      split at read
      · rename_i same
        cases read
        simpa [same] using exactRead
      · cases read
  readValid _ _ _ _ := rfl
  readComplete value rest _ := by cases value; simp [codec.readComplete _ _ valid]

private def enclosedRead (outer : Codec Bytes) (inner : Codec α) (input : Bytes) : Option (α × Bytes) :=
  match outer.read input with
  | none => none
  | some (body, rest) => (inner.decode body).map fun value => (value, rest)

/-- A length-delimited body must itself decode to exact exhaustion. Trailing
bytes inside the body cannot be hidden by a valid outer length or header. -/
def enclosed (outer : Codec Bytes) (inner : Codec α) : Codec α where
  valid value := inner.valid value && outer.valid (inner.encode value)
  encode value := outer.encode (inner.encode value)
  read := enclosedRead outer inner
  readExact input value rest read := by
    cases parsed : outer.read input with
    | none => simp [enclosedRead, parsed] at read
    | some result =>
      rcases result with ⟨body, suffix⟩
      cases decoded : inner.decode body with
      | none => simp [enclosedRead, parsed, decoded] at read
      | some output =>
        have outerExact := outer.readExact input body suffix parsed
        have innerExact := (inner.decode_exact body output decoded).2
        simp only [enclosedRead, parsed, decoded, Option.map_some, Option.some.injEq, Prod.mk.injEq] at read
        rcases read with ⟨rfl, rfl⟩
        simpa [innerExact] using outerExact
  readValid input value rest read := by
    cases parsed : outer.read input with
    | none => simp [enclosedRead, parsed] at read
    | some result =>
      rcases result with ⟨body, suffix⟩
      cases decoded : inner.decode body with
      | none => simp [enclosedRead, parsed, decoded] at read
      | some output =>
        have outerValid := outer.readValid input body suffix parsed
        have innerValid := inner.decode_exact body output decoded
        simp only [enclosedRead, parsed, decoded, Option.map_some, Option.some.injEq, Prod.mk.injEq] at read
        rcases read with ⟨rfl, rfl⟩
        simp [innerValid.1, innerValid.2, outerValid]
  readComplete value rest valid := by
    have both : inner.valid value = true ∧ outer.valid (inner.encode value) = true := by simpa using valid
    simp [enclosedRead, outer.readComplete _ _ both.2, inner.decode_encode _ both.1]

end Codec

/-- Wire elements with a proved nonempty encoding. Counted collections require
this evidence; zero-byte payloads remain ordinary Codec values inside tags. -/
structure NonemptyCodec (α : Type) extends Codec α where
  positive : toCodec.Positive

instance : Coe (NonemptyCodec α) (Codec α) := ⟨NonemptyCodec.toCodec⟩

namespace NonemptyCodec

def natural : NonemptyCodec Nat := ⟨Codec.natural, Codec.natural_positive⟩
def byte : NonemptyCodec UInt8 := ⟨Codec.byte, Codec.byte_positive⟩
def boolean : NonemptyCodec Bool := ⟨Codec.boolean, Codec.enumeration_positive _ _ _ _⟩
def blob : NonemptyCodec Bytes := ⟨Codec.blob, Codec.sizedBytes_positive _ Codec.natural_positive⟩
def reference (space : Space) (domain : Domain) : NonemptyCodec (Ref space domain) :=
  ⟨Codec.reference space domain, Codec.reference_positive space domain⟩
def unsignedFixed (width : Nat) (positive : 0 < width) : NonemptyCodec Nat :=
  ⟨Codec.unsignedFixed width, Codec.unsignedFixed_positive width positive⟩
def fixedBytes (width : Nat) (positive : 0 < width) : NonemptyCodec (Vector UInt8 width) :=
  ⟨Codec.fixedBytes width, by intro value _; simpa [Codec.fixedBytes] using positive⟩
def enumeration [DecidableEq α] (values : List α) (complete : ∀ value, value ∈ values)
    (unique : values.Nodup) (bounded : values.length ≤ wordLimit) : NonemptyCodec α :=
  ⟨Codec.enumeration values complete unique bounded, Codec.enumeration_positive values complete unique bounded⟩
def pair (left : NonemptyCodec α) (right : Codec β) : NonemptyCodec (α × β) :=
  ⟨Codec.pair left.toCodec right, Codec.pair_positive_left _ _ left.positive⟩
def iso (codec : NonemptyCodec α) (pack : α → β) (unpack : β → α)
    (packUnpack : ∀ value, pack (unpack value) = value)
    (unpackPack : ∀ value, unpack (pack value) = value) : NonemptyCodec β :=
  ⟨codec.toCodec.iso pack unpack packUnpack unpackPack,
    Codec.iso_positive _ _ _ _ _ codec.positive⟩
def list (codec : NonemptyCodec α) : NonemptyCodec (List α) :=
  ⟨codec.toCodec.list codec.positive, Codec.list_positive _ codec.positive⟩
def optional (codec : Codec α) : NonemptyCodec (Option α) :=
  ⟨codec.optional, Codec.optional_positive codec⟩
def checked (codec : NonemptyCodec α) (condition : α → Bool) : NonemptyCodec α :=
  ⟨codec.toCodec.checked condition, Codec.checked_positive _ _ codec.positive⟩
def dependent {ι : Type} {α : ι → Type} (tags : NonemptyCodec ι)
    (fields : ∀ tag, Codec (α tag)) : NonemptyCodec (Sigma α) :=
  ⟨Codec.dependent tags.toCodec fields, Codec.dependent_positive _ _ tags.positive⟩
end NonemptyCodec


end BoundaryV2.Profile.Wire
