import BoundaryV2.SourceEffects

namespace BoundaryV2.Profile.Source.Machine

def cleanupInformation (context : Context) (schema : SchemaId .source)
    (exit : Cleanup.Exit .source) : Except Invalid SemanticValue := do
  let .product [primary, optional, failures] ← fromOption context.source.schemas[schema.value]? .type | throw .type
  let .sum [unit, failure, reason, abandoned] ← fromOption context.source.schemas[primary.value]? .type | throw .type
  let .sum [absent, present] ← fromOption context.source.schemas[optional.value]? .type | throw .type
  let .sum [text, bytes] ← fromOption context.source.schemas[reason.value]? .type | throw .type
  require (unit == abandoned && unit == absent && reason == present && failure == context.source.failure) .type
  require (context.source.schemas[unit.value]? == some .unit &&
    context.source.schemas[text.value]? == some .text && context.source.schemas[bytes.value]? == some .bytes &&
    context.source.schemas[failures.value]? == some (.seq context.source.failure)) .type
  let empty : SemanticValue := .scalar unit 0
  let cancellation : Option SemanticValue := exit.cancellation.map fun cancellation => match cancellation with
    | .text data => .variant reason 0 (.blob text data)
    | .bytes data => .variant reason 1 (.blob bytes data)
  let primaryValue ← match exit.primary with
    | .normal _ => pure (.variant primary 0 empty)
    | .failure value => pure (.variant primary 1 value)
    | .cancellation => do
      let value ← fromOption cancellation .type
      pure (.variant primary 2 value)
    | .abandoned => pure (.variant primary 3 empty)
  let optionalValue := match cancellation with
    | none => .variant optional 0 empty
    | some value => .variant optional 1 value
  return .product schema [primaryValue, optionalValue, .sequence failures exit.failures]

def installProtection (state : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) : Except Invalid Transition := do
  let bodyType ← computationType context body
  let cleanupType ← computationType context cleanup
  require (cleanupType.parameters.length == 1 + resource.toList.length) .type
  require (context.source.schemas[cleanupType.result.value]? == some .unit) .type
  require (state.heap.nextObligation == state.heap.obligations.length) .scope
  let identity : ObligationId := ⟨state.heap.nextObligation⟩
  let held := cleanup :: resource.toList
  let heap ← fromOption (moveValues state.heap held (fun _ => .protection identity)) .custody
  let obligation : Cleanup.Obligation .source := ⟨identity, state.scope, identity.value,
    cleanup.value, resource.map Located.value, .pending⟩
  let heap := { heap with obligations := heap.obligations ++ [obligation], nextObligation := heap.nextObligation + 1 }
  let (heap, borrowed, frames) ← match resource, loan with
    | none, none => pure (heap, [], [.protection identity])
    | some resource, some descriptor => do
      require (descriptor.value < context.source.regionCount) .type
      let .reference _ node (some _) := resource.value | throw .type
      let schema ← fromOption bodyType.parameters.head? .type
      require (context.source.schemas[schema.value]? == some (.internal (.borrowed resource.value.schema descriptor))) .type
      let region : RegionInstanceId := ⟨heap.nextRegion⟩
      let heap := { heap with nextRegion := heap.nextRegion + 1, loans := heap.loans ++ [(region, identity)] }
      let (heap, borrowed) ← fromOption (allocateObject heap schema
        (.borrow schema node region state.invocation) (.receiver state.invocation 0) false) .custody
      pure (heap, [borrowed], [.region region, .protection identity])
    | _, _ => throw .type
  applyClosure { state with heap := heap, stack := frames ++ state.stack } context body (borrowed ++ arguments)

