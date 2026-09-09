import BoundaryV2.Effects

namespace BoundaryV2.Effects

open Core Control

abbrev Translation (A B : Atom) := {ctx : List Ty} → {t : Ty} → A ctx t → B ctx t

def Plan.map (translate : Translation A B) : Plan A ctx body answer → Plan B ctx body answer
  | .dispose expression => .dispose (translate expression)
  | .once mode argument post => .once mode (translate argument) (translate post)
  | .multi mode arguments seed fold => .multi mode (arguments.map translate) (translate seed) (translate fold)

def Handler.map (translate : Translation A B) (handler : Handler A ctx a b) : Handler B ctx a b :=
  ⟨translate handler.returned, handler.clause.map translate⟩

def Flow.map (translate : Translation A B) : Flow A regions caps ctx a → Flow B regions caps ctx a
  | .pure expression => .pure (translate expression)
  | .bind first after => .bind (first.map translate) (after.map translate)
  | .branch condition yes no => .branch (translate condition) (yes.map translate) (no.map translate)
  | .perform capability argument => .perform capability (translate argument)
  | .handle handler body => .handle (handler.map translate) (body.map translate)
  | .region initial body => .region (translate initial) (body.map translate)
  | .read reference => .read reference
  | .write reference value => .write reference (translate value)

mutual
  def Frame.map (translate : Translation A B) : Frame A r a s b → Frame B r a s b
    | .bind body env caps => .bind (body.map translate) env caps
    | .delimiter identity handler env => .delimiter identity (handler.map translate) env
    | .region => .region
    | .post expression env => .post (translate expression) env
    | .repeat template heap arguments acc fold env =>
      .repeat (template.map translate) heap arguments acc (translate fold) env

  def Stack.map (translate : Translation A B) : Stack A r a s b → Stack B r a s b
    | .done => .done
    | .push frame rest => .push (frame.map translate) (rest.map translate)
end

def Selected.map (translate : Translation A B) (selected : Selected A r a s b) : Selected B r a s b :=
  ⟨selected.atRegion, selected.body, selected.answer, selected.ctx, selected.identity,
    selected.inside.map translate, selected.handler.map translate, selected.env,
    selected.outsideStack.map translate⟩

def Focus.map (translate : Translation A B) : Focus A regions a → Focus B regions a
  | .code body env caps => .code (body.map translate) env caps
  | .value item => .value item

def Position.map (translate : Translation A B) (position : Position A outside result) :
    Position B outside result :=
  ⟨position.regions, position.input, position.focus.map translate, position.heap, position.stack.map translate⟩

def Pending.map (translate : Translation A B) (pending : Pending A outside result) : Pending B outside result :=
  ⟨pending.regions, pending.identity, pending.payload, pending.token, pending.heap, pending.stack.map translate⟩

def Status.map (translate : Translation A B) : Status A outside result → Status B outside result
  | .running position => .running (position.map translate)
  | .pending item => .pending (item.map translate)
  | .returned value => .returned value
  | .disposed => .disposed
  | .transferred item => .transferred (item.map translate)

def Machine.map (translate : Translation A B) (machine : Machine A outside result) : Machine B outside result :=
  ⟨machine.ownership, machine.freshAttachment, machine.status.map translate⟩

theorem map_preserves_composition (translate : Translation A B)
    (first : Stack A r a s b) (after : Stack A s b t c) :
    (first.append after).map translate = (first.map translate).append (after.map translate) := by
  induction first using Stack.spine_induction with
  | done => rfl
  | push frame rest ih => exact congrArg (Stack.push (frame.map translate)) (ih after)

theorem map_preserves_outer_heap (translate : Translation A B) (stack : Stack A r a s b) (heap : Heap r) :
    (stack.map translate).outerHeap heap = stack.outerHeap heap := by
  induction stack using Stack.spine_induction with
  | done => rfl
  | push frame rest ih =>
    cases frame with
    | bind | delimiter | post | «repeat» => exact ih heap
    | region => cases heap; exact ih _

