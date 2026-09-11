import BoundaryV2.ProfileCodec
import BoundaryV2.Traits

namespace BoundaryV2.Profile.SchemaAdmission

/-- The production schema checker reserves the largest u64 width as its
unproductive/overflow sentinel. It is not an authored execution failure. -/
def infinity : Nat := wordLimit - 1

def structuralChildren : Schema space → List (SchemaId space)
  | .product fields | .sum fields => fields
  | .seq element | .vector element _ | .array element _ => [element]
  | _ => []

def references : Schema space → List (SchemaId space)
  | .internal inner => match inner with
    | .computation type => type.parameters ++ type.captureBound ++ [type.result]
    | .resumption type => [type.input, type.answer] ++ type.captureBound
    | .cell type _ | .suspensionPackage type | .borrowed type _ => [type]
    | _ => []
  | shape => structuralChildren shape

def ascending : List Nat → Bool
  | [] | [_] => true
  | a :: b :: rest => a < b && ascending (b :: rest)

def referencesValid (types : List (Schema space)) (shape : Schema space) : Bool :=
  (references shape).all (fun id => id.value < types.length) &&
    match shape with
    | .sum fields => !fields.isEmpty
    | .enumeration tags => ascending tags
    | .internal (.suspensionPackage type) => match types[type.value]? with
      | some (.internal (.resumption type)) => type.use == .linear || type.use == .affine
      | _ => false
    | _ => true

def minimumWidth (widths : List Nat) : Schema space → Nat
  | .unit | .internal _ => 0
  | .boolean | .i8 | .u8 => 1
  | .i16 | .u16 => 2
  | .i32 | .u32 | .enumeration _ => 4
  | .i64 | .u64 => 8
  | .bytes | .text | .boundedBytes _ | .boundedText _ | .seq _ | .vector _ _ => 1
  | .array element length => min infinity (length * widths[element.value]?.getD infinity)
  | .product fields => min infinity ((fields.map (fun id => widths[id.value]?.getD infinity)).sum)
  | .sum fields => min infinity (1 + (fields.map (fun id => widths[id.value]?.getD infinity)).foldr min infinity)

private def tighten (next : Nat → Nat) : List Nat → Nat → List Nat
  | [], _ => []
  | prior :: rest, index => min prior (next index) :: tighten next rest (index + 1)

private theorem tighten_sum_le (next : Nat → Nat) (prior : List Nat) (index : Nat) :
    (tighten next prior index).sum ≤ prior.sum := by
  induction prior generalizing index with
  | nil => simp [tighten]
  | cons first rest ih =>
    simp only [tighten, List.sum_cons]
    have tail := ih (index + 1)
    have head := Nat.min_le_left first (next index)
    omega

private theorem tighten_eq_of_sum_eq (next : Nat → Nat) (prior : List Nat) (index : Nat)
    (equal : (tighten next prior index).sum = prior.sum) : tighten next prior index = prior := by
  induction prior generalizing index with
  | nil => rfl
  | cons first rest ih =>
    have tail := tighten_sum_le next rest (index + 1)
    have head := Nat.min_le_left first (next index)
    simp only [tighten, List.sum_cons] at equal
    have firstEq : min first (next index) = first := by omega
    have tailEq : (tighten next rest (index + 1)).sum = rest.sum := by omega
    simp [tighten, firstEq, ih (index + 1) tailEq]

def widthRound (types : List (Schema space)) (prior : List Nat) : List Nat :=
  tighten (fun index => (types[index]?.map (minimumWidth prior)).getD infinity) prior 0

private theorem widthRound_decreases (types : List (Schema space)) (prior : List Nat)
    (changed : widthRound types prior ≠ prior) : (widthRound types prior).sum < prior.sum := by
  have le := tighten_sum_le (fun index => (types[index]?.map (minimumWidth prior)).getD infinity) prior 0
  have ne : (widthRound types prior).sum ≠ prior.sum := by
    intro equal
    exact changed (tighten_eq_of_sum_eq _ prior 0 equal)
  change (widthRound types prior).sum ≤ prior.sum at le
  omega

/-- The sum of finite widths strictly decreases at each recursive call. This
computes a fixed point without an execution horizon or an assumed round bound. -/
def widthLoop (types : List (Schema space)) (prior : List Nat) : List Nat :=
  if _unchanged : widthRound types prior = prior then prior
  else widthLoop types (widthRound types prior)
termination_by prior.sum
decreasing_by exact widthRound_decreases types prior _unchanged

def widths (types : List (Schema space)) : List Nat :=
  widthLoop types (List.replicate types.length infinity)

theorem widthLoop_stable (types : List (Schema space)) (prior : List Nat) :
    widthRound types (widthLoop types prior) = widthLoop types prior := by
  fun_induction widthLoop types prior with
  | case1 prior unchanged => exact unchanged
  | case2 prior changed ih => exact ih

theorem widthLoop_of_fixed (types : List (Schema space)) (prior : List Nat)
    (fixed : widthRound types prior = prior) : widthLoop types prior = prior := by
  rw [widthLoop, dif_pos fixed]

theorem widthLoop_round (types : List (Schema space)) (prior : List Nat) :
    widthLoop types (widthRound types prior) = widthLoop types prior := by
  by_cases fixed : widthRound types prior = prior
  · rw [fixed]
  · conv => rhs; rw [widthLoop, dif_neg fixed]

private theorem tighten_length (next : Nat → Nat) (prior : List Nat) (index : Nat) :
    (tighten next prior index).length = prior.length := by
  induction prior generalizing index with
  | nil => rfl
  | cons first rest ih => simp [tighten, ih]

theorem widthLoop_length (types : List (Schema space)) (prior : List Nat) :
    (widthLoop types prior).length = prior.length := by
  fun_induction widthLoop types prior with
  | case1 prior unchanged => rfl
  | case2 prior changed ih =>
    exact ih.trans (tighten_length _ _ _)

def valid (types : List (Schema space)) : Bool :=
  (Codecs.schema space).list.valid types && types.all (referencesValid types) &&
    (widths types).all (fun width => width < infinity)

theorem widths_length (types : List (Schema space)) : (widths types).length = types.length := by
  simp [widths, widthLoop_length]

end BoundaryV2.Profile.SchemaAdmission
