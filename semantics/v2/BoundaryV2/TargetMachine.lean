import BoundaryV2.TargetEffects

namespace BoundaryV2.Profile.Target.Machine

def executeTerminator (context : Context) (state : State context.program) (control : Graph.Control)
    (block : Block) (values : List Graph.Value) : Except Invalid (Transition context.program) := do
  match block.terminator with
  | .returnValue selected => returnTo state control.parent (← slot values selected)
  | .fail selected => return ⟨← fail state (← slot values selected) control values block.instructions, []⟩
  | .jump edge => return ⟨← jump state control edge values, []⟩
  | .yieldValue edge =>
    let state ← jump state control edge values
    return ⟨{ state with status := .yielded }, [.yielded]⟩
  | .branch condition yes no =>
    let condition ← slot values condition
    require (context.program.schemas[condition.schema.value]? == some .boolean) .type
    return ⟨← jump state control (if (← natural state condition) == 1 then yes else no) values, []⟩
  | .switchVariant selected cases =>
    let (state, tag, fields) ← splitAggregate state (← slot values selected)
    let edge ← fromOption cases[tag]? .type
    let [payload] := fields | throw .type
    return ⟨← jump state control edge values (some payload), []⟩
  | .unpackProduct selected target argumentSlots =>
    let (state, _, fields) ← splitAggregate state (← slot values selected)
    let arguments ← slots values argumentSlots
    return ⟨installControl state { control with block := target, arguments := fields ++ arguments }, []⟩
  | .call function arguments next => return ⟨← call state control function arguments next values, []⟩
  | .apply computation argumentSlots _ =>
    let body ← slot values computation
    let arguments ← slots values argumentSlots
    let (state, after) ← continuation state control values
    return ⟨← applyComputation state body arguments (some after) control.evidence control.region, []⟩
  | .perform operation => perform context state control operation values
  | .handle handler body arguments fields _ => return ⟨← installHandler state control handler body fields arguments values, []⟩
  | .resumeValue resumption argument _ => return ⟨← resumeValue state control resumption argument values, []⟩
  | .resumeWith resumption argument handler fields _ => return ⟨← resumeWith state control resumption argument handler fields values, []⟩
  | .resumeComputation resumption computation _ => return ⟨← resumeComputation state control resumption computation values, []⟩
  | .withRegion descriptor body arguments _ => return ⟨← withRegion state control descriptor body arguments values, []⟩
  | .protect body cleanup arguments resource loan _ => return ⟨← protect state control body cleanup arguments resource loan values, []⟩
  | .dispose resumption _ => return ⟨← dispose state control resumption values, []⟩
  | .forward _ => throw .type

/-- One target tick executes one BPI2 block or one unwind rule. Program
recursion uses successor states; it has no execution-fuel parameter. -/
def tick (context : Context) (state : State context.program) : Except Invalid (Transition context.program) := do
  if state.result.isSome then return ⟨state, []⟩
  match state.status with
  | .parked | .yielded => return ⟨state, []⟩
  | .unwinding => unwindStep state
  | .active =>
    let control ← currentControl state
    let block ← fromOption context.program.blocks[control.block.value]? .reference
    match ← evaluateBlock context state control with
    | .complete state values => executeTerminator context state control block values
    | .failed state failure values instructions => return ⟨← fail state failure control values instructions, []⟩

inductive Action where
  | continueYield
  | response : RequestOccurrence → SemanticValue → Action
  | cancel : Protocol.Reason → Action

def external (context : Context) (state : State context.program) (action : Action) :
    Except Invalid (Transition context.program) := do
  require state.result.isNone .inactive
  match action with
  | .continueYield =>
    require (state.status == .yielded) .inactive
    return ⟨{ state with status := .active }, []⟩
  | .response occurrence response =>
    require (state.status == .parked && state.pendingOccurrence == some occurrence) .inactive
    let reference ← fromOption state.roots.pending .inactive
    let .pending effect _ saved _ ← fromOption (state.store.lookup reference) .reference | throw .type
    let effect ← fromOption context.program.effects[effect.value]? .reference
    require (response.schema == effect.result && Profile.Value.externalValid context.program.schemas response) .type
    let (state, value) ← materialize state response
    let state := { state with status := .active, pendingOccurrence := none, roots := { state.roots with pending := none } }
    return ⟨← resumeContinuation state saved value, [.responseAccepted occurrence response]⟩
  | .cancel reason =>
    let next ← cancel state reason
    let next := if next.status == .yielded then { next with status := .active } else next
    let events := match state.pendingOccurrence with
      | some occurrence => if next.status == .parked && next.raw != state.raw then [.requestRebound occurrence] else []
      | none => []
    return ⟨next, events⟩

structure Attempt (program : Program) where
  state : State program
  events : List Event
  rejection : Option Invalid

def attempt (context : Context) (state : State context.program) (action : Action) : Attempt context.program :=
  match external context state action with
  | .ok transition => ⟨transition.state, transition.events, none⟩
  | .error error => ⟨state, [], some error⟩

theorem rejected_action_preserves_state_and_emits_no_event (context : Context) (state : State context.program)
    (action : Action) (error : Invalid) (rejected : external context state action = .error error) :
    (attempt context state action).state = state ∧ (attempt context state action).events = [] := by
  simp [attempt, rejected]

theorem terminal_internal_poll_has_no_semantic_event (context : Context) (state : State context.program)
    (terminal : state.result.isSome = true) : tick context state = .ok ⟨state, []⟩ := by
  simp [tick, terminal]
  rfl

theorem parked_internal_poll_has_no_semantic_event (context : Context) (state : State context.program)
    (parked : state.status = .parked) : tick context state = .ok ⟨state, []⟩ := by
  cases terminal : state.result.isSome <;> simp [tick, terminal, parked] <;> rfl

inductive Steps (context : Context) : State context.program → List Event → State context.program → Prop where
  | refl : Steps context state [] state
  | tick : Machine.tick context state = .ok transition → Steps context transition.state later final →
      Steps context state (transition.events ++ later) final
  | external : Machine.external context state action = .ok transition → Steps context transition.state later final →
      Steps context state (transition.events ++ later) final

theorem trace_concatenation_matches_segment_composition (context : Context)
    (start middle final : State context.program) (early later : List Event)
    (first : Steps context start early middle) (second : Steps context middle later final) :
    Steps context start (early ++ later) final := by
  induction first with
  | refl => simpa using second
  | tick step _ induction => simpa [List.append_assoc] using Steps.tick step (induction second)
  | external step _ induction => simpa [List.append_assoc] using Steps.external step (induction second)

theorem inserting_parked_poll_preserves_semantic_trace (context : Context) (state final : State context.program) (events : List Event)
    (parked : state.status = .parked) (rest : Steps context state events final) :
    Steps context state events final := by
  simpa using Steps.tick (parked_internal_poll_has_no_semantic_event context state parked) rest

end BoundaryV2.Profile.Target.Machine
