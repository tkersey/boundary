import BoundaryV2.Profile

namespace BoundaryV2.Profile.Scalars

inductive Width where
  | w8 | w16 | w32 | w64
  deriving DecidableEq, Repr

def Width.bits : Width → Nat
  | .w8 => 8 | .w16 => 16 | .w32 => 32 | .w64 => 64

def Width.bytes (width : Width) : Nat := width.bits / 8

theorem Width.positive (width : Width) : 0 < width.bits := by cases width <;> decide

inductive IntegerType where
  | signed : Width → IntegerType
  | unsigned : Width → IntegerType
  deriving DecidableEq, Repr

def IntegerType.width : IntegerType → Width
  | .signed width | .unsigned width => width

def IntegerType.minimum : IntegerType → Int
  | .signed width => -(2 ^ (width.bits - 1))
  | .unsigned _ => 0

def IntegerType.upper : IntegerType → Int
  | .signed width => 2 ^ (width.bits - 1)
  | .unsigned width => 2 ^ width.bits

def IntegerType.Contains (type : IntegerType) (value : Int) : Prop :=
  type.minimum ≤ value ∧ value < type.upper

instance (type : IntegerType) (value : Int) : Decidable (type.Contains value) :=
  inferInstanceAs (Decidable (type.minimum ≤ value ∧ value < type.upper))

structure Integer (type : IntegerType) where
  value : Int
  valid : type.Contains value
  deriving DecidableEq

theorem Integer.ext {left right : Integer type} (equal : left.value = right.value) : left = right := by
  cases left
  cases right
  cases equal
  rfl

def checkInteger (type : IntegerType) (value : Int) : Except Fault (Integer type) :=
  if valid : type.Contains value then .ok ⟨value, valid⟩ else .error .arithmeticOverflow

theorem checked_value_exact (type : IntegerType) (value : Int) (output : Integer type)
    (accepted : checkInteger type value = .ok output) : output.value = value := by
  unfold checkInteger at accepted
  split at accepted
  · cases accepted; rfl
  · cases accepted

theorem checked_overflow_exact (type : IntegerType) (value : Int) :
    checkInteger type value = .error .arithmeticOverflow ↔ ¬ type.Contains value := by
  unfold checkInteger
  split <;> simp_all

theorem zero_admitted (type : IntegerType) : type.Contains 0 := by
  cases type with
  | signed width | unsigned width => cases width <;> decide

def zero (type : IntegerType) : Integer type := ⟨0, zero_admitted type⟩

def integerType : Schema space → Option IntegerType
  | .i8 => some (.signed .w8) | .i16 => some (.signed .w16)
  | .i32 => some (.signed .w32) | .i64 => some (.signed .w64)
  | .u8 => some (.unsigned .w8) | .u16 => some (.unsigned .w16)
  | .u32 => some (.unsigned .w32) | .u64 => some (.unsigned .w64)
  | _ => none

/-- Exact two's-complement representation, independent of host integers. -/
def bits (value : Integer type) : BitVec type.width.bits :=
  BitVec.ofInt type.width.bits value.value

def interpretBits (type : IntegerType) (value : BitVec type.width.bits) : Integer type :=
  match type with
  | .signed _ => ⟨value.toInt, BitVec.le_toInt value, BitVec.toInt_lt⟩
  | .unsigned width => ⟨value.toNat, by
      constructor
      · exact Int.natCast_nonneg _
      · have bound : (value.toNat : Int) < (2 ^ width.bits : Nat) := by exact_mod_cast value.isLt
        simpa [IntegerType.upper, IntegerType.width] using bound⟩

theorem bits_preserve_signed_value (width : Width) (value : Integer (.signed width)) :
    (bits value).toInt = value.value :=
  BitVec.toInt_ofInt_eq_self width.positive value.valid.1 value.valid.2

theorem bits_preserve_unsigned_value (width : Width) (value : Integer (.unsigned width)) :
    (bits value).toNat = value.value.toNat := by
  simp only [bits, IntegerType.width, BitVec.toNat_ofInt]
  have bound : value.value < (2 ^ width.bits : Nat) := by
    simpa [IntegerType.upper] using value.valid.2
  rw [Int.emod_eq_of_lt value.valid.1 bound]

theorem interpret_bits_roundtrip (value : Integer type) : interpretBits type (bits value) = value := by
  apply Integer.ext
  cases type with
  | signed width => exact bits_preserve_signed_value width value
  | unsigned width =>
    simp only [interpretBits, bits_preserve_unsigned_value]
    exact Int.toNat_of_nonneg value.valid.1

inductive Arithmetic where
  | add | sub | mul | div | rem
  deriving DecidableEq, Repr

