import BoundaryV2.TargetInvocation

namespace BoundaryV2.Profile.Target.Boundary

open Machine (Invalid require)

def stopped (state : Machine.State program) : Bool :=
  state.result.isSome || state.status == .parked || state.status == .yielded

/-- Internal run paths contain actual rule applications, with neither external
actions nor parked, yielded, or terminal polling steps. -/
inductive InternalPath (context : Machine.Context) : Nat → Machine.State context.program →
    List Machine.Event → Machine.State context.program → Prop where
  | done : stopped state = true → InternalPath context 0 state [] state
  | step : stopped state = false → Machine.tick context state = .ok next →
      InternalPath context count next.state later final →
      InternalPath context (count + 1) state (next.events ++ later) final

/-- A finite internal path witness must end at an observable boundary. Its
length is evidence to check, never a fuel parameter of program semantics:
zero remaining steps at an active or unwinding state is rejection. -/
def completeInternal (context : Machine.Context) : Nat → Machine.State context.program →
    Except Invalid (Machine.Transition context.program)
  | 0, state => do
    require (stopped state) .witness
    pure ⟨state, []⟩
  | count + 1, state => do
    require (!stopped state) .witness
    let next ← Machine.tick context state
    let rest ← completeInternal context count next.state
    pure ⟨rest.state, next.events ++ rest.events⟩

theorem completeInternal_sound (context : Machine.Context) (count : Nat)
    (state : Machine.State context.program) (transition : Machine.Transition context.program)
    (accepted : completeInternal context count state = .ok transition) :
    stopped transition.state = true ∧ Machine.Steps context state transition.events transition.state := by
  induction count generalizing state transition with
  | zero =>
    cases valid : stopped state with
    | false => simp [completeInternal, require, valid, bind, Except.bind] at accepted
    | true =>
      simp [completeInternal, require, valid, bind, Except.bind] at accepted
      cases accepted
      exact ⟨valid, .refl⟩
  | succ count ih =>
    cases valid : stopped state with
    | true => simp [completeInternal, require, valid, bind, Except.bind] at accepted
    | false =>
      simp only [completeInternal, valid, Bool.not_false, require, ↓reduceIte, bind, Except.bind] at accepted
      cases atNext : Machine.tick context state with
      | error error => simp [atNext] at accepted
      | ok next =>
        simp only [atNext] at accepted
        cases atRest : completeInternal context count next.state with
        | error error => simp [atRest] at accepted
        | ok rest =>
          simp only [atRest] at accepted
          cases accepted
          exact ⟨(ih next.state rest atRest).1, .tick atNext (ih next.state rest atRest).2⟩

theorem incomplete_internal_path_rejected (context : Machine.Context) (state : Machine.State context.program)
    (active : stopped state = false) : completeInternal context 0 state = .error .witness := by
  simp [completeInternal, active, require, bind, Except.bind]

theorem completeInternal_exact_path (context : Machine.Context) (count : Nat)
    (state : Machine.State context.program) (transition : Machine.Transition context.program)
    (accepted : completeInternal context count state = .ok transition) :
    InternalPath context count state transition.events transition.state := by
  induction count generalizing state transition with
  | zero =>
    cases valid : stopped state with
    | false => simp [completeInternal, require, valid, bind, Except.bind] at accepted
    | true =>
      simp [completeInternal, require, valid, bind, Except.bind] at accepted
      cases accepted
      exact .done valid
  | succ count ih =>
    cases valid : stopped state with
    | true => simp [completeInternal, require, valid, bind, Except.bind] at accepted
    | false =>
      simp only [completeInternal, valid, Bool.not_false, require, ↓reduceIte, bind, Except.bind] at accepted
      cases atNext : Machine.tick context state with
      | error error => simp [atNext] at accepted
      | ok next =>
        simp only [atNext] at accepted
        cases atRest : completeInternal context count next.state with
        | error error => simp [atRest] at accepted
        | ok rest =>
          simp only [atRest] at accepted
          cases accepted
          exact .step valid atNext (ih next.state rest atRest)

/-- Run consumes a complete finite internal derivation after boundary controls.
No finite accepted witness can label unfinished internal work as completed. -/
def run (image : Machine.ImageContext imageBytes programWitness) (input : Protocol.Input)
    (incoming : InputWitness) (outgoing : Graph.Admission.Witness) (count : Nat) :
    Except Invalid (Observation image.context.program) := do
  require (input.mode == .run) .witness
  let prepared ← prepare image input incoming
  let transition ← completeInternal image.context count prepared.state
  let outcome ← finish image transition.state outgoing
  require (Protocol.outcomeCodec.valid outcome) .type
  pure ⟨transition.state, prepared.events ++ transition.events, outcome⟩

theorem run_has_complete_internal_derivation (image : Machine.ImageContext imageBytes programWitness)
    (input : Protocol.Input) (incoming : InputWitness) (outgoing : Graph.Admission.Witness)
    (count : Nat) (observation : Observation image.context.program)
    (accepted : run image input incoming outgoing count = .ok observation) :
    ∃ (prepared : Prepared image.context.program) (transition : Machine.Transition image.context.program),
      prepare image input incoming = .ok prepared ∧
      Machine.Steps image.context prepared.state transition.events transition.state ∧
      stopped transition.state = true ∧ observation.state = transition.state ∧
      observation.events = prepared.events ++ transition.events ∧
      finish image transition.state outgoing = .ok observation.outcome := by
  unfold run at accepted
  simp only [bind, Except.bind] at accepted
  split at accepted
  · cases accepted
  · cases preparedAt : prepare image input incoming with
    | error error => simp [preparedAt] at accepted
    | ok prepared =>
      simp only [preparedAt] at accepted
      cases transitionAt : completeInternal image.context count prepared.state with
      | error error => simp [transitionAt] at accepted
      | ok transition =>
        simp only [transitionAt] at accepted
        cases outcomeAt : finish image transition.state outgoing with
        | error error => simp [outcomeAt] at accepted
        | ok outcome =>
          simp only [outcomeAt] at accepted
          split at accepted
          · cases accepted
          · cases accepted
            exact ⟨prepared, transition, rfl, (completeInternal_sound _ _ _ _ transitionAt).2,
              (completeInternal_sound _ _ _ _ transitionAt).1, rfl, rfl, outcomeAt⟩

end BoundaryV2.Profile.Target.Boundary
