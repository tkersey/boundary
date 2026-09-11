import BoundaryV2.Profile

namespace BoundaryV2.Profile.Traits

inductive Kind where
  | copy | drop | clone | external
  deriving DecidableEq, Repr
abbrev Atom (space : Space) := SchemaId space × Kind

/-- A successful local rule lists every premise. Rules reflect structural
properties, including dependencies between resumption copying and capture
cloning; the input artifact cannot assert these properties. -/
def premises (shape : Schema space) (kind : Kind) : Option (List (Atom space)) :=
  match shape with
  | .product fields | .sum fields => some (fields.map (·, kind))
  | .seq element | .vector element _ | .array element _ => some [(element, kind)]
  | .internal inner => match kind, inner with
    | .external, _ => none
    | _, .capability _ | _, .region _ => some []
    | .copy, .cell _ _ | .drop, .cell _ _ | .copy, .borrowed _ _ | .drop, .borrowed _ _ => some []
    | .clone, .cell element _ | .clone, .borrowed element _ => some [(element, .clone)]
    | _, .computation type =>
      if (if kind == .drop then type.use != .linear else type.use == .reusable || type.use == .multi)
      then some (type.captureBound.map (·, kind)) else none
    | _, .resumption type =>
      if type.obligations then none
      else if kind == .drop then
        if type.use == .multi then some []
        else if type.use == .affine then some (type.captureBound.map (·, .drop))
        else none
      else if type.use == .multi then some (type.captureBound.map (·, .clone))
      else none
    | _, .suspensionPackage _ | _, .abstractResource _ => none
  | _ => some []

def rule (schemas : List (Schema space)) (atom : Atom space) : Option (List (Atom space)) := do
  let shape ← schemas[atom.1.value]?
  premises shape atom.2

/-- A closed support is a finite coinductive derivation. Repeated references
and recursive immutable schemas share premises rather than being unfolded as
an unbounded tree. Every member must have a valid local rule. -/
def closed (schemas : List (Schema space)) (support : List (Atom space)) : Bool :=
  support.all fun atom => match rule schemas atom with
    | none => false
    | some children => children.all support.contains

def checkSupport (schemas : List (Schema space)) (root : Atom space) (support : List (Atom space)) : Bool :=
  support.contains root && closed schemas support

def expand (schemas : List (Schema space)) (support : List (Atom space)) : List (Atom space) :=
  (support ++ support.flatMap (fun atom => (rule schemas atom).getD [])).eraseDups

private def iterate (step : α → α) (initial : α) : Nat → α
  | 0 => initial
  | count + 1 => step (iterate step initial count)

private theorem iterate_from_step (step : α → α) (initial : α) (count : Nat) :
    iterate step (step initial) count = iterate step initial (count + 1) := by
  induction count with
  | zero => rfl
  | succ count ih => exact congrArg step ih

private theorem iterate_fixed (step : α → α) (initial : α) (fixed : step initial = initial)
    (count : Nat) : iterate step initial count = initial := by
  induction count with
  | zero => rfl
  | succ count ih => simpa only [iterate, ih] using fixed

private theorem iterate_eq_rec (step : α → α) (initial : α) (count : Nat) :
    iterate step initial count = Nat.rec initial (fun _ previous => step previous) count := by
  induction count with
  | zero => rfl
  | succ count ih => exact congrArg step ih

private def untilStable [DecidableEq α] (step : α → α) : Nat → α → α
  | 0, current => current
  | count + 1, current =>
    let next := step current
    if next = current then current else untilStable step count next

private theorem untilStable_exact [DecidableEq α] (step : α → α) (count : Nat) (initial : α) :
    untilStable step count initial = iterate step initial count := by
  induction count generalizing initial with
  | zero => rfl
  | succ count ih =>
    unfold untilStable
    dsimp only
    split
    · rename_i fixed
      exact (iterate_fixed step initial fixed (count + 1)).symm
    · exact (ih (step initial)).trans (iterate_from_step step initial count)

/-- Stop at a fixed support. Continuing the original finite expansion from
that point produces the same set on every remaining round. -/
def support (schemas : List (Schema space)) (root : Atom space) : List (Atom space) :=
  untilStable (expand schemas) (4 * schemas.length) [root]

theorem support_preserves_bounded_search (schemas : List (Schema space)) (root : Atom space) :
    support schemas root = Nat.rec [root] (fun _ previous => expand schemas previous) (4 * schemas.length) :=
  (untilStable_exact (expand schemas) (4 * schemas.length) [root]).trans
    (iterate_eq_rec (expand schemas) [root] (4 * schemas.length))

