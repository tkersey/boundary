import BoundaryV2.Control

namespace BoundaryV2.Regions

open Core Control

/-- The modeled mutable fragment has mathematical-number cells. A template
contains frozen local contents and reference identities, never outer contents. -/
structure Cell where
  identity : Nat
  value : Nat
  deriving DecidableEq, Repr

def readCell (identity : Nat) : List Cell → Option Nat
  | [] => none
  | cell :: rest => if identity = cell.identity then some cell.value else readCell identity rest

def writeCell (identity value : Nat) : List Cell → List Cell
  | [] => []
  | cell :: rest =>
    if identity = cell.identity then { cell with value } :: rest
    else cell :: writeCell identity value rest

inductive Reference where
  | local : Nat → Reference
  | outer : Nat → Reference
  deriving DecidableEq, Repr

def Reference.rename (rename : Nat → Nat) : Reference → Reference
  | .local identity => .local (rename identity)
  | .outer identity => .outer identity

def Cell.rename (rename : Nat → Nat) (cell : Cell) : Cell :=
  { cell with identity := rename cell.identity }

structure Template (input answer : Ty) where
  continuation : Context input answer
  locals : List Cell
  references : List Reference

structure Activation (input answer : Ty) where
  continuation : Context input answer
  locals : List Cell
  references : List Reference

def Template.activate (template : Template a b) (attachments cells : Nat → Nat) : Activation a b :=
  ⟨template.continuation.rename attachments cells, template.locals.map (Cell.rename cells),
    template.references.map (Reference.rename cells)⟩

/-- Shared reads take the current outer heap at the time of the read. There is
no copy of this heap in a template or activation. -/
def Activation.read (activation : Activation a b) (outside : List Cell) : Reference → Option Nat
  | .local identity => readCell identity activation.locals
  | .outer identity => readCell identity outside

def Activation.writeLocal (activation : Activation a b) (identity value : Nat) : Activation a b :=
  { activation with locals := writeCell identity value activation.locals }

def Reference.InScope (locals owners : List Nat) : Reference → Prop
  | .local identity => identity ∈ locals
  | .outer identity => identity ∈ owners

def Template.Scoped (template : Template a b) (owners : List Nat) : Prop :=
  ∀ reference, reference ∈ template.references →
    reference.InScope (template.locals.map Cell.identity) owners

def Activation.Scoped (activation : Activation a b) (owners : List Nat) : Prop :=
  ∀ reference, reference ∈ activation.references →
    reference.InScope (activation.locals.map Cell.identity) owners

theorem activation_preserves_scope (template : Template a b) (owners : List Nat)
    (attachments cells : Nat → Nat) (scopeValid : template.Scoped owners) :
    (template.activate attachments cells).Scoped owners := by
  intro reference present
  obtain ⟨original, member, rfl⟩ := List.mem_map.mp present
  have valid := scopeValid original member
  cases original with
  | outer identity => exact valid
  | «local» identity =>
    obtain ⟨cell, cellPresent, rfl⟩ := List.mem_map.mp valid
    exact List.mem_map.mpr ⟨cell.rename cells, List.mem_map.mpr ⟨cell, cellPresent, rfl⟩, rfl⟩

/-- Fresh activation control is separate from the reusable template. This
returns a new owned control identity; the input template is retained unchanged. -/
def Template.resume (template : Template a b) (state : Ownership)
    (attachments cells : Nat → Nat) : Ownership × Activation a b :=
  (state.activateMulti, template.activate attachments cells)

theorem multi_resume_preserves_ownership_and_scope (template : Template a b)
    (state : Ownership) (owners : List Nat) (attachments cells : Nat → Nat)
    (ownershipValid : state.Valid) (scopeValid : template.Scoped owners) :
    (template.resume state attachments cells).1.Valid ∧
      (template.resume state attachments cells).2.Scoped owners :=
  ⟨multi_activation_preserves_ownership state ownershipValid,
    activation_preserves_scope template owners attachments cells scopeValid⟩

theorem successive_multi_resumes_have_distinct_control (template : Template a b)
    (state : Ownership) (attachments cells : Nat → Nat) :
    state.fresh ≠ (template.resume state attachments cells).1.fresh :=
  multi_activations_are_distinct state

/-- The modeled cell payloads and contexts have no exclusive resources or exit
obligations. For this clone-safe fragment, freezing consumes the original token. -/
def freeze (owned : Owned a b) (state : Ownership) (locals : List Cell)
    (references : List Reference) : Option (Ownership × Template a b) := do
  let next ← owned.dispose state .freeze
  return (next, ⟨owned.continuation, locals, references⟩)

