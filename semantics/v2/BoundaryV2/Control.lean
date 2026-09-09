import BoundaryV2.Lowering
import BoundaryV2.Ownership

namespace BoundaryV2.Control

open Core

inductive Mode where
  | deep | shallow
  deriving DecidableEq, Repr

/-- A typed evaluation-context frame. `attachment` is a runtime capability
identity, not an operation label. Region frames have no value-level coercion. -/
inductive Frame : Ty → Ty → Type where
  | bind : Expr [a] b → Frame a b
  | delimiter : (attachment : Nat) → Expr [a] b → Frame a b
  | region : (owner : Nat) → Frame a a

def Frame.run : Frame a b → Value a → Value b
  | .bind expression, value => expression.eval (.cons value .nil)
  | .delimiter _ returned, value => returned.eval (.cons value .nil)
  | .region _, value => value

/-- Source evaluation contexts are typed compositions, ordered from the current
hole to its caller. They are finite data, including all return clauses. -/
inductive Context : Ty → Ty → Type where
  | done : Context a a
  | push : Frame a b → Context b c → Context a c

def Context.append : Context a b → Context b c → Context a c
  | .done, after => after
  | .push frame rest, after => .push frame (rest.append after)

def Context.run : Context a b → Value a → Value b
  | .done, value => value
  | .push frame rest, value => rest.run (frame.run value)

theorem append_runs_in_order (before : Context a b) (after : Context b c)
    (value : Value a) :
    (before.append after).run value = after.run (before.run value) := by
  induction before with
  | done => rfl
  | push frame rest ih => exact ih after _

theorem append_done (context : Context a b) : context.append .done = context := by
  induction context with
  | done => rfl
  | push frame rest ih => simp [Context.append, ih]

theorem append_associative (first : Context a b) (second : Context b c)
    (third : Context c d) :
    (first.append second).append third = first.append (second.append third) := by
  induction first with
  | done => rfl
  | push frame rest ih => simp [Context.append, ih]

/-- A successful selection retains both sides of the selected delimiter. This
dependent record prevents confusing the body result with the handler answer. -/
structure Selection (input output : Ty) where
  body : Ty
  answer : Ty
  attachment : Nat
  inside : Context input body
  returned : Expr [body] answer
  outside : Context answer output

def Selection.whole (selected : Selection a b) : Context a b :=
  selected.inside.append
    (.push (.delimiter selected.attachment selected.returned) selected.outside)

def Selection.prepend (selected : Selection b c) (frame : Frame a b) : Selection a c :=
  { selected with inside := .push frame selected.inside }

/-- Selection follows an explicit attachment and stops at its first occurrence.
An absent attachment is a residual operation; it is not resolved by a label. -/
def select (attachment : Nat) : Context a b → Option (Selection a b)
  | .done => none
  | .push (.delimiter actual returned) rest =>
    if attachment = actual then
      some ⟨_, _, actual, .done, returned, rest⟩
    else (select attachment rest).map (fun selected => selected.prepend (.delimiter actual returned))
  | .push frame rest =>
    (select attachment rest).map (fun selected => selected.prepend frame)

theorem selection_reconstructs_context (context : Context a b) (attachment : Nat)
    (selected : Selection a b) (found : select attachment context = some selected) :
    selected.whole = context := by
  induction context with
  | done => simp [select] at found
  | push frame rest ih =>
    cases frame with
    | bind expression =>
      simp only [select, Option.map_eq_some_iff] at found
      obtain ⟨inner, found, rfl⟩ := found
      exact congrArg (Context.push (.bind expression)) (ih inner found)
    | region owner =>
      simp only [select, Option.map_eq_some_iff] at found
      obtain ⟨inner, found, rfl⟩ := found
      exact congrArg (Context.push (.region owner)) (ih inner found)
    | delimiter actual returned =>
      simp only [select] at found
      split at found
      next same => cases found; rfl
      next different =>
        simp only [Option.map_eq_some_iff] at found
        obtain ⟨inner, found, rfl⟩ := found
        exact congrArg (Context.push (.delimiter actual returned)) (ih inner found)

theorem selection_uses_capability_identity (context : Context a b) (attachment : Nat)
    (selected : Selection a b) (found : select attachment context = some selected) :
    selected.attachment = attachment := by
  induction context with
  | done => simp [select] at found
  | push frame rest ih =>
    cases frame with
    | bind expression =>
      simp only [select, Option.map_eq_some_iff] at found
      obtain ⟨inner, found, rfl⟩ := found
      exact ih inner found
    | region owner =>
      simp only [select, Option.map_eq_some_iff] at found
      obtain ⟨inner, found, rfl⟩ := found
      exact ih inner found
    | delimiter actual returned =>
      simp only [select] at found
      split at found
      next same => cases found; exact same.symm
      next different =>
        simp only [Option.map_eq_some_iff] at found
        obtain ⟨inner, found, rfl⟩ := found
        exact ih inner found

def Mode.result : Mode → Ty → Ty → Ty
  | .deep, _, answer => answer
  | .shallow, body, _ => body

/-- Deep capture includes the selected return delimiter. Shallow capture ends
before it. The operation clause itself always executes in `outside`. -/
def Selection.capture (selected : Selection a b) (mode : Mode) :
    Context a (mode.result selected.body selected.answer) :=
  match mode with
  | .deep => selected.inside.append
      (.push (.delimiter selected.attachment selected.returned) .done)
  | .shallow => selected.inside

def Selection.clauseResult (selected : Selection a b) (answer : Value selected.answer) : Value b :=
  selected.outside.run answer

