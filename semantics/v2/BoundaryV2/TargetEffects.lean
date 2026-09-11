import BoundaryV2.TargetUnwind

namespace BoundaryV2.Profile.Target.Machine

def computationType (program : Program) (schema : SchemaId .target) : Except Invalid (ComputationType .target) := do
  let .internal (.computation signature) ← fromOption program.schemas[schema.value]? .type | throw .type
  return signature

def installHandler (state : State program) (control : Graph.Control) (handler : HandlerId .target)
    (bodySlot : Slot) (stateSlots argumentSlots : List Slot) (values : List Graph.Value) : Except Invalid (State program) := do
  let definition ← fromOption program.handlers[handler.value]? .reference
  let fields ← slots values stateSlots
  require (fields.map Graph.Value.schema == definition.state) .type
  let (store, activation) := state.store.add (.handler handler fields control.evidence control.region)
  let (state, after) ← continuation { state with store := store } control values
  let (store, attachment) := state.store.add (.attachment activation control.evidence (some after) .active control.region)
  let body ← slot values bodySlot
  let signature ← computationType program body.schema
  let capabilities ← definition.clauses.zipIdx.mapM fun (clause, index) => do
    let schema ← fromOption signature.parameters[index]? .type
    require (program.schemas[schema.value]? == some (.internal (.capability clause.effect))) .type
    return (⟨schema, .reference attachment⟩ : Graph.Value)
  let arguments ← slots values argumentSlots
  applyComputation { state with store := store } body (capabilities ++ arguments) (some attachment) (some attachment) control.region

def selectAttachmentAt (store : Store schemas) (selected : NodeId) : Nat → Option NodeId → Except Invalid Unit
  | 0, _ => .error .scope
  | _, none => .error .scope
  | count + 1, some cursor => do
    let node ← fromOption (store.lookup cursor) .reference
    if cursor == selected then
      let .attachment _ _ _ phase _ := node | throw .type
      require (phase == .active) .inactive
    else
      require (Graph.isFrame node) .scope
      selectAttachmentAt store selected count (Graph.frameParent node)

def performHandled (context : Context) (state : State context.program) (control : Graph.Control)
    (operation : Perform) (values : List Graph.Value) : Except Invalid (State context.program) := do
  let capability ← slot values (← fromOption operation.capability .operands)
  require (context.program.schemas[capability.schema.value]? == some (.internal (.capability operation.effect))) .type
  let selected ← valueReference capability
  selectAttachmentAt state.store selected (state.store.nodes.length + 1) control.parent
  let .attachment handler outer parent _ region ← fromOption (state.store.lookup selected) .reference | throw .type
  let .handler definition fields evidence handlerRegion ← fromOption (state.store.lookup handler) .reference | throw .type
  let definition ← fromOption context.program.handlers[definition.value]? .reference
  let clause ← fromOption (definition.clauses.find? (fun clause => clause.effect == operation.effect)) .type
  let payload ← slot values operation.payload
  if clause.direct then
    let function ← fromOption context.program.functions[clause.function.value]? .reference
    let block ← fromOption context.program.blocks[function.entry.value]? .reference
    let .returnValue result := block.terminator | throw .type
    let entered := { control with block := function.entry, arguments := fields ++ [payload] }
    let .complete state evaluated ← evaluateBlock context state entered | throw .type
    jump state control operation.next values (some (← slot evaluated result))
  else
    let signature ← resumptionType context.program clause.resumption
    let (state, saved) ← continuation state control values
    let useSite ← slots values operation.useSiteCapabilities
    let capture : Graph.Capture := ⟨clause.resumption, some saved, selected, control.evidence, useSite⟩
    if signature.use == .multi then capturedCloneSafe state capture
    let node := if signature.use == .multi then Graph.Node.multiTemplate capture else .oneShot capture
    let (store, token) := state.store.add node
    let state ← replaceNode { state with store := store } selected (.attachment handler outer none .suspended region)
    let bodies ← slots values operation.bodies
    let argument : Graph.Value := ⟨clause.resumption, if signature.use == .multi then .reference token else .owned ⟨token⟩⟩
    enter state clause.function (fields ++ [payload] ++ bodies ++ [argument]) parent evidence handlerRegion

def perform (context : Context) (state : State context.program) (control : Graph.Control)
    (operation : Perform) (values : List Graph.Value) : Except Invalid (Transition context.program) := do
  if operation.capability.isSome then return ⟨← performHandled context state control operation values, []⟩
  let effect ← fromOption context.program.effects[operation.effect.value]? .reference
  require (effect.external && operation.bodies.isEmpty && operation.useSiteCapabilities.isEmpty) .type
  let payload ← slot values operation.payload
  let meaning ← loadValue state.store payload
  require (payload.schema == effect.payload && Profile.Value.externalValid context.program.schemas meaning) .type
  let (state, saved) ← continuation state control values
  let (store, pending) := state.store.add (.pending operation.effect payload saved control.block)
  let occurrence : RequestOccurrence := ⟨state.nextOccurrence⟩
  let state := { state with store := store, status := .parked, nextOccurrence := state.nextOccurrence + 1, pendingOccurrence := some occurrence, roots := { state.roots with pending := some pending, current := none } }
  return ⟨state, [.requestOpened occurrence operation.effect meaning]⟩

