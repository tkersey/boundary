import BoundaryV2.Profile

namespace BoundaryV2.Profile.SourceJson

/-- Staged IR has unsigned numeric metadata and ASCII field/tag strings;
semantic text and literal contents are byte arrays. Objects retain field order
and are admitted only when decoded keys are unique. -/
inductive Value where
  | null
  | boolean : Bool → Value
  | number : Nat → Value
  | string : Bytes → Value
  | array : List Value → Value
  | object : List (Bytes × Value) → Value

private structure Scan (α : Type) (input : Bytes) where
  value : α
  rest : Bytes
  bound : rest.length ≤ input.length

private def whitespace (byte : UInt8) : Bool := byte == 32 || byte == 9 || byte == 10 || byte == 13

private def skipSpace : Bytes → Bytes
  | [] => []
  | byte :: rest => if whitespace byte then skipSpace rest else byte :: rest

private theorem skipSpace_bound (bytes : Bytes) : (skipSpace bytes).length ≤ bytes.length := by
  induction bytes with
  | nil => exact Nat.le_refl _
  | cons byte rest ih =>
    simp only [skipSpace]
    split
    · exact Nat.le_trans ih (Nat.le_succ _)
    · exact Nat.le_refl _

private def digit (byte : UInt8) : Option Nat :=
  if 48 ≤ byte.toNat ∧ byte.toNat ≤ 57 then some (byte.toNat - 48) else none

private def hexDigit (byte : UInt8) : Option Nat :=
  if 48 ≤ byte.toNat ∧ byte.toNat ≤ 57 then some (byte.toNat - 48)
  else if 65 ≤ byte.toNat ∧ byte.toNat ≤ 70 then some (byte.toNat - 55)
  else if 97 ≤ byte.toNat ∧ byte.toNat ≤ 102 then some (byte.toNat - 87)
  else none

private def scanDigits (input : Bytes) (accumulator : Nat) : Option (Scan Nat input) :=
  match input with
  | [] => some ⟨accumulator, [], by simp⟩
  | byte :: rest =>
    match digit byte with
    | none => some ⟨accumulator, byte :: rest, Nat.le_refl _⟩
    | some value =>
      if accumulator * 10 + value < wordLimit then do
        let result ← scanDigits rest (accumulator * 10 + value)
        return ⟨result.value, result.rest, Nat.le_trans result.bound (by simp only [List.length_cons]; omega)⟩
      else none
termination_by input.length

private def scanString (input : Bytes) (accumulator : Bytes) : Option (Scan Bytes input) :=
  match input with
  | [] => none
  | byte :: rest =>
    if byte == 34 then some ⟨accumulator.reverse, rest, by simp⟩
    else if byte == 92 then
      match rest with
      | [] => none
      | escape :: after =>
        if escape == 117 then
          match after with
          | a :: b :: c :: d :: tail => do
            let a ← hexDigit a
            let b ← hexDigit b
            let c ← hexDigit c
            let d ← hexDigit d
            let character := a * 4096 + b * 256 + c * 16 + d
            if character < 128 then
              let result ← scanString tail (UInt8.ofNat character :: accumulator)
              return ⟨result.value, result.rest, Nat.le_trans result.bound (by simp only [List.length_cons]; omega)⟩
            else none
          | _ => none
        else do
          let character ← match escape.toNat with
            | 34 => some (34 : UInt8) | 92 => some 92 | 47 => some 47
            | 98 => some 8 | 102 => some 12 | 110 => some 10 | 114 => some 13 | 116 => some 9
            | _ => none
          let result ← scanString after (character :: accumulator)
          return ⟨result.value, result.rest, Nat.le_trans result.bound (by simp only [List.length_cons]; omega)⟩
    else if 32 ≤ byte.toNat ∧ byte.toNat < 128 then do
      let result ← scanString rest (byte :: accumulator)
      return ⟨result.value, result.rest, Nat.le_trans result.bound (by simp only [List.length_cons]; omega)⟩
    else none
termination_by input.length

def text (value : String) : Bytes := value.toUTF8.data.toList

private def word (expected : Bytes) (input : Bytes) : Option (Scan Unit input) :=
  if expected.isPrefixOf input then
    some ⟨(), input.drop expected.length, by simp⟩
  else none