theorem map_preserves_freezing (translate : Translation A B) (stack : Stack A r a s b)
    (frozen : Heap r) :
    (stack.map translate).freezeHeap frozen = stack.freezeHeap frozen := by
  induction stack using Stack.spine_induction with
  | done => rfl
  | push frame rest ih =>
    cases frame with
    | bind | delimiter | post | «repeat» => exact ih frozen
    | region => cases frozen; exact congrArg (LocalHeap.cons _) (ih _)

theorem map_preserves_attachments (translate : Translation A B) (stack : Stack A r a s b) :
    (stack.map translate).attachments = stack.attachments := by
  induction stack using Stack.spine_induction with
  | done => rfl
  | push frame rest ih =>
    cases frame with
    | bind | region | post | «repeat» => exact ih
    | delimiter => exact congrArg (List.cons _) ih

theorem stack_map_commutes_with_renaming (translate : Translation A B)
    (rename : Nat → Nat) (stack : Stack A r a s b) :
    (stack.rename rename).map translate = (stack.map translate).rename rename := by
  induction stack using Stack.rec
    (motive_1 := fun _ _ _ _ frame => (frame.rename rename).map translate = (frame.map translate).rename rename) with
  | bind | delimiter | region | post | done => rfl
  | «repeat» template heap arguments acc fold env ih => simp only [Frame.rename, Frame.map, ih]
  | push frame rest ihFrame ihRest => simp only [Stack.rename, Stack.map, ihFrame, ihRest]

theorem map_preserves_activation (translate : Translation A B) (stack : Stack A r a s b) (fresh : Nat) :
    (stack.map translate).activate fresh = ((stack.activate fresh).1.map translate, (stack.activate fresh).2) := by
  simp [Stack.activate, map_preserves_attachments, stack_map_commutes_with_renaming]

theorem map_preserves_selection (translate : Translation A B) (stack : Stack A r a s b) (identity : Nat) :
    select identity (stack.map translate) = (select identity stack).map (Selected.map translate) := by
  induction stack using Stack.spine_induction with
  | done => rfl
  | push frame rest ih =>
    cases frame with
    | delimiter actual handler env =>
      by_cases same : identity = actual
      · simp [Stack.map, Frame.map, select, same, Selected.map]
      · simp [Stack.map, Frame.map, select, same, ih,
          Option.map_map, Function.comp_def, Selected.map, Selected.prepend]
    | bind | region | post | «repeat» =>
      simp [Stack.map, Frame.map, select, ih,
        Option.map_map, Function.comp_def, Selected.map, Selected.prepend]

theorem map_preserves_capture (translate : Translation A B) (selected : Selected A r a s b) (mode : Mode) :
    (selected.map translate).capture mode = (selected.capture mode).map translate := by
  cases mode with
  | deep => simp [Selected.capture, Selected.map, map_preserves_composition, Stack.map, Frame.map]
  | shallow => rfl

def PreservesEvaluation (translate : Translation A B) (source : Evaluator A) (target : Evaluator B) : Prop :=
  ∀ ctx t (expression : A ctx t) (env : Values ctx), target (translate expression) env = source expression env

theorem map_preserves_return_step (translate : Translation A B) (source : Evaluator A) (target : Evaluator B)
    (compatible : PreservesEvaluation translate source target) (machine : Machine A outside result)
    (value : Value a) (heap : Heap regions) (stack : Stack A regions a outside result) :
    returnValue target (machine.map translate) value heap (stack.map translate) =
      (returnValue source machine value heap stack).map translate := by
  unfold PreservesEvaluation at compatible
  cases stack with
  | done => rfl
  | push frame rest =>
    cases frame with
    | bind => rfl
    | delimiter =>
      simp only [returnValue, Stack.map, Frame.map, Handler.map, compatible, Machine.map,
        Status.map, Position.map, Focus.map]
    | region => cases heap; rfl
    | post =>
      simp only [returnValue, Stack.map, Frame.map, compatible, Machine.map,
        Status.map, Position.map, Focus.map]
    | «repeat» template frozen arguments acc fold env =>
      cases arguments <;>
        simp only [returnValue, Stack.map, Frame.map, compatible, Machine.map,
          Status.map, Position.map, Focus.map, map_preserves_activation,
          map_preserves_composition]