/-- Mathematical operations use truncation toward zero, including the sign of
remainder. Both div and rem reject the signed minimum divided by negative one case before evaluating
or narrowing their result, exactly as required by profile 1. -/
def arithmetic (operation : Arithmetic) (left right : Integer type) : Except Fault (Integer type) :=
  match operation with
  | .add => checkInteger type (left.value + right.value)
  | .sub => checkInteger type (left.value - right.value)
  | .mul => checkInteger type (left.value * right.value)
  | .div | .rem =>
    if right.value = 0 then .error .divisionByZero
    else if right.value = -1 ∧ ¬ type.Contains (-left.value) then .error .arithmeticOverflow
    else checkInteger type (if operation = .div then left.value.tdiv right.value else left.value.tmod right.value)

theorem add_result_exact (left right output : Integer type)
    (step : arithmetic .add left right = .ok output) : output.value = left.value + right.value :=
  checked_value_exact _ _ _ step

theorem subtraction_result_exact (left right output : Integer type)
    (step : arithmetic .sub left right = .ok output) : output.value = left.value - right.value :=
  checked_value_exact _ _ _ step

theorem multiplication_result_exact (left right output : Integer type)
    (step : arithmetic .mul left right = .ok output) : output.value = left.value * right.value :=
  checked_value_exact _ _ _ step

theorem addition_overflow_exact (left right : Integer type) :
    arithmetic .add left right = .error .arithmeticOverflow ↔
      ¬ type.Contains (left.value + right.value) := checked_overflow_exact _ _

theorem subtraction_overflow_exact (left right : Integer type) :
    arithmetic .sub left right = .error .arithmeticOverflow ↔
      ¬ type.Contains (left.value - right.value) := checked_overflow_exact _ _

theorem multiplication_overflow_exact (left right : Integer type) :
    arithmetic .mul left right = .error .arithmeticOverflow ↔
      ¬ type.Contains (left.value * right.value) := checked_overflow_exact _ _

theorem division_by_zero_first (left right : Integer type) (zero : right.value = 0) :
    arithmetic .div left right = .error .divisionByZero ∧
    arithmetic .rem left right = .error .divisionByZero := by simp [arithmetic, zero]

theorem signed_negation_out_of_range (width : Width) (value : Integer (.signed width)) :
    ¬ (IntegerType.signed width).Contains (-value.value) ↔
      value.value = (IntegerType.signed width).minimum := by
  have bounds := value.valid
  simp only [IntegerType.Contains, IntegerType.minimum, IntegerType.upper] at *
  omega

theorem signed_minimum_division_and_remainder (width : Width)
    (left right : Integer (.signed width))
    (minimum : left.value = (IntegerType.signed width).minimum) (negativeOne : right.value = -1) :
    arithmetic .div left right = .error .arithmeticOverflow ∧
    arithmetic .rem left right = .error .arithmeticOverflow := by
  have outside := (signed_negation_out_of_range width left).mpr minimum
  simp [arithmetic, negativeOne, outside]

private theorem absolute_bounds (value : Int) :
    -(value.natAbs : Int) ≤ value ∧ value ≤ (value.natAbs : Int) := by
  have upper := Int.le_natAbs (a := value)
  have lower := Int.le_natAbs (a := -value)
  simp only [Int.natAbs_neg] at lower
  omega

private theorem signed_quotient_bounds (a b bound : Int)
    (lower : -bound ≤ a) (upper : a < bound)
    (nonzero : b ≠ 0) (safe : ¬ (a = -bound ∧ b = -1)) :
    -bound ≤ a.tdiv b ∧ a.tdiv b < bound := by
  have quotient := absolute_bounds (a.tdiv b)
  have magnitude := Int.natAbs_tdiv_le_natAbs a b
  by_cases nonnegative : 0 ≤ a
  · have absolute : (a.natAbs : Int) = a := Int.natAbs_of_nonneg nonnegative
    omega
  · have absolute : (a.natAbs : Int) = -a := Int.ofNat_natAbs_of_nonpos (by omega)
    by_cases minimum : a = -bound
    · by_cases divisorPositive : 0 < b
      · have sign := Int.tdiv_nonneg (a := -a) (b := b) (by omega) (by omega)
        rw [Int.neg_tdiv] at sign
        omega
      · have divisor : 1 < b.natAbs := by
          have absoluteB : (b.natAbs : Int) = -b := Int.ofNat_natAbs_of_nonpos (by omega)
          omega
        have numerator : 0 < a.natAbs := by omega
        have smaller := Nat.div_lt_self numerator divisor
        have strict : (a.tdiv b).natAbs < a.natAbs := by
          simpa only [Int.natAbs_tdiv, HDiv.hDiv, instHDiv, Nat.instDiv, Div.div] using smaller
        omega
    · omega