def resumeValue (state : State program) (control : Graph.Control) (resumption argument : Slot)
    (values : List Graph.Value) : Except Invalid (State program) := do
  let value ← slot values resumption
  let (state, capture) ← takeCapture state value
  let (state, after) ← continuation state control values
  let (state, _) ← prepareResumption state capture after
  resumeContinuation state (← fromOption capture.capture .custody) (← slot values argument)

def resumeWith (state : State program) (control : Graph.Control) (resumption argument : Slot)
    (handler : HandlerId .target) (stateSlots : List Slot) (values : List Graph.Value) : Except Invalid (State program) := do
  let (state, capture) ← takeCapture state (← slot values resumption)
  let fields ← slots values stateSlots
  let definition ← fromOption program.handlers[handler.value]? .reference
  require (fields.map Graph.Value.schema == definition.state) .type
  let (store, activation) := state.store.add (.handler handler fields control.evidence control.region)
  let (state, after) ← continuation { state with store := store } control values
  let state ← replaceNode state capture.delimiter (.attachment activation control.evidence (some after) .active control.region)
  resumeContinuation state (← fromOption capture.capture .custody) (← slot values argument)

def resumeComputation (state : State program) (control : Graph.Control) (resumption computation : Slot)
    (values : List Graph.Value) : Except Invalid (State program) := do
  let (state, capture) ← takeCapture state (← slot values resumption)
  let (state, after) ← continuation state control values
  let (state, evidence) ← prepareResumption state capture after
  let position ← fromOption capture.capture .custody
  let .continuation saved ← fromOption (state.store.lookup position) .reference | throw .type
  let (store, injected) := state.store.add (.injection position)
  applyComputation { state with store := store } (← slot values computation) capture.useSiteCapabilities (some injected) evidence saved.region

def withRegion (state : State program) (control : Graph.Control) (descriptor : RegionId .target)
    (bodySlot : Slot) (argumentSlots : List Slot) (values : List Graph.Value) : Except Invalid (State program) := do
  require (descriptor.value < program.scopes.regionCount) .scope
  let (store, region) := state.store.add (.region descriptor control.region [])
  let (state, after) ← continuation { state with store := store } control values
  let (store, frame) := state.store.add (.regionScope control.block region (some after))
  let body ← slot values bodySlot
  let signature ← computationType program body.schema
  let regionType ← fromOption signature.parameters[0]? .type
  require (program.schemas[regionType.value]? == some (.internal (.region descriptor))) .type
  let arguments ← slots values argumentSlots
  applyComputation { state with store := store } body (⟨regionType, .reference region⟩ :: arguments) (some frame) control.evidence (some region)

def protect (state : State program) (control : Graph.Control) (bodySlot cleanupSlot : Slot)
    (argumentSlots : List Slot) (resourceSlot : Option Slot) (loanDescriptor : Option (RegionId .target))
    (values : List Graph.Value) : Except Invalid (State program) := do
  let resource ← resourceSlot.mapM (slot values)
  let cleanup ← slot values cleanupSlot
  let (store, obligation) := state.store.add (.obligation control.block (some cleanup) resource .pending)
  let (state, after) ← continuation { state with store := store } control values
  let (state, loan) ← match loanDescriptor with
    | none => pure (state, none)
    | some descriptor => do
      require (descriptor.value < program.scopes.regionCount) .scope
      let (store, region) := state.store.add (.region descriptor control.region [])
      pure ({ state with store := store }, some region)
  let (store, frame) := state.store.add (.protection control.block ⟨obligation⟩ (some after) control.evidence control.region loan)
  let state := { state with store := store }
  let body ← slot values bodySlot
  let signature ← computationType program body.schema
  let (state, borrowed) ← match resource with
    | none => pure (state, [])
    | some value => do
      let type ← fromOption signature.parameters[0]? .type
      let loan ← fromOption loan .scope
      let .owned owned := value.body | throw .custody
      let (store, borrow) := state.store.add (.borrow type owned.node loan)
      pure ({ state with store := store }, [⟨type, .reference borrow⟩])
  let arguments ← slots values argumentSlots
  applyComputation state body (borrowed ++ arguments) (some frame) control.evidence (loan.or control.region)

def dispose (state : State program) (control : Graph.Control) (resumption : Slot)
    (values : List Graph.Value) : Except Invalid (State program) := do
  let (state, capture) ← takeCapture state (← slot values resumption)
  let (state, after) ← continuation state control values
  let state ← activate state capture after
  return beginUnwind state .abandoned capture.capture (some after) []

end BoundaryV2.Profile.Target.Machine