theorem freeze_consumes_original_ownership (owned : Owned a b)
    (state next : Ownership) (locals : List Cell) (references : List Reference)
    (template : Template a b) (ownershipValid : state.Valid)
    (step : freeze owned state locals references = some (next, template)) :
    next.Valid ∧ owned.dispose next .resume = none ∧
      template.continuation = owned.continuation := by
  cases consumed : owned.dispose state .freeze with
  | none => simp [freeze, consumed] at step
  | some nextState =>
    simp [freeze, consumed] at step
    rcases step with ⟨rfl, rfl⟩
    exact ⟨linear_disposition_preserves_ownership owned state nextState .freeze ownershipValid consumed,
      linear_disposition_cannot_repeat owned state nextState .freeze .resume ownershipValid consumed, rfl⟩

theorem renamed_read_preserves_frozen_contents (cells : List Cell) (rename : Nat → Nat)
    (injective : Function.Injective rename) (identity : Nat) :
    readCell (rename identity) (cells.map (Cell.rename rename)) = readCell identity cells := by
  induction cells with
  | nil => rfl
  | cons cell rest ih =>
    simp only [List.map_cons, readCell, Cell.rename]
    by_cases same : identity = cell.identity
    · simp [same]
    · have distinct : rename identity ≠ rename cell.identity := fun h => same (injective h)
      simp [same, distinct, ih]

theorem activation_preserves_local_read (template : Template a b)
    (attachments cells : Nat → Nat) (injective : Function.Injective cells)
    (identity : Nat) (outside : List Cell) :
    (template.activate attachments cells).read outside (.local (cells identity)) =
      readCell identity template.locals :=
  renamed_read_preserves_frozen_contents template.locals cells injective identity

theorem activation_observes_current_outer_heap (template : Template a b)
    (attachments cells : Nat → Nat) (outside : List Cell) (identity : Nat) :
    (template.activate attachments cells).read outside (.outer identity) = readCell identity outside := rfl

theorem activation_preserves_computation (template : Template a b)
    (attachments cells : Nat → Nat) (argument : Value a) :
    (template.activate attachments cells).continuation.run argument =
      template.continuation.run argument :=
  renamed_context_preserves_value template.continuation attachments cells argument

theorem activation_preserves_aliases (cells : Nat → Nat) (left right : Reference)
    (alias : left = right) : left.rename cells = right.rename cells := congrArg _ alias

theorem local_activation_names_are_disjoint (first second : Nat → Nat)
    (disjoint : ∀ a b, first a ≠ second b) (a b : Nat) :
    Reference.local (first a) ≠ Reference.local (second b) := by
  intro equal
  exact disjoint a b (Reference.local.inj equal)

/-- The caller supplies injective fresh names. A total scoped reference rewrite
uses that same mapping for the local owner set and every local dependency. -/
theorem clone_preserves_region_scope (owners dependencies : List Nat)
    (rename : Nat → Nat) (scopeValid : InScope owners dependencies) :
    InScope (owners.map rename) (dependencies.map rename) := by
  intro identity present
  obtain ⟨original, member, rfl⟩ := List.mem_map.mp present
  exact List.mem_map.mpr ⟨original, scopeValid original member, rfl⟩

/-- A local write cannot alter another activation: updates return new local
storage, and no template or outer cell store is part of that operation. -/
theorem write_preserves_outer_read (activation : Activation a b)
    (outside : List Cell) (localIdentity value sharedIdentity : Nat) :
    (activation.writeLocal localIdentity value).read outside (.outer sharedIdentity) =
      activation.read outside (.outer sharedIdentity) := rfl

theorem write_preserves_reference_aliases (activation : Activation a b) (identity value : Nat) :
    (activation.writeLocal identity value).references = activation.references := rfl

/-- With a frozen inner cell, both independent branches start from zero. -/
theorem choice_outside_state :
    let frozen : List Cell := [⟨0, 0⟩]
    let left := writeCell 10 1 (frozen.map (Cell.rename (fun id => id + 10)))
    let right := writeCell 20 1 (frozen.map (Cell.rename (fun id => id + 20)))
    (readCell 10 left, readCell 20 right) = (some 1, some 1) := rfl

/-- With one outer cell, the second branch observes the first branch's update. -/
theorem state_outside_choice :
    let shared : List Cell := [⟨0, 0⟩]
    let afterLeft := writeCell 0 1 shared
    let afterRight := writeCell 0 2 afterLeft
    (readCell 0 afterLeft, readCell 0 afterRight) = (some 1, some 2) := rfl

end BoundaryV2.Regions
