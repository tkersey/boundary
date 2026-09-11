import BoundaryV2.EffectsLowering

namespace BoundaryV2.Effects

open Core

/-- Occurrence identities are logical custody allocations, not payload hashes.
Equal requests at different transitions therefore remain distinct events. -/
inductive Event (result : Ty) where
  | requestOpened (occurrence attachment payload : Nat)
  | resultAccepted (occurrence value : Nat)
  | disposed (occurrence : Nat)
  | transferred (occurrence attachment payload : Nat)
  | completed (value : Value result)

def emittedEvents (before : Machine A outside result) (input : Input)
    (after : Machine A outside result) : List (Event result) :=
  match input with
  | .internal =>
    match before.status, after.status with
    | .running _, .pending pending =>
      [.requestOpened pending.token pending.identity pending.payload]
    | .running _, .returned value => [.completed value]
    | _, _ => []
  | .resume value =>
    match before.status with
    | .pending pending => [.resultAccepted pending.token value]
    | _ => []
  | .dispose =>
    match before.status with
    | .pending pending => [.disposed pending.token]
    | _ => []
  | .transfer =>
    match before.status with
    | .pending pending => [.transferred pending.token pending.identity pending.payload]
    | _ => []

structure Attempt (A : Atom) (outside : Nat) (result : Ty) where
  accepted : Bool
  state : Machine A outside result
  events : List (Event result)

/-- Rejection carries the unchanged input state and no new events. -/
def attempt (eval : Evaluator A) (machine : Machine A outside result) (input : Input) :
    Attempt A outside result :=
  match transition eval machine input with
  | none => ⟨false, machine, []⟩
  | some next => ⟨true, next, emittedEvents machine input next⟩

theorem rejected_action_preserves_state_and_emits_no_event (eval : Evaluator A)
    (machine : Machine A outside result) (input : Input)
    (rejected : transition eval machine input = none) :
    attempt eval machine input = ⟨false, machine, []⟩ := by
  simp [attempt, rejected]

theorem parked_internal_poll_has_no_semantic_event (eval : Evaluator A)
    (machine : Machine A outside result) (pending : Pending A outside result)
    (parked : machine.status = .pending pending) :
    attempt eval machine .internal = ⟨true, machine, []⟩ := by
  simp [attempt, transition, tick, emittedEvents, parked]

theorem terminal_internal_poll_has_no_semantic_event (eval : Evaluator A)
    (machine : Machine A outside result) (terminal : ∀ position, machine.status ≠ .running position) :
    attempt eval machine .internal = ⟨true, machine, []⟩ := by
  cases state : machine.status with
  | running position => exact False.elim (terminal position state)
  | pending | returned | disposed | transferred =>
    simp [attempt, transition, tick, emittedEvents, state]

/-- The old observer samples states, including parked states repeatedly. -/
abbrev driveStateSamples := @drive

/-- A script horizon belongs to observation, not to the machine semantics. -/
def driveEvents (eval : Evaluator A) (machine : Machine A outside result) :
    List Input → Option (Machine A outside result × List (Event result))
  | [] => some (machine, [])
  | input :: inputs => do
    let step := attempt eval machine input
    if !step.accepted then none else do
      let (final, events) ← driveEvents eval step.state inputs
      return (final, step.events ++ events)

theorem empty_script_emits_no_events (eval : Evaluator A) (machine : Machine A outside result) :
    driveEvents eval machine [] = some (machine, []) := rfl

theorem inserting_parked_polls_preserves_semantic_trace (eval : Evaluator A)
    (machine : Machine A outside result) (pending : Pending A outside result)
    (parked : machine.status = .pending pending) (inputs : List Input) :
    driveEvents eval machine (.internal :: inputs) = driveEvents eval machine inputs := by
  simp [driveEvents, parked_internal_poll_has_no_semantic_event eval machine pending parked]
  cases driveEvents eval machine inputs <;> rfl

theorem trace_concatenation_matches_segment_composition (eval : Evaluator A)
    (machine : Machine A outside result) (first second : List Input) :
    driveEvents eval machine (first ++ second) = do
      let (middle, firstEvents) ← driveEvents eval machine first
      let (final, secondEvents) ← driveEvents eval middle second
      return (final, firstEvents ++ secondEvents) := by
  induction first generalizing machine with
  | nil =>
    simp [driveEvents]
    cases driveEvents eval machine second <;> rfl
  | cons input inputs ih =>
    simp only [List.cons_append, driveEvents]
    split
    next rejected => rfl
    next accepted =>
      rw [ih]
      cases firstRun : driveEvents eval (attempt eval machine input).state inputs with
      | none => simp
      | some pair =>
        rcases pair with ⟨middle, events⟩
        cases secondRun : driveEvents eval middle second <;> simp [secondRun, List.append_assoc]

theorem map_preserves_event_emission (translate : Translation A B)
    (before after : Machine A outside result) (input : Input) :
    emittedEvents (before.map translate) input (after.map translate) = emittedEvents before input after := by
  cases input <;> cases old : before.status <;> cases next : after.status <;>
    simp only [emittedEvents, Machine.map, Status.map, Pending.map, old, next]

theorem atom_lowering_preserves_event_step (translate : Translation A B)
    (source : Evaluator A) (target : Evaluator B) (compatible : PreservesEvaluation translate source target)
    (machine : Machine A outside result) (input : Input) :
    attempt target (machine.map translate) input =
      let result := attempt source machine input
      ⟨result.accepted, result.state.map translate, result.events⟩ := by
  unfold attempt
  rw [map_preserves_transition translate source target compatible]
  cases step : transition source machine input <;> simp [map_preserves_event_emission]

theorem atom_lowering_preserves_event_trace (translate : Translation A B)
    (source : Evaluator A) (target : Evaluator B) (compatible : PreservesEvaluation translate source target)
    (machine : Machine A outside result) (inputs : List Input) :
    driveEvents target (machine.map translate) inputs =
      (driveEvents source machine inputs).map fun output => (output.1.map translate, output.2) := by
  induction inputs generalizing machine with
  | nil => rfl
  | cons input inputs ih =>
    simp only [driveEvents, atom_lowering_preserves_event_step translate source target compatible]
    split
    next rejected => rfl
    next accepted =>
      rw [ih]
      cases driveEvents source (attempt source machine input).state inputs <;> rfl

def repeatedRequestBody : Flow Expr 0 1 [] .number :=
  .bind (.perform 0 (.literal (.number 5))) (.perform 0 (.literal (.number 5)))

def repeatedRequestInputs : List Input :=
  [.internal, .internal, .resume 5, .internal, .internal, .resume 5, .internal]

theorem distinct_equal_payload_requests_are_not_collapsed :
    (driveEvents Expr.eval (initial repeatedRequestBody #[7].toVector) repeatedRequestInputs).map Prod.snd =
      some [.requestOpened 0 7 5, .resultAccepted 0 5, .requestOpened 1 7 5,
        .resultAccepted 1 5, .completed (.number 5)] := rfl

end BoundaryV2.Effects
