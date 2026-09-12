import BoundaryV2.TargetInstructions

namespace BoundaryV2.Profile.Target.Machine

def owned (values : List Graph.Value) : List Graph.Value :=
  values.filter (fun value => match value.body with | .owned _ => true | _ => false)

def unwindPosition (state : State program) (cursor : Option NodeId) (values : List Graph.Value) : State program :=
  let (store, current) := state.store.add (.unwind cursor values)
  { state with store := store, status := .unwinding, pendingOccurrence := none, roots := { state.roots with current := some current, pending := none, evidence := none } }

def beginUnwind (state : State program) (reason : Graph.ExitReason) (cursor stop : Option NodeId)
    (values : List Graph.Value) : State program :=
  let (store, exit) := state.store.add (.exit ⟨reason, [], none, stop, state.roots.exit, []⟩)
  unwindPosition { state with store := store, roots := { state.roots with exit := some exit } } cursor values

def outermostExitAt (store : Store schemas) : Nat → NodeId → Except Invalid (NodeId × Graph.Exit)
  | 0, _ => .error .scope
  | count + 1, reference => do
    let .exit exit ← fromOption (store.lookup reference) .reference | throw .type
    match exit.outer with
    | none => pure (reference, exit)
    | some outer => outermostExitAt store count outer

def outermostExit (state : State program) : Except Invalid (NodeId × Graph.Exit) := do
  outermostExitAt state.store (state.store.nodes.length + 1) (← fromOption state.roots.exit .inactive)

def discardedNormal (exit : Graph.Exit) : List Graph.Value :=
  exit.discarded ++ (match exit.reason with | .normal value => owned [value] | _ => [])

def rememberFailure (state : State program) (value : Graph.Value) : Except Invalid (State program) := do
  let (reference, exit) ← outermostExit state
  let next := { exit with cleanupFailures := exit.cleanupFailures ++ [value] }
  let next := match exit.reason with
    | .normal _ | .abandoned => { next with reason := .failure value, stop := none, discarded := discardedNormal exit }
    | _ => next
  replaceNode state reference (.exit next)

def borrowsOperands : Opcode → Bool
  | .variantTag | .sequenceLength | .sequenceGet => true
  | _ => false

def outstanding (values : List Graph.Value) (executed : List Instruction) : List Graph.Value :=
  let consumed := (executed.filter (fun instruction => !borrowsOperands instruction.opcode)).flatMap Instruction.operands
  owned ((values.zipIdx.filter (fun (_, index) => !consumed.contains ⟨index⟩)).map Prod.fst)

def fail (state : State program) (value : Graph.Value) (control : Graph.Control)
    (values : List Graph.Value) (executed : List Instruction) : Except Invalid (State program) := do
  require (value.schema == program.roots.failure) .type
  let state ← if state.roots.exit.isSome then rememberFailure state value else pure state
  return beginUnwind state (.failure value) control.parent none (outstanding values executed)

def cancel (state : State program) (reason : Protocol.Reason) : Except Invalid (State program) := do
  require (match reason with | .text bytes => UTF8.valid bytes | .bytes _ => true) .type
  let state ← if state.roots.exit.isNone then do
    let cursor ← match state.roots.pending with
      | none => pure state.roots.current
      | some reference => do
        let .pending _ _ continuation _ ← fromOption (state.store.lookup reference) .reference | throw .type
        pure (some continuation)
    pure (beginUnwind state .cancellation cursor none [])
  else pure state
  let (reference, exit) ← outermostExit state
  if exit.cancellation.isSome then return state
  let next := { exit with cancellation := some reason }
  let next := match exit.reason with
    | .normal _ | .abandoned => { next with reason := .cancellation, stop := none, discarded := discardedNormal exit }
    | _ => next
  replaceNode state reference (.exit next)

