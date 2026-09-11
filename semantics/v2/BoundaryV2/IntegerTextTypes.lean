import BoundaryV2.PrimitiveValueTypes
import Init.Data.Nat.ToString
import Init.Data.String.Basic

namespace BoundaryV2.Profile

private theorem byte_array_loop_exact (bytes : ByteArray) (index : Nat) (reversed : List UInt8) :
    ByteArray.toList.loop bytes index reversed = reversed.reverse ++ bytes.data.toList.drop index := by
  fun_induction ByteArray.toList.loop bytes index reversed with
  | case1 index reversed bounded induction =>
    rw [induction]
    have inside : index < bytes.data.toList.length := by simpa using bounded
    rw [List.drop_eq_getElem_cons inside]
    have selected : bytes.get! index = bytes.data.toList[index] := by
      cases bytes with
      | mk data => simpa [ByteArray.get!] using getElem!_pos data index inside
    simp [List.reverse_cons, List.append_assoc, selected]
  | case2 index reversed outside =>
    have exhausted : bytes.data.toList.length ≤ index := by simpa using Nat.le_of_not_gt outside
    simp [List.drop_eq_nil_of_le exhausted]

theorem byte_array_to_list_exact (bytes : ByteArray) : bytes.toList = bytes.data.toList := by
  simpa only [ByteArray.toList, List.reverse_nil, List.nil_append, List.drop_zero] using byte_array_loop_exact bytes 0 []

namespace UTF8

theorem ascii_encoding (chars : List Char) (ascii : ∀ char ∈ chars, char.toNat < 128) :
    chars.utf8Encode.toList = chars.map (fun char => UInt8.ofNat char.toNat) := by
  induction chars with
  | nil => simp
  | cons first rest induction =>
    have firstAscii := ascii first (by simp)
    have restAscii : ∀ char ∈ rest, char.toNat < 128 := fun char member => ascii char (by simp [member])
    rw [List.utf8Encode_cons, List.utf8Encode_singleton]
    have bytePrefix : first.toNat ≤ 127 := by omega
    simp only [String.utf8EncodeChar, Char.toNat_val, bytePrefix, if_true, byte_array_to_list_exact,
      ByteArray.toList_data_append, List.toList_data_toByteArray, List.singleton_append, List.map_cons]
    rw [← byte_array_to_list_exact, induction restAscii]

theorem ascii_bytes_valid (chars : List Char) (ascii : ∀ char ∈ chars, char.toNat < 128) :
    valid (chars.map (fun char => UInt8.ofNat char.toNat)) = true := by
  induction chars with
  | nil => rfl
  | cons first rest induction =>
    have firstAscii := ascii first (by simp)
    have restAscii : ∀ char ∈ rest, char.toNat < 128 := fun char member => ascii char (by simp [member])
    simp only [List.map_cons]
    rw [BoundaryV2.Profile.UTF8.valid.eq_def]
    simp only [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (show first.toNat < 256 by omega), firstAscii, if_true]
    exact induction restAscii

theorem ascii_string_valid (string : String) (ascii : ∀ char ∈ string.toList, char.toNat < 128) :
    valid string.toUTF8.toList = true ∧ string.toUTF8.toList.length = string.toList.length := by
  rw [String.toUTF8_eq_toByteArray, ← String.utf8Encode_toList, ascii_encoding string.toList ascii]
  exact ⟨ascii_bytes_valid string.toList ascii, List.length_map _⟩

end UTF8

theorem decimal_digits_ascii (number : Nat) : ∀ char ∈ Nat.toDigits 10 number, char.toNat < 128 := by
  intro char member
  have digit := Nat.isDigit_of_mem_toDigits (by decide : 0 < 10) (by decide : 10 ≤ 10) member
  have bounds := Char.isDigit_iff_toNat.mp digit
  change 48 ≤ char.toNat ∧ char.toNat ≤ 57 at bounds
  omega

theorem integer_decimal_ascii (number : Int) : ∀ char ∈ (toString number).toList, char.toNat < 128 := by
  change ∀ char ∈ (Int.repr number).toList, char.toNat < 128
  cases number with
  | ofNat value => simpa only [Int.repr, Nat.toList_repr] using decimal_digits_ascii value
  | negSucc value =>
    simp only [Int.repr, String.toList_append, List.mem_append]
    intro char member
    rcases member with member | member
    · have same : char = '-' := by simpa using member
      cases same
      decide
    · exact decimal_digits_ascii (value + 1) char (by simpa only [Nat.toList_repr] using member)

theorem integer_magnitude_bounded (kind : Scalars.IntegerType) (value : Scalars.Integer kind) :
    value.value.natAbs < 2 ^ 64 := by
  rcases value with ⟨number, bounded⟩
  cases number <;> cases kind with
  | signed width | unsigned width =>
    cases width <;> simp only [Scalars.IntegerType.Contains, Scalars.IntegerType.minimum,
      Scalars.IntegerType.upper, Scalars.Width.bits, Int.natAbs, Int.ofNat_eq_natCast] at bounded ⊢
    all_goals omega

theorem integer_decimal_length (number : Int) (bounded : number.natAbs < 2 ^ 64) :
    (toString number).toList.length ≤ 21 := by
  have digitsBound (value : Nat) (below : value < 2 ^ 64) : (Nat.toDigits 10 value).length ≤ 20 := by
    apply (Nat.length_toDigits_le_iff (by decide : 1 < 10) (by decide : 0 < 20)).mpr
    omega
  change (Int.repr number).toList.length ≤ 21
  cases number with
  | ofNat value =>
    have bound := digitsBound value bounded
    simpa only [Int.repr, Nat.toList_repr] using Nat.le_trans bound (by decide : 20 ≤ 21)
  | negSucc value =>
    have bound := digitsBound (value + 1) bounded
    simp only [Int.repr, String.toList_append, List.length_append, Nat.toList_repr]
    change 1 + (Nat.toDigits 10 (value + 1)).length ≤ 21
    omega

theorem integer_text_typed (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (schema : SchemaId space) (kind : Scalars.IntegerType) (value : Scalars.Integer kind)
    (found : schemas[schema.value]? = some .text) :
    Value.Typed schemas references (.blob schema (toString value.value).toUTF8.toList) := by
  have ascii := UTF8.ascii_string_valid (toString value.value) (integer_decimal_ascii value.value)
  have bounded := integer_decimal_length value.value (integer_magnitude_bounded kind value)
  refine .blob found ?_
  simp only [Value.blobValid, Value.blobMaximum, Value.isText, ascii.1, Bool.not_true, Bool.false_or,
    Bool.and_true, Bool.and_eq_true, decide_eq_true_eq]
  rw [ascii.2]
  constructor <;> simp only [wordLimit] <;> omega

end BoundaryV2.Profile
