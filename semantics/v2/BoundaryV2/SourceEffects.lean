import BoundaryV2.SourceCapture

namespace BoundaryV2.Profile.Source.Machine

def computationType (context : Context) (value : Located) : Except Invalid (ComputationType .source) := do
  let .internal (.computation signature) ← fromOption context.source.schemas[value.value.schema.value]? .type | throw .type
  return signature

def handlerEnvironment (context : Context) (handler : Handler .source) (environment : Environment) : Environment :=
  restrictEnvironment environment ((handler.returnFunction :: handler.clauses.map Clause.function).flatMap
    (Analysis.captures context.captures))

def installHandler (state : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (environment : Environment) : Except Invalid Transition := do
  let definition ← fromOption context.source.handlers[handler.value]? .reference
  require definition.forwardFunction.isNone .type
  require (stored.map (fun value => value.value.schema) == definition.state) .type
  require (stored.all (fun value => Traits.check context.source.schemas .copy value.value.schema)) .type
  let signature ← computationType context body
  require (signature.parameters.length == definition.clauses.length + arguments.length) .type
  let identity : AttachmentId := ⟨state.heap.nextAttachment⟩
  let activation : Activation := ⟨identity, handler, handlerEnvironment context definition environment,
    stored, state.invocation, state.scope, (activeAttachments state.stack).head?⟩
  let seed := { state.heap with nextAttachment := state.heap.nextAttachment + 1 }
  let (heap, capabilities) ← (definition.clauses.zip (signature.parameters.take definition.clauses.length)).foldlM
    (fun (heap, capabilities) (clause, schema) => do
      require (context.source.schemas[schema.value]? == some (.internal (.capability clause.effect))) .type
      let (heap, value) ← fromOption (allocateObject heap schema (.capability identity clause.effect)
        (.receiver state.invocation capabilities.length) false) .custody
      pure (heap, capabilities ++ [value])) (seed, [])
  applyClosure { state with heap := heap, stack := .handler activation :: state.stack } context body (capabilities ++ arguments)

def completeHandler (state : State) (context : Context) : Except Invalid Transition := do
  let .delivered value := state.control | throw .inactive
  let .handler activation :: tail := state.stack | throw .inactive
  let definition ← fromOption context.source.handlers[activation.definition.value]? .reference
  require (value.value.schema == definition.input) .type
  return ⟨{ state with
    control := .invoke definition.returnFunction activation.environment (activation.state ++ [value])
    stack := tail
    scope := activation.scope
    invocation := activation.invocation }, []⟩

def frozenCells (heap : Heap) (regions : List RegionInstanceId) : List FrozenCell :=
  heap.objects.zipIdx |>.filterMap fun (object, index) => match object with
    | some (.cell identity _ region content) => if regions.contains region then some ⟨⟨index⟩, identity, region, content⟩ else none
    | _ => none

def openRequest (state : State) (context : Context) (operation : Operation)
    (operands : List Located) : Except Invalid Transition := do
  let effect ← fromOption context.source.effects[operation.effect.value]? .reference
  require (operands.length == operation.capability.toList.length + 1 + operation.bodies.length + operation.useSiteCapabilities.length) .operands
  let capability := if operation.capability.isSome then operands.head? else none
  let rest := operands.drop operation.capability.toList.length
  let payload ← fromOption rest.head? .operands
  let bodies := (rest.drop 1).take operation.bodies.length
  let capabilities := rest.drop (1 + operation.bodies.length)
  require (payload.value.schema == effect.payload && bodies.map (fun value => value.value.schema) == effect.bodies) .type
  match capability with
  | none =>
    require effect.external .type
    require (Profile.Value.externalValid context.source.schemas payload.value) .type
    let occurrence : RequestOccurrence := ⟨state.nextOccurrence⟩
    let request : Request := ⟨occurrence, operation.effect, payload.value, bodies, capabilities, effect.result⟩
    return ⟨{ state with status := .parked request, nextOccurrence := state.nextOccurrence + 1 }, [.requestOpened request]⟩
  | some capability =>
    let (_, .capability identity nominal) ← lookupObject state capability | throw .type
    require (nominal == operation.effect) .type
    let selected ← fromOption (selectAttachment identity state.stack) .scope
    let definition ← fromOption context.source.handlers[selected.activation.definition.value]? .reference
    let clause ← fromOption (definition.clauses.find? (fun clause => clause.effect == operation.effect)) .type
    if clause.direct then
      require bodies.isEmpty .type
      let function ← fromOption context.source.functions[clause.function.value]? .reference
      require (function.effects.isEmpty && function.result == effect.result) .type
      invokeFunction state context clause.function selected.activation.environment (selected.activation.state ++ [payload])
    else
      let .internal (.resumption signature) ← fromOption context.source.schemas[clause.resumption.value]? .type | throw .type
      -- Clause operands leave the captured custody before clone admission.
      -- Enter the clause before exposing a successor: cancellation must never
      -- observe receiver holdings whose invocation has not acquired them.
      let receiver : InvocationId := ⟨state.heap.nextInvocation⟩
      let outgoing := payload :: bodies
      let heap ← fromOption (moveValues state.heap outgoing (Custody.Owner.receiver receiver)) .custody
      let outgoing := outgoing.mapIdx (fun index value => retainAt value (.receiver receiver index))
      let frames := selected.inside.map (trimFrame context)
      let regions := activeRegions frames
      let capture : Capture := ⟨clause.resumption, frames, selected.activation, capabilities, regions,
        frozenCells heap regions, state.scope, state.invocation⟩
      if signature.use == .multi then require (allCaptureCloneSafe context.source heap capture) .custody
      let outside := { state with
        heap := heap
        stack := selected.outside
        scope := selected.activation.scope
        invocation := selected.activation.invocation }
      let (outside, owner) ← temporary outside
      let (heap, token) ← fromOption (allocateObject outside.heap clause.resumption
        (if signature.use == .multi then .multiTemplate capture else .oneShot capture) owner
        (signature.use != .multi)) .custody
      let staged ← finishTemporary { outside with heap := heap } token
      invokeFunction staged.state context clause.function selected.activation.environment
        (selected.activation.state ++ outgoing ++ [token])

def takeCapture (state : State) (context : Context) (token : Located) : Except Invalid (State × Capture) := do
  let (_, object) ← lookupObject state token
  match object with
  | .oneShot capture =>
    let heap ← fromOption (retireObject state.heap token) .custody
    return ({ state with heap := heap }, capture)
  | .multiTemplate capture => instantiateCapture state context capture
  | _ => throw .type

/-- Resume keeps both continuations: the captured code and its caller. The
restore frame does not release the original handler caller's lexical scope. -/
def activateCapture (state : State) (context : Context) (capture : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) : Except Invalid State := do
  let .internal (.resumption signature) ← fromOption context.source.schemas[capture.schema.value]? .type | throw .type
  let delimiter ← match successor with
    | none => pure capture.delimiter
    | some (handler, stored, environment) => do
      let definition ← fromOption context.source.handlers[handler.value]? .reference
      require (stored.map (fun value => value.value.schema) == definition.state) .type
      require (stored.all (fun value => Traits.check context.source.schemas .copy value.value.schema)) .type
      pure { capture.delimiter with
        definition := handler
        environment := handlerEnvironment context definition environment
        state := stored
        invocation := state.invocation
        scope := state.scope
        outer := (activeAttachments state.stack).head? }
  let reinstall := successor.isSome || signature.mode == .deep
  return { state with
    stack := capture.frames ++ (if reinstall then [.handler delimiter] else []) ++
      [.restore state.invocation state.scope] ++ state.stack
    scope := capture.scope
    invocation := capture.invocation }

def resumeValue (state : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment) := none) : Except Invalid Transition := do
  let (after, capture) ← takeCapture state context token
  let .internal (.resumption signature) ← fromOption context.source.schemas[capture.schema.value]? .type | throw .type
  require (argument.value.schema == signature.input) .type
  let active ← activateCapture after context capture successor
  let (active, owner) ← temporary active
  let heap ← fromOption (moveValues active.heap [argument] (fun _ => owner)) .custody
  finishTemporary { active with heap := heap } (retainAt argument owner)