def cleanupReturned (state : State program) (reference : NodeId) : Except Invalid (State program) := do
  let .cleanupReturn obligation parent exit ← fromOption (state.store.lookup reference) .reference | throw .type
  let .obligation block cleanup resource status ← fromOption (state.store.lookup obligation.node) .reference | throw .type
  require (status == .running reference && cleanup.isNone && resource.isNone) .custody
  let state ← replaceNode state obligation.node (.obligation block none none .completed)
  return unwindPosition { state with roots := { state.roots with exit := some exit } } parent []

def completed (state : State program) (value : Graph.Value) : Except Invalid (Transition program) := do
  let meaning ← loadValue state.store value
  require (value.schema == program.roots.result && Profile.Value.externalValid program.schemas meaning) .type
  return ⟨{ state with result := some (.completed meaning) }, [.completed meaning]⟩

/-- Returning across empty region wrappers is a finite graph traversal. Entering
a return clause, cleanup, or saved continuation ends this transition. -/
def returnToAt : Nat → State program → Option NodeId → Graph.Value → Except Invalid (Transition program)
  | 0, _, _, _ => .error .scope
  | count + 1, state, parent, value => do
    match parent with
    | none => completed state value
    | some reference =>
      let node ← fromOption (state.store.lookup reference) .reference
      match node with
      | .regionScope _ _ next => returnToAt count state next value
      | .continuation _ => return ⟨← resumeContinuation state reference value, []⟩
      | .attachment handler _ after phase _ =>
        require (phase == .active) .inactive
        let .handler definition values evidence region ← fromOption (state.store.lookup handler) .reference | throw .type
        let definition ← fromOption program.handlers[definition.value]? .reference
        return ⟨← enter state definition.returnFunction (values ++ [value]) after evidence region, []⟩
      | .injection saved => return ⟨← resumeContinuation state saved value, []⟩
      | .protection _ _ after _ _ _ => return ⟨beginUnwind state (.normal value) (some reference) after [], []⟩
      | .cleanupReturn .. => return ⟨← cleanupReturned state reference, []⟩
      | .disposalReturn _ parent remaining => return ⟨unwindPosition state parent (owned [value] ++ remaining), []⟩
      | _ => throw .type

def returnTo (state : State program) (parent : Option NodeId) (value : Graph.Value) : Except Invalid (Transition program) :=
  returnToAt (state.store.nodes.length + 1) state parent value

def exitInformation (state : State program) (schema : SchemaId .target) (exit : Graph.Exit) :
    Except Invalid (State program × Graph.Value) := do
  let .product [primary, optional, failures] ← fromOption program.schemas[schema.value]? .type | throw .type
  let .sum [unit, errorType, reasonType, abandoned] ← fromOption program.schemas[primary.value]? .type | throw .type
  let .sum [optionalUnit, optionalReason] ← fromOption program.schemas[optional.value]? .type | throw .type
  let .sum [textType, bytesType] ← fromOption program.schemas[reasonType.value]? .type | throw .type
  require (errorType == program.roots.failure && optionalReason == reasonType && abandoned == unit && optionalUnit == unit &&
    program.schemas[unit.value]? == some .unit && program.schemas[textType.value]? == some .text &&
    program.schemas[bytesType.value]? == some .bytes && program.schemas[failures.value]? == some (.seq program.roots.failure)) .type
  let (state, unitValue) ← scalar state unit 0
  let (state, reasonValue) ← match exit.cancellation with
    | none => pure (state, unitValue)
    | some reason => do
      let (schema, tag, bytes) := match reason with
        | .text bytes => (textType, 0, bytes)
        | .bytes bytes => (bytesType, 1, bytes)
      let (state, payload) ← materialize state (.blob schema bytes)
      aggregate state reasonType tag [payload]
  let (tag, payload) := match exit.reason with
    | .normal _ => (0, unitValue)
    | .failure failure => (1, failure)
    | .cancellation => (2, reasonValue)
    | .abandoned => (3, unitValue)
  let (state, primary) ← aggregate state primary tag [payload]
  let (state, optional) ← aggregate state optional (if exit.cancellation.isSome then 1 else 0) [reasonValue]
  let (state, failures) ← aggregate state failures 0 exit.cleanupFailures
  aggregate state schema 0 [primary, optional, failures]