def Selection.resume (selected : Selection a b) (mode : Mode) (argument : Value a)
    (post : Expr [mode.result selected.body selected.answer] selected.answer) : Value b :=
  selected.clauseResult (post.eval (.cons ((selected.capture mode).run argument) .nil))

theorem deep_resume_applies_return_once (selected : Selection a b) (value : Value a)
    (post : Expr [selected.answer] selected.answer) :
    selected.resume .deep value post =
      selected.outside.run (post.eval (.cons
        (selected.returned.eval (.cons (selected.inside.run value) .nil)) .nil)) := by
  simp [Selection.resume, Selection.clauseResult, Selection.capture, append_runs_in_order,
    Context.run, Frame.run]
  rfl

theorem shallow_resume_does_not_reinstall (selected : Selection a b) (value : Value a)
    (post : Expr [selected.body] selected.answer) :
    selected.resume .shallow value post =
      selected.outside.run (post.eval (.cons (selected.inside.run value) .nil)) := rfl

theorem clause_answer_bypasses_return (selected : Selection a b) (answer : Value selected.answer) :
    selected.clauseResult answer = selected.outside.run answer := rfl

theorem non_tail_resume_retains_both_continuations (selected : Selection a b)
    (mode : Mode) (value : Value a)
    (post : Expr [mode.result selected.body selected.answer] selected.answer) :
    ((selected.capture mode).append (.push (.bind post) selected.outside)).run value =
      selected.resume mode value post := by
  simp [append_runs_in_order, Context.run, Frame.run, Selection.resume, Selection.clauseResult]

/-- An operation boundary always either exposes a selected, reconstructible
delimiter or an explicitly residual continuation. There is no third stuck case. -/
theorem operation_progress (context : Context a b) (attachment : Nat) :
    select attachment context = none ∨
    ∃ selected, select attachment context = some selected ∧
      selected.attachment = attachment ∧ selected.whole = context := by
  cases found : select attachment context with
  | none => exact Or.inl rfl
  | some selected =>
    exact Or.inr ⟨selected, rfl,
      selection_uses_capability_identity context attachment selected found,
      selection_reconstructs_context context attachment selected found⟩

/-- Runtime identity renaming does not change pure return computation. The two
maps remain distinct: fresh attachments are not region/cell identities. -/
def Frame.rename (attachments regions : Nat → Nat) : Frame a b → Frame a b
  | .bind expression => .bind expression
  | .delimiter attachment returned => .delimiter (attachments attachment) returned
  | .region owner => .region (regions owner)

def Context.rename (attachments regions : Nat → Nat) : Context a b → Context a b
  | .done => .done
  | .push frame rest => .push (frame.rename attachments regions) (rest.rename attachments regions)

theorem renamed_context_preserves_value (context : Context a b)
    (attachments regions : Nat → Nat) (value : Value a) :
    (context.rename attachments regions).run value = context.run value := by
  induction context with
  | done => rfl
  | push frame rest ih =>
    cases frame <;> simp [Context.rename, Frame.rename, Context.run, Frame.run, ih]

/-- A one-shot operation has exactly one terminal action. No action returns a
live handle. Transfer creates custody in the receiver, outside this ledger. -/
inductive Disposition where
  | resume | dispose | transfer | freeze
  deriving DecidableEq, Repr

structure Owned (input answer : Ty) where
  token : Nat
  continuation : Context input answer

def Owned.dispose (owned : Owned a b) (state : Ownership) (_action : Disposition) :
    Option Ownership := state.consume owned.token

theorem linear_disposition_preserves_ownership (owned : Owned a b)
    (state next : Ownership) (action : Disposition) (valid : state.Valid)
    (step : owned.dispose state action = some next) : next.Valid :=
  consume_preserves_ownership state next owned.token valid step

theorem linear_disposition_cannot_repeat (owned : Owned a b)
    (state next : Ownership) (first second : Disposition) (valid : state.Valid)
    (step : owned.dispose state first = some next) : owned.dispose next second = none :=
  consumed_token_cannot_resume state next owned.token valid step

theorem live_linear_disposition_progress (owned : Owned a b)
    (state : Ownership) (action : Disposition) (live : owned.token ∈ state.live) :
    ∃ next, owned.dispose state action = some next := by
  simp [Owned.dispose, Ownership.consume, live]

/-- The returned continuation is entered only after `consume` succeeds. -/
def Owned.resume (owned : Owned a b) (state : Ownership) (argument : Value a)
    (caller : Context b c) : Option (Ownership × Value c) := do
  let next ← owned.dispose state .resume
  return (next, (owned.continuation.append caller).run argument)

theorem resume_consumes_before_returning_to_clause (owned : Owned a b)
    (state next : Ownership) (argument : Value a) (caller : Context b c)
    (result : Value c) (valid : state.Valid)
    (step : owned.resume state argument caller = some (next, result)) :
    next.Valid ∧ owned.dispose next .resume = none ∧
      result = caller.run (owned.continuation.run argument) := by
  cases consume : owned.dispose state .resume with
  | none => simp [Owned.resume, consume] at step
  | some consumed =>
    simp [Owned.resume, consume] at step
    rcases step with ⟨rfl, rfl⟩
    exact ⟨linear_disposition_preserves_ownership owned state consumed .resume valid consume,
      linear_disposition_cannot_repeat owned state consumed .resume .resume valid consume,
      append_runs_in_order owned.continuation caller argument⟩

end BoundaryV2.Control
