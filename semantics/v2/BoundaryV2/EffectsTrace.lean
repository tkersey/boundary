import BoundaryV2.EffectsIdentity
import BoundaryV2.EffectsLowering

namespace BoundaryV2.Effects

open Core Control

/-- `drive` remains a state-sampling trace. Event traces instead record a newly
exposed request/result, or an external disposition. Polling a parked machine
is not another request. Equal payloads from distinct operations are not deduped. -/
def eventAfter (before : Machine A outside result) (input : Input)
    (next : Machine A outside result) : Option (Observation result) :=
  match input, before.status with
  | .internal, .running _ => observe next
  | .dispose, .pending _ => observe next
  | .transfer, .pending _ => observe next
  | _, _ => none

def driveEvents (eval : Evaluator A) (machine : Machine A outside result) :
    List Input → Option (Machine A outside result × List (Observation result))
  | [] => some (machine, [])
  | input :: inputs => do
    let next ← transition eval machine input
    let (last, trace) ← driveEvents eval next inputs
    return (last, (eventAfter machine input next).toList ++ trace)

theorem parked_internal_is_silent (eval : Evaluator A) (machine : Machine A outside result)
    (parked : observe machine ≠ none) (inputs : List Input) :
    driveEvents eval machine (.internal :: inputs) = driveEvents eval machine inputs := by
  cases state : machine.status with
  | running => simp [observe, state] at parked
  | pending | returned | disposed | transferred =>
    simp [driveEvents, transition, tick, state, eventAfter]
    cases driveEvents eval machine inputs <;> rfl

theorem parked_polling_preserves_event_trace (eval : Evaluator A) (machine : Machine A outside result)
    (parked : observe machine ≠ none) (count : Nat) (inputs : List Input) :
    driveEvents eval machine (List.replicate count .internal ++ inputs) = driveEvents eval machine inputs := by
  induction count with
  | zero => rfl
  | succ count ih =>
    simpa only [List.replicate_succ, List.cons_append,
      parked_internal_is_silent eval machine parked] using ih

theorem map_preserves_events (translate : Translation A B) (before next : Machine A outside result)
    (input : Input) :
    eventAfter (before.map translate) input (next.map translate) = eventAfter before input next := by
  cases input <;> cases state : before.status <;>
    simp only [eventAfter, Machine.map, Status.map, state] <;>
    first | rfl | exact map_preserves_observation translate next

theorem map_preserves_event_trace (translate : Translation A B) (source : Evaluator A) (target : Evaluator B)
    (compatible : PreservesEvaluation translate source target) (machine : Machine A outside result) (inputs : List Input) :
    driveEvents target (machine.map translate) inputs =
      (driveEvents source machine inputs).map (fun (last, trace) => (last.map translate, trace)) := by
  induction inputs generalizing machine with
  | nil => rfl
  | cons input inputs ih =>
    simp only [driveEvents, map_preserves_transition translate source target compatible]
    cases step : transition source machine input with
    | none => rfl
    | some next =>
      change (do
        let pair ← driveEvents target (next.map translate) inputs
        pure (pair.1, (eventAfter (machine.map translate) input (next.map translate)).toList ++ pair.2)) =
        (do
          let pair ← driveEvents source next inputs
          pure (pair.1, (eventAfter machine input next).toList ++ pair.2)).map
            (fun (pair : Machine A outside result × List (Observation result)) => (pair.1.map translate, pair.2))
      rw [ih, map_preserves_events]
      cases driveEvents source next inputs <;> rfl

theorem effectful_event_trace_simulation (machine : Machine Expr outside result) (inputs : List Input) :
    driveEvents evaluateBlock (compileMachine machine) inputs =
      (driveEvents Expr.eval machine inputs).map (fun (last, trace) => (compileMachine last, trace)) :=
  map_preserves_event_trace compileAtom Expr.eval evaluateBlock compile_atom_preserves_evaluation machine inputs

theorem map_preserves_stack_bound (translate : Translation A B) (stack : Stack A r a s b) (fresh : Nat) :
    (stack.map translate).Below fresh ↔ stack.Below fresh := by
  induction stack using Stack.rec
    (motive_1 := fun _ _ _ _ frame => (frame.map translate).Below fresh ↔ frame.Below fresh) with
  | bind | delimiter | region | post | done => rfl
  | «repeat» template heap arguments acc fold env ih => exact ih
  | push frame rest ihFrame ihRest => simp only [Stack.map, Stack.Below, ihFrame, ihRest]

theorem map_preserves_attachment_bound (translate : Translation A B) (machine : Machine A outside result) :
    (machine.map translate).AttachmentsBounded ↔ machine.AttachmentsBounded := by
  cases state : machine.status with
  | running position =>
    rcases position with ⟨regions, input, focus, heap, stack⟩
    cases focus <;>
      simp [Machine.AttachmentsBounded, Machine.map, Status.map, state, Status.Below,
        Position.map, Focus.map, Focus.Below, map_preserves_stack_bound]
  | pending | returned | disposed | transferred =>
    simp [Machine.AttachmentsBounded, Machine.map, Status.map, state, Status.Below,
      Pending.map, map_preserves_stack_bound]

theorem drive_preserves_attachment_bound (eval : Evaluator A) (machine last : Machine A outside result)
    (inputs : List Input) (trace : List (Observation result)) (bound : machine.AttachmentsBounded)
    (run : drive eval machine inputs = some (last, trace)) : last.AttachmentsBounded := by
  induction inputs generalizing machine last trace with
  | nil => simp [drive] at run; exact run.1 ▸ bound
  | cons input inputs ih =>
    cases step : transition eval machine input with
    | none => simp [drive, step] at run
    | some next =>
      cases later : drive eval next inputs with
      | none => simp [drive, step, later] at run
      | some pair =>
        rcases pair with ⟨finalState, finalTrace⟩
        simp [drive, step, later] at run
        exact run.1 ▸ ih next finalState finalTrace
          (transition_preserves_attachment_bound eval machine next input bound step) later

theorem event_drive_preserves_invariants (eval : Evaluator A) (machine last : Machine A outside result)
    (inputs : List Input) (trace : List (Observation result))
    (valid : machine.Valid) (bound : machine.AttachmentsBounded)
    (run : driveEvents eval machine inputs = some (last, trace)) :
    last.Valid ∧ last.AttachmentsBounded := by
  induction inputs generalizing machine last trace with
  | nil => simp [driveEvents] at run; exact run.1 ▸ And.intro valid bound
  | cons input inputs ih =>
    cases step : transition eval machine input with
    | none => simp [driveEvents, step] at run
    | some next =>
      cases later : driveEvents eval next inputs with
      | none => simp [driveEvents, step, later] at run
      | some pair =>
        rcases pair with ⟨finalState, finalTrace⟩
        simp [driveEvents, step, later] at run
        exact run.1 ▸ ih next finalState finalTrace
          (transition_preserves_invariants eval machine next input valid step)
          (transition_preserves_attachment_bound eval machine next input bound step) later

end BoundaryV2.Effects