def terminalExit (state : State program) (exit : Graph.Exit) : Except Invalid (Transition program) := do
  let failures ← exit.cleanupFailures.mapM (loadValue state.store)
  require (failures.all (fun value => value.schema == program.roots.failure && Profile.Value.externalValid program.schemas value)) .type
  match exit.reason with
  | .failure failure =>
    let failure ← loadValue state.store failure
    require (failure.schema == program.roots.failure && Profile.Value.externalValid program.schemas failure) .type
    return ⟨{ state with result := some (.failed failure failures exit.cancellation) }, [.failed failure failures exit.cancellation]⟩
  | .cancellation =>
    let reason ← fromOption exit.cancellation .type
    return ⟨{ state with result := some (.cancelled reason failures) }, [.cancelled reason failures]⟩
  | _ => throw .type

def unlinkSuspendedExitAt (retired : NodeId) (prior : Graph.Exit) :
    Nat → State program → NodeId → Except Invalid (State program)
  | 0, _, _ => .error .scope
  | count + 1, state, cursor => do
    let .exit record ← fromOption (state.store.lookup cursor) .reference | throw .type
    let outer ← fromOption record.outer .scope
    if outer == retired then
      let state ← replaceNode state cursor (.exit { record with outer := prior.outer })
      let preserve := match prior.reason with
        | .failure _ | .cancellation => true
        | _ => prior.cancellation.isSome
      if preserve then
        let active ← fromOption state.roots.exit .scope
        let .exit current ← fromOption (state.store.lookup active) .reference | throw .type
        let reason := match prior.reason with | .failure value => .failure value | _ => .cancellation
        replaceNode state active (.exit { current with
          reason := reason
          cancellation := prior.cancellation.or current.cancellation
          cleanupFailures := prior.cleanupFailures ++ current.cleanupFailures
          stop := none })
      else pure state
    else unlinkSuspendedExitAt retired prior count state outer

/-- Closing a suspended cleanup removes its obsolete exit context while the
current disposal retains its own caller and any earlier failure/cancellation. -/
def unlinkSuspendedExit (state : State program) (retired : NodeId) : Except Invalid (State program) := do
  let .exit prior ← fromOption (state.store.lookup retired) .reference | throw .type
  let cursor ← fromOption state.roots.exit .scope
  if cursor == retired then pure state
  else unlinkSuspendedExitAt retired prior state.store.nodes.length state cursor

def crossedCleanupReturn (state : State program) (reference : NodeId) (obligation : Graph.OwnedRef)
    (parent : Option NodeId) (outer : NodeId) (exit : Graph.Exit) : Except Invalid (Transition program) := do
  let .obligation block cleanup resource status ← fromOption (state.store.lookup obligation.node) .reference | throw .type
  require (status == .running reference && cleanup.isNone && resource.isNone) .custody
  match exit.reason with
  | .abandoned =>
    let .exit suspended ← fromOption (state.store.lookup outer) .reference | throw .type
    let state ← unlinkSuspendedExit state outer
    let state ← replaceNode state obligation.node (.obligation block none none .completed)
    return ⟨unwindPosition state parent (discardedNormal suspended), []⟩
  | .failure failure =>
    let state ← replaceNode state obligation.node (.obligation block none none (.failed failure))
    let .exit parentExit ← fromOption (state.store.lookup outer) .reference | throw .type
    let state ← match parentExit.reason with
      | .normal _ | .abandoned => replaceNode state outer (.exit { parentExit with reason := exit.reason, stop := none, discarded := discardedNormal parentExit })
      | _ => pure state
    return ⟨unwindPosition { state with roots := { state.roots with exit := some outer } } parent [], []⟩
  | _ => throw .type