theorem map_preserves_dispatch (translate : Translation A B) (source : Evaluator A) (target : Evaluator B)
    (compatible : PreservesEvaluation translate source target) (machine : Machine A outside result)
    (payload : Nat) (heap : Heap regions) (selected : Selected A regions .number outside result) :
    dispatch target (machine.map translate) payload heap (selected.map translate) =
      (dispatch source machine payload heap selected).map translate := by
  unfold PreservesEvaluation at compatible
  simp only [dispatch, map_preserves_capture]
  cases clause : selected.handler.clause with
  | dispose | once =>
    simp only [Selected.map, Handler.map, clause, Plan.map, compatible,
      map_preserves_outer_heap, Machine.map, Status.map,
      Position.map, Focus.map, map_preserves_composition, Stack.map, Frame.map]
  | multi mode arguments seed fold =>
    simp only [Selected.map, Handler.map, clause, Plan.map, List.map_map,
      Function.comp_def, compatible, map_preserves_outer_heap]
    split <;>
      simp only [Machine.map, Status.map, Position.map, Focus.map, map_preserves_composition,
        Stack.map, Frame.map, map_preserves_activation,
        map_preserves_freezing]

theorem map_preserves_tick (translate : Translation A B) (source : Evaluator A) (target : Evaluator B)
    (compatible : PreservesEvaluation translate source target) (machine : Machine A outside result) :
    tick target (machine.map translate) = (tick source machine).map translate := by
  have evaluation := compatible
  unfold PreservesEvaluation at compatible
  cases state : machine.status with
  | pending | returned | disposed | transferred => simp [tick, Machine.map, Status.map, state]
  | running position =>
    rcases position with ⟨regions, input, focus, heap, stack⟩
    cases focus with
    | value value =>
      simpa only [tick, Machine.map, Status.map, state, Position.map, Focus.map] using
        map_preserves_return_step translate source target evaluation machine value heap stack
    | code expression env caps =>
      cases expression with
      | pure | bind | handle | region | read | write =>
        simp only [tick, Machine.map, Status.map, state, Position.map, Focus.map,
          Flow.map, Frame.map, Stack.map, compatible]
      | branch condition yes no =>
        simp only [tick, Machine.map, Status.map, state, Position.map, Focus.map,
          Flow.map, compatible]
        split <;> rfl
      | perform index payload =>
        simp only [tick, Machine.map, Status.map, state, Position.map, Focus.map,
          Flow.map, compatible, map_preserves_selection]
        cases found : select caps[index] stack with
        | none => rfl
        | some selected =>
          simpa only [Machine.map, state, Status.map, Position.map, Focus.map, Flow.map, Option.map] using
            map_preserves_dispatch translate source target evaluation machine (number (source payload env)) heap selected

theorem map_preserves_transition (translate : Translation A B) (source : Evaluator A) (target : Evaluator B)
    (compatible : PreservesEvaluation translate source target) (machine : Machine A outside result) (input : Input) :
    transition target (machine.map translate) input = (transition source machine input).map (Machine.map translate) := by
  cases input with
  | internal => simp [transition, map_preserves_tick translate source target compatible]
  | resume | dispose | transfer =>
    cases state : machine.status <;>
      simp only [transition, Machine.map, Status.map, state, Pending.map] <;> try rfl
    next pending =>
      cases machine.ownership.consume pending.token <;> rfl

theorem map_preserves_observation (translate : Translation A B) (machine : Machine A outside result) :
    observe (machine.map translate) = observe machine := by
  cases state : machine.status <;> simp [observe, Machine.map, Status.map, Pending.map, state]

theorem map_preserves_ownership (translate : Translation A B) (machine : Machine A outside result) :
    (machine.map translate).Valid ↔ machine.Valid := by
  cases state : machine.status <;> simp [Machine.Valid, Machine.map, Status.map, Pending.map, state]