/-- The finite catalog bounds proof search, not execution. Acceptance always
rechecks closure, so exhausting this construction cannot manufacture a trait. -/
def check (schemas : List (Schema space)) (kind : Kind) (type : SchemaId space) : Bool :=
  checkSupport schemas (type, kind) (support schemas (type, kind))

inductive Reach (schemas : List (Schema space)) (root : Atom space) : Atom space → Prop where
  | refl : Reach schemas root root
  | step : Reach schemas root parent → rule schemas parent = some children →
      child ∈ children → Reach schemas root child

def Safe (schemas : List (Schema space)) (root : Atom space) : Prop :=
  ∀ atom, Reach schemas root atom → ∃ children, rule schemas atom = some children

theorem Reach.trans (first : Reach schemas root middle) (second : Reach schemas middle last) :
    Reach schemas root last := by
  induction second with
  | refl => exact first
  | step _ rule member induction => exact .step induction rule member

theorem Safe.reachable (safe : Safe schemas root) (path : Reach schemas root child) :
    Safe schemas child := fun atom continuation => safe atom (path.trans continuation)

/-- Computation traits include every declared capture dependency. A checked
outer closure trait cannot conceal an unsafe capture behind its use label. -/
theorem Safe.computation_capture (schemas : List (Schema space)) (type : SchemaId space)
    (signature : ComputationType space) (kind : Kind) (capture : SchemaId space)
    (found : schemas[type.value]? = some (.internal (.computation signature)))
    (safe : Safe schemas (type, kind)) (member : capture ∈ signature.captureBound) :
    Safe schemas (capture, kind) := by
  obtain ⟨children, checked⟩ := safe _ .refl
  apply safe.reachable
  apply Reach.step Reach.refl checked
  have childrenKnown : children = signature.captureBound.map (·, kind) := by
    cases kind <;> simp [rule, found, premises] at checked
    all_goals exact checked.2.symm
  rw [childrenKnown]
  exact List.mem_map.mpr ⟨capture, member, rfl⟩

theorem closed_member (schemas : List (Schema space)) (support : List (Atom space))
    (valid : closed schemas support = true) (member : atom ∈ support) :
    ∃ children, rule schemas atom = some children ∧ ∀ child ∈ children, child ∈ support := by
  have row := List.all_eq_true.mp valid atom member
  cases found : rule schemas atom with
  | none => simp [found] at row
  | some children =>
    refine ⟨children, rfl, ?_⟩
    simpa [found, List.all_eq_true] using row

theorem support_sound (schemas : List (Schema space)) (root : Atom space) (support : List (Atom space))
    (accepted : checkSupport schemas root support = true) : Safe schemas root := by
  have both : root ∈ support ∧ closed schemas support = true := by
    simpa [checkSupport, Bool.and_eq_true] using accepted
  have included : ∀ atom, Reach schemas root atom → atom ∈ support := by
    intro atom path
    induction path with
    | refl => exact both.1
    | step _ found child induction =>
      obtain ⟨_, other, children⟩ := closed_member schemas support both.2 induction
      cases found.symm.trans other
      exact children _ child
  intro atom path
  obtain ⟨children, found, _⟩ := closed_member schemas support both.2 (included atom path)
  exact ⟨children, found⟩

theorem check_sound (schemas : List (Schema space)) (kind : Kind) (type : SchemaId space)
    (accepted : check schemas kind type = true) : Safe schemas (type, kind) :=
  support_sound schemas _ _ accepted

theorem external_has_no_internal (schemas : List (Schema space)) (root id : SchemaId space)
    (safe : Safe schemas (root, .external))
    (path : Reach schemas (root, .external) (id, .external)) :
    ∀ inner, schemas[id.value]? ≠ some (.internal inner) := by
  intro inner found
  obtain ⟨children, accepted⟩ := safe _ path
  simp [rule, found, premises] at accepted

theorem unused_internal_alternative_is_not_exportable :
    check ([.unit, .sum [0, 2], .internal (.capability 0)] : List (Schema .target)) .external 1 = false := by
  decide +kernel

theorem recursive_public_data_is_exportable :
    check ([.unit, .sum [0, 1]] : List (Schema .target)) .external 1 = true := by decide +kernel

theorem exclusive_capture_cannot_be_cloned :
    check ([.unit, .internal (.abstractResource 0),
      .internal (.computation ⟨[], 0, [], [1], .multi, []⟩)] : List (Schema .target)) .clone 2 = false := by
  decide +kernel

end BoundaryV2.Profile.Traits