/-- One obligation starts or advances at most one lifecycle transition here.
Authored cleanup enters the ordinary BPI2 computation path and may suspend. -/
def unwindStep (state : State program) : Except Invalid (Transition program) := do
  let .unwind cursor values ← fromOption (state.store.lookup (← fromOption state.roots.current .inactive)) .reference | throw .type
  let exitReference ← fromOption state.roots.exit .inactive
  let .exit exit ← fromOption (state.store.lookup exitReference) .reference | throw .type
  let (rootReference, rootExit) ← outermostExit state
  if !rootExit.discarded.isEmpty then
    let state ← replaceNode state rootReference (.exit { rootExit with discarded := [] })
    return ⟨unwindPosition state cursor (rootExit.discarded ++ values), []⟩
  if let value :: rest := values then
    let .owned reference := value.body | throw .custody
    let record ← fromOption (state.store.lookup reference.node) .reference
    match record with
    | .oneShot _ =>
      let (state, capture) ← takeCapture state value
      let (store, after) := state.store.add (.disposalReturn value.schema cursor rest)
      let state ← activate { state with store := store } capture after
      return ⟨unwindPosition state capture.capture [], []⟩
    | .aggregate _ _ fields => return ⟨unwindPosition state cursor (owned fields ++ rest), []⟩
    | .package _ inner => return ⟨unwindPosition state cursor (owned [inner] ++ rest), []⟩
    | .computation _ environment =>
      let fields ← environmentValues state.store (state.store.nodes.length + 1) (some environment)
      return ⟨unwindPosition state cursor (owned fields ++ rest), []⟩
    | .resource .. => return ⟨unwindPosition state cursor rest, []⟩
    | _ => throw .custody
  if cursor == exit.stop then
    let state := { state with roots := { state.roots with exit := exit.outer }, status := .active }
    match exit.reason with
    | .normal value => return ← returnTo state cursor value
    | .abandoned =>
      let after ← fromOption cursor .inactive
      -- Lowering's disposal edge does not use its returned hole. The concrete
      -- runtime still supplies the canonical all-zero scalar record.
      let value : Graph.Value := ⟨0, .scalar (Vector.replicate 8 0)⟩
      return ⟨← resumeContinuation state after value, []⟩
    | _ => pure ()
  let some reference := cursor | return ← terminalExit state rootExit
  match ← fromOption (state.store.lookup reference) .reference with
  | .control control => return ⟨unwindPosition state control.parent (owned control.arguments), []⟩
  | .continuation saved => return ⟨unwindPosition state saved.parent (owned (saved.arguments.filterMap id)), []⟩
  | .attachment _ _ after _ _ | .regionScope _ _ after => return ⟨unwindPosition state after [], []⟩
  | .injection after => return ⟨unwindPosition state (some after) [], []⟩
  | .disposalReturn _ parent rest => return ⟨unwindPosition state parent rest, []⟩
  | .protection _ obligation after evidence region _ =>
    let .obligation block cleanup resource status ← fromOption (state.store.lookup obligation.node) .reference | throw .type
    require (status == .pending) .custody
    let cleanup ← fromOption cleanup .custody
    let (store, frame) := state.store.add (.cleanupReturn obligation after exitReference)
    let state ← replaceNode { state with store := store } obligation.node (.obligation block none none (.running frame))
    let .internal (.computation signature) ← fromOption program.schemas[cleanup.schema.value]? .type | throw .type
    let informationType ← fromOption signature.parameters[0]? .type
    let (state, info) ← exitInformation state informationType rootExit
    let state ← applyComputation { state with status := .active } cleanup (info :: resource.toList) (some frame) evidence region
    return ⟨state, []⟩
  | .cleanupReturn obligation parent outer =>
    crossedCleanupReturn state reference obligation parent outer exit
  | _ => throw .type

end BoundaryV2.Profile.Target.Machine