/-- A finite external script is a proof/observation horizon. The machine step
does not read this list or have any execution limit. Invalid actions reject. -/
def drive (eval : Evaluator A) (machine : Machine A outside result) :
    List Input → Option (Machine A outside result × List (Observation result))
  | [] => some (machine, [])
  | input :: inputs => do
    let next ← transition eval machine input
    let (last, trace) ← drive eval next inputs
    return (last, (observe next).toList ++ trace)

theorem drive_preserves_invariants (eval : Evaluator A) (machine last : Machine A outside result)
    (inputs : List Input) (trace : List (Observation result)) (valid : machine.Valid)
    (run : drive eval machine inputs = some (last, trace)) : last.Valid := by
  induction inputs generalizing machine last trace with
  | nil => simp [drive] at run; exact run.1 ▸ valid
  | cons input inputs ih =>
    cases step : transition eval machine input with
    | none => simp [drive, step] at run
    | some next =>
      cases later : drive eval next inputs with
      | none => simp [drive, step, later] at run
      | some pair =>
        rcases pair with ⟨finalState, finalTrace⟩
        simp [drive, step, later] at run
        exact run.1 ▸ ih next finalState finalTrace (transition_preserves_invariants eval machine next input valid step) later

theorem map_preserves_observable_trace (translate : Translation A B) (source : Evaluator A) (target : Evaluator B)
    (compatible : PreservesEvaluation translate source target) (machine : Machine A outside result) (inputs : List Input) :
    drive target (machine.map translate) inputs =
      (drive source machine inputs).map (fun (last, trace) => (last.map translate, trace)) := by
  induction inputs generalizing machine with
  | nil => rfl
  | cons input inputs ih =>
    simp only [drive, map_preserves_transition translate source target compatible]
    cases step : transition source machine input with
    | none => rfl
    | some next =>
      change (do
        let pair ← drive target (next.map translate) inputs
        pure (pair.1, (observe (next.map translate)).toList ++ pair.2)) =
        (do
          let pair ← drive source next inputs
          pure (pair.1, (observe next).toList ++ pair.2)).map
            (fun (pair : Machine A outside result × List (Observation result)) => (pair.1.map translate, pair.2))
      rw [ih, map_preserves_observation]
      cases drive source next inputs <;> rfl

/-- Target atoms are explicit first-order instruction blocks. Source lexical
bind is eliminated by Core.compile into enter/leave instructions. The control
algebra above is common to both instantiations; there are no source Expr
values or native functions inside a compiled Flow, frame, or template. -/
abbrev Block (ctx : List Ty) (t : Ty) := Code ctx ctx [] [t]

def evaluateBlock (block : Block ctx t) (env : Values ctx) : Value t :=
  match (block.run env .nil).2 with
  | .cons value .nil => value

def compileAtom : Translation Expr Block := fun expression => Core.compile expression []

theorem compile_atom_preserves_evaluation : PreservesEvaluation compileAtom Expr.eval evaluateBlock := by
  intro ctx t expression env
  simp [compileAtom, evaluateBlock, compile_preserves_value_and_scope]

def compileFlow (body : Flow Expr regions caps ctx a) : Flow Block regions caps ctx a := body.map compileAtom
def compileMachine (machine : Machine Expr outside result) : Machine Block outside result := machine.map compileAtom

theorem effectful_step_simulation (machine : Machine Expr outside result) (input : Input) :
    transition evaluateBlock (compileMachine machine) input =
      (transition Expr.eval machine input).map compileMachine :=
  map_preserves_transition compileAtom Expr.eval evaluateBlock compile_atom_preserves_evaluation machine input

/-- Equality of the complete observable trace implies weak trace agreement
after discarding internal transitions. It covers effectful bind, branches,
deep/shallow capture, both non-tail callers, repeated template activation,
region reads/writes, and residual linear resume/dispose/transfer. -/
theorem effectful_trace_simulation (machine : Machine Expr outside result) (inputs : List Input) :
    drive evaluateBlock (compileMachine machine) inputs =
      (drive Expr.eval machine inputs).map (fun (last, trace) => (compileMachine last, trace)) :=
  map_preserves_observable_trace compileAtom Expr.eval evaluateBlock compile_atom_preserves_evaluation machine inputs

end BoundaryV2.Effects