def beginCleanup (state : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) : Except Invalid Transition := do
  let exit := observedExit state exit
  let obligation ← fromOption state.heap.obligations[identity.value]? .reference
  require (obligation.id == identity) .scope
  let invocation : InvocationId := ⟨state.heap.nextInvocation⟩
  let (obligation, events) ← fromOption (Cleanup.begin obligation invocation) .custody
  let cleanup : Located := ⟨obligation.cleanup, .protection identity⟩
  let signature ← computationType context cleanup
  let informationType ← fromOption signature.parameters.head? .type
  let information ← cleanupInformation context informationType exit
  let heap := { state.heap with obligations := state.heap.obligations.set identity.value obligation }
  let arguments := Located.mk information (.receiver invocation 0) ::
    obligation.resource.toList.map (fun value => Located.mk value (.protection identity))
  let transition ← applyClosure { state with
    heap := heap
    stack := .cleanupReturn identity invocation exit normal :: tail } context cleanup arguments
  return { transition with events := events.map Event.cleanup ++ transition.events }

def exitAfter (exit : Cleanup.Exit .source) (normal : Option Located) : Except Invalid AfterRelease := do
  match exit.primary with
  | .normal value =>
    let located ← fromOption normal .custody
    require (located.value == value) .type
    return .deliver located
  | _ => return .unwind exit

def finishCleanup (state : State) (context : Context) : Except Invalid Transition := do
  let .delivered value := state.control | throw .inactive
  let .cleanupReturn identity invocation exit normal :: tail := state.stack | throw .inactive
  require (context.source.schemas[value.value.schema.value]? == some .unit) .type
  let obligation ← fromOption state.heap.obligations[identity.value]? .reference
  let (obligation, events) ← fromOption (Cleanup.complete obligation invocation (.ok ())) .custody
  let heap := { state.heap with obligations := state.heap.obligations.set identity.value obligation }
  let after ← exitAfter (observedExit state exit) normal
  return { resumeRelease { state with heap := heap, stack := tail } after with events := events.map Event.cleanup }

def mergeAbrupt (outer inner : Cleanup.Exit .source) : Cleanup.Exit .source :=
  let after := match inner.primary with
    | .failure value => Cleanup.recordFailure outer value inner.failures
    | _ => { outer with failures := outer.failures ++ inner.failures }
  match inner.cancellation with
  | some reason => Cleanup.cancel after reason
  | none => after

def cleanupFailed (state : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) : Except Invalid Transition := do
  let .failure failure := inner.primary | throw .type
  let obligation ← fromOption state.heap.obligations[identity.value]? .reference
  let (obligation, events) ← fromOption (Cleanup.complete obligation invocation (.error failure)) .custody
  let heap := { state.heap with obligations := state.heap.obligations.set identity.value obligation }
  let exit := mergeAbrupt outer inner
  return ⟨{ state with
    heap := heap
    stack := tail
    control := .discard (normal.toList.flatMap (liveOwned heap)) (.unwind exit) }, events.map Event.cleanup⟩

def releaseScope (state : State) : Except Invalid Transition := do
  let .release scope after := state.control | throw .inactive
  let record ← fromOption state.heap.scopes[scope.value]? .scope
  require (record.id == scope) .scope
  let values := record.holdings.flatMap (liveOwned state.heap)
  return ⟨{ state with control := .discard values after }, []⟩

/-- Disposal traverses owned children before siblings. A captured continuation
runs its own ordinary unwind rules and may suspend in authored cleanup. -/
def discardValues (state : State) (_context : Context) : Except Invalid Transition := do
  let .discard values after := state.control | throw .inactive
  match values with
  | [] => return resumeRelease state after
  | value :: rest =>
    if (liveOwned state.heap value).isEmpty then return ⟨{ state with control := .discard rest after }, []⟩
    let (_, object) ← lookupObject state value
    match object with
    | .oneShot capture =>
      let heap ← fromOption (retireObject state.heap value) .custody
      -- Abandonment crosses the selected delimiter without running its return clause.
      return ⟨{ state with
        heap := heap
        scope := capture.scope
        invocation := capture.invocation
        control := .unwind (match after with | .unwind exit => exit | .deliver _ => ⟨.abandoned, [], none⟩)
        stack := capture.frames ++ [.handler capture.delimiter,
          .disposalReturn rest after state.invocation state.scope] ++ state.stack }, []⟩
    | .closure _ _ environment =>
      let heap ← fromOption (retireObject state.heap value) .custody
      let children := environment.flatMap (fun binding => liveOwned heap binding.located)
      return ⟨{ state with heap := heap, control := .discard (children ++ rest) after }, []⟩
    | .package _ content =>
      let heap ← fromOption (retireObject state.heap value) .custody
      return ⟨{ state with heap := heap, control := .discard (liveOwned heap content ++ rest) after }, []⟩
    | .resource _ _ =>
      let heap ← fromOption (retireObject state.heap value) .custody
      return ⟨{ state with heap := heap, control := .discard rest after }, []⟩
    | _ => throw .type