def resumeComputation (state : State) (context : Context) (token computation : Located) : Except Invalid Transition := do
  let (after, capture) ← takeCapture state context token
  let active ← activateCapture after context capture none
  applyClosure active context computation capture.useSiteCapabilities

def restoreResumeCaller (state : State) : Except Invalid Transition := do
  let .delivered value := state.control | throw .inactive
  let .restore invocation scope :: tail := state.stack | throw .inactive
  let (after, owner) ← temporary { state with scope := scope, invocation := invocation, stack := tail }
  let heap ← fromOption (moveValues after.heap [value] (fun _ => owner)) .custody
  finishTemporary { after with heap := heap } (retainAt value owner)

def enterRegion (state : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) : Except Invalid Transition := do
  require (descriptor.value < context.source.regionCount) .type
  let signature ← computationType context body
  let schema ← fromOption signature.parameters.head? .type
  require (context.source.schemas[schema.value]? == some (.internal (.region descriptor))) .type
  let identity : RegionInstanceId := ⟨state.heap.nextRegion⟩
  let heap := { state.heap with nextRegion := state.heap.nextRegion + 1 }
  let (heap, value) ← fromOption (allocateObject heap schema
    (.region identity descriptor state.invocation (activeRegions state.stack).head?)
    (.receiver state.invocation 0) false) .custody
  applyClosure { state with heap := heap, stack := .region identity :: state.stack } context body (value :: arguments)

def executeEffectTerm (state : State) (context : Context) : Except Invalid Transition := do
  let .execute (.term term) environment operands := state.control | throw .inactive
  require (operands.all (current state.heap)) .custody
  match term with
  | .perform operation => openRequest state context operation operands
  | .handle handler _ arguments _ => match operands with
    | body :: rest => installHandler state context handler body (rest.take arguments.length) (rest.drop arguments.length) environment
    | _ => throw .operands
  | .resumeValue _ _ => match operands with
    | [token, argument] => resumeValue state context token argument
    | _ => throw .operands
  | .resumeWith _ _ handler _ => match operands with
    | token :: argument :: stored => resumeValue state context token argument (some (handler, stored, environment))
    | _ => throw .operands
  | .resumeComputation _ _ => match operands with
    | [token, computation] => resumeComputation state context token computation
    | _ => throw .operands
  | .withRegion descriptor _ _ => match operands with
    | body :: arguments => enterRegion state context descriptor body arguments
    | _ => throw .operands
  | _ => throw .inactive

/-- Handler selection is by allocated capability identity, never effect text. -/
theorem other_attachment_does_not_intercept (identity : AttachmentId) (activation : Activation)
    (different : identity ≠ activation.identity) (tail : List Frame) :
    selectAttachment identity (.handler activation :: tail) =
      (selectAttachment identity tail).map (fun selected => { selected with inside := .handler activation :: selected.inside }) := by
  simp [selectAttachment, different]

end BoundaryV2.Profile.Source.Machine