theorem division_result_in_range (left right : Integer type)
    (nonzero : right.value ≠ 0)
    (safe : ¬ (right.value = -1 ∧ ¬ type.Contains (-left.value))) :
    type.Contains (left.value.tdiv right.value) := by
  cases type with
  | unsigned width =>
    have nonnegative := Int.tdiv_nonneg left.valid.1 right.valid.1
    have smaller := Int.tdiv_le_self right.value left.valid.1
    have valid := left.valid
    exact ⟨nonnegative, Int.lt_of_le_of_lt smaller valid.2⟩
  | signed width =>
    have valid := left.valid
    have safe' : ¬ (left.value = -(2 ^ (width.bits - 1)) ∧ right.value = -1) := by
      intro collision
      have outside := (signed_negation_out_of_range width left).mpr collision.1
      exact safe ⟨collision.2, outside⟩
    exact signed_quotient_bounds _ _ _ valid.1 valid.2 nonzero safe'

theorem remainder_result_in_range (left right : Integer type) :
    type.Contains (left.value.tmod right.value) := by
  have remainder := absolute_bounds (left.value.tmod right.value)
  have magnitude : (left.value.tmod right.value).natAbs ≤ left.value.natAbs := by
    rw [Int.natAbs_tmod]
    exact Nat.mod_le _ _
  cases type with
  | unsigned width =>
    have nonnegative := Int.tmod_nonneg right.value left.valid.1
    have absolute : (left.value.natAbs : Int) = left.value := Int.natAbs_of_nonneg left.valid.1
    have valid := left.valid
    simp only [IntegerType.Contains, IntegerType.minimum] at *
    omega
  | signed width =>
    have positive : (0 : Int) < 2 ^ (width.bits - 1) := by cases width <;> decide
    have valid := left.valid
    simp only [IntegerType.Contains, IntegerType.minimum, IntegerType.upper] at *
    by_cases nonnegative : 0 ≤ left.value
    · have absolute : (left.value.natAbs : Int) = left.value := Int.natAbs_of_nonneg nonnegative
      omega
    · have absolute : (left.value.natAbs : Int) = -left.value := Int.ofNat_natAbs_of_nonpos (by omega)
      have sign := Int.tmod_nonneg right.value (a := -left.value) (by omega)
      rw [Int.neg_tmod] at sign
      omega

theorem division_faults_exhaustive (left right : Integer type)
    (nonzero : right.value ≠ 0)
    (safe : ¬ (right.value = -1 ∧ ¬ type.Contains (-left.value))) :
    ∃ quotient remainder, arithmetic .div left right = .ok quotient ∧
      arithmetic .rem left right = .ok remainder ∧
      quotient.value = left.value.tdiv right.value ∧ remainder.value = left.value.tmod right.value := by
  have division := division_result_in_range left right nonzero safe
  have remainder := remainder_result_in_range left right
  refine ⟨⟨_, division⟩, ⟨_, remainder⟩, ?_, ?_, rfl, rfl⟩ <;>
    simp [arithmetic, nonzero, safe, checkInteger, division, remainder]

def convert (target : IntegerType) (value : Integer source) : Except Fault (Integer target) :=
  checkInteger target value.value

def conversionCanFail (source target : IntegerType) : Bool :=
  !(decide (target.Contains source.minimum) && decide (target.Contains (source.upper - 1)))

theorem widening_conversion_total (source target : IntegerType)
    (noFailure : conversionCanFail source target = false) (value : Integer source) :
    ∃ output, convert target value = .ok output ∧ output.value = value.value := by
  have both : target.Contains source.minimum ∧ target.Contains (source.upper - 1) := by
    simpa [conversionCanFail, Bool.and_eq_true] using noFailure
  have low := both.1
  have high := both.2
  have valid : target.Contains value.value := by
    have bounds := value.valid
    simp only [IntegerType.Contains] at *
    omega
  exact ⟨⟨value.value, valid⟩, by simp [convert, checkInteger, valid], rfl⟩

inductive Bitwise where
  | not | and | or | xor
  deriving DecidableEq, Repr

def complement (value : Integer type) : Integer type := interpretBits type (~~~bits value)

def bitwise (operation : Bitwise) (left right : Integer type) : Integer type :=
  interpretBits type <| match operation with
    | .not => ~~~bits left
    | .and => bits left &&& bits right
    | .or => bits left ||| bits right
    | .xor => bits left ^^^ bits right

theorem double_complement (value : Integer type) : complement (complement value) = value := by
  have back (type : IntegerType) (vector : BitVec type.width.bits) : bits (interpretBits type vector) = vector := by
    cases type <;> simp [bits, interpretBits, BitVec.ofInt_toInt, BitVec.ofInt_natCast, BitVec.ofNat_toNat]
  simp only [complement, back, BitVec.not_not, interpret_bits_roundtrip]

end BoundaryV2.Profile.Scalars