private inductive Frame where
  | array : List Value → Frame
  | object : Bytes → List (Bytes × Value) → Frame

private inductive Phase where
  | needValue
  | haveValue : Value → Phase

private def property (input : Bytes) : Option (Scan Bytes input) :=
  let trimmed := skipSpace input
  match eq : trimmed with
  | [] => none
  | quote :: rest =>
    if quote == 34 then do
      let name ← scanString rest []
      let afterName := skipSpace name.rest
      match colon : afterName with
      | [] => none
      | byte :: value =>
        if byte == 58 then
          some ⟨name.value, value, by
            have trimBound := skipSpace_bound input
            have nameBound := name.bound
            have colonBound := skipSpace_bound name.rest
            simp only [trimmed] at eq
            simp only [afterName] at colon
            rw [eq] at trimBound
            rw [colon] at colonBound
            simp only [List.length_cons] at *
            omega⟩
        else none
    else none

/-- An explicit parser stack keeps nesting in data. Every recursive call
consumes input; the termination argument is input length, not execution fuel. -/
private def parseLoop (input : Bytes) (frames : List Frame) (phase : Phase) : Option (Value × Bytes) :=
  let remaining := skipSpace input
  have trimmed := skipSpace_bound input
  match phase with
  | .needValue =>
    match eq : remaining with
    | [] => none
    | byte :: rest =>
      have shorter : rest.length < input.length := by
        simp only [remaining] at eq
        rw [eq] at trimmed
        simp only [List.length_cons] at trimmed
        omega
      if byte == 34 then do
        let parsed ← scanString rest []
        parseLoop parsed.rest frames (.haveValue (.string parsed.value))
      else if byte == 91 then
        let next := skipSpace rest
        match nextEq : next with
        | [] => none
        | close :: tail =>
          if close == 93 then parseLoop tail frames (.haveValue (.array []))
          else parseLoop next (.array [] :: frames) .needValue
      else if byte == 123 then
        let next := skipSpace rest
        match nextEq : next with
        | [] => none
        | close :: tail =>
          if close == 125 then parseLoop tail frames (.haveValue (.object []))
          else do
            let parsed ← property next
            parseLoop parsed.rest (.object parsed.value [] :: frames) .needValue
      else if byte == 116 then do
        let parsed ← word (text "rue") rest
        parseLoop parsed.rest frames (.haveValue (.boolean true))
      else if byte == 102 then do
        let parsed ← word (text "alse") rest
        parseLoop parsed.rest frames (.haveValue (.boolean false))
      else if byte == 110 then do
        let parsed ← word (text "ull") rest
        parseLoop parsed.rest frames (.haveValue .null)
      else do
        let first ← digit byte
        if first == 0 then
          if (rest.head?.bind digit).isSome then none
          else parseLoop rest frames (.haveValue (.number 0))
        else
          let parsed ← scanDigits rest first
          parseLoop parsed.rest frames (.haveValue (.number parsed.value))
  | .haveValue value =>
    match frames with
    | [] => some (value, remaining)
    | .array values :: frames =>
      match eq : remaining with
      | [] => none
      | byte :: rest =>
        if byte == 44 then parseLoop rest (.array (value :: values) :: frames) .needValue
        else if byte == 93 then parseLoop rest frames (.haveValue (.array (value :: values).reverse))
        else none
    | .object key fields :: frames =>
      match eq : remaining with
      | [] => none
      | byte :: rest =>
        let fields := (key, value) :: fields
        if byte == 125 then parseLoop rest frames (.haveValue (.object fields.reverse))
        else if byte == 44 then do
          let parsed ← property rest
          if fields.any (fun field => field.1 == parsed.value) then none
          else parseLoop parsed.rest (.object parsed.value fields :: frames) .needValue
        else none
termination_by input.length
decreasing_by
  all_goals grind only [skipSpace_bound, Scan.bound, List.length_cons]

def parse (input : Bytes) : Option Value :=
  match parseLoop input [] .needValue with
  | some (value, []) => some value
  | _ => none

end BoundaryV2.Profile.SourceJson