/-- Unwind first releases the active lexical scope. Scope holdings are ordered
by construction; handler frames themselves own no exclusive state. -/
def unwindStep (state : State) (context : Context) : Except Invalid Transition := do
  let .unwind original := state.control | throw .inactive
  let exit := observedExit state original
  let scope ← fromOption state.heap.scopes[state.scope.value]? .scope
  let pending := scope.holdings.flatMap (liveOwned state.heap)
  let leaving := match state.stack with
    | [] | .invocation .. :: _ | .lexical _ :: _ => true
    | _ => false
  if leaving && !pending.isEmpty then
    return ⟨{ state with control := .discard pending (.unwind exit) }, []⟩
  match state.stack with
  | [] => match exit.primary with
    | .failure _ => return ⟨{ state with status := .failed exit }, [.failed exit]⟩
    | .cancellation => return ⟨{ state with status := .cancelled exit }, [.cancelled exit]⟩
    | _ => throw .type
  | frame :: tail => match frame with
    | .invocation invocation scope | .restore invocation scope =>
      return ⟨{ state with stack := tail, invocation := invocation, scope := scope }, []⟩
    | .lexical identity =>
      require (identity == state.scope) .scope
      let parent ← fromOption scope.parent .scope
      return ⟨{ state with stack := tail, scope := parent }, []⟩
    | .protection identity => beginCleanup state context identity exit none tail
    | .cleanupReturn identity invocation outer normal => cleanupFailed state identity invocation outer normal tail exit
    | .disposalReturn remaining after invocation scope =>
      let after ← match exit.primary with
        | .abandoned => pure after
        | _ => match after with
          | .unwind _ => pure (.unwind exit)
          | .deliver value => pure (.unwind (mergeAbrupt ⟨.normal value.value, [], none⟩ exit))
      return ⟨{ state with
        control := .discard remaining after
        stack := tail
        scope := scope
        invocation := invocation }, []⟩
    | .releaseReturn _ after =>
      let merged := match after with
        | .unwind outer => mergeAbrupt outer exit
        | .deliver value => mergeAbrupt ⟨.normal value.value, [], none⟩ exit
      return ⟨{ state with control := .unwind merged, stack := tail }, []⟩
    | .binding .. | .operands .. | .handler _ | .region _ | .injection _ =>
      return ⟨{ state with stack := tail }, []⟩

def executeCleanupTerm (state : State) (context : Context) : Except Invalid Transition := do
  let .execute (.term term) _ operands := state.control | throw .inactive
  require (operands.all (current state.heap)) .custody
  match term with
  | .protect _ _ arguments resource loan => match operands with
    | body :: cleanup :: rest =>
      require (rest.length == arguments.length + resource.toList.length) .operands
      installProtection state context body cleanup (rest.take arguments.length) (rest[arguments.length]?) loan
    | _ => throw .operands
  | .dispose _ => match operands with
    | [value] =>
      let .internal (.resumption signature) ← fromOption context.source.schemas[value.value.schema.value]? .type | throw .type
      require (signature.use == .affine || signature.use == .linear) .type
      let unitIndex ← fromOption (context.source.schemas.findIdx? (· == .unit)) .type
      let (after, owner) ← temporary state
      let unit : Located := ⟨.scalar ⟨unitIndex⟩ 0, owner⟩
      return ⟨{ after with control := .discard [value] (.deliver unit) }, []⟩
    | _ => throw .operands
  | _ => throw .inactive

end BoundaryV2.Profile.Source.Machine
