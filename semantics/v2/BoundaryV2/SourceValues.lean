import BoundaryV2.SourceState

namespace BoundaryV2.Profile.Source.Machine

structure Context where
  source : Module
  captures : Analysis.Facts
  constants : List SemanticValue

/-- The source-level raw constant opcode can refer to the compiler's implicit
unit adapter. Its existence and value follow from the staged module itself. -/
def Context.executionConstants (context : Context) : List SemanticValue :=
  match context.source.schemas.findIdx? (· == .unit) with
  | none => context.constants
  | some index =>
    if Analysis.hasDisposal context.source && !context.source.constants.any
        (fun literal => literal.schema.value == index && literal.bytes.isEmpty) then
      context.constants ++ [.scalar ⟨index⟩ 0]
    else context.constants

def current (heap : Heap) (value : Located) : Bool :=
  decide (ownedTokens value.value).Nodup &&
  (ownedTokens value.value).all (fun token => Custody.has heap.custody token value.owner)

/-- Active exclusive leaves in source field order. -/
def liveOwnedValue (heap : Heap) (owner : Custody.Owner) : SemanticValue → List Located
  | .reference schema node (some token) =>
    if Custody.has heap.custody token owner then [⟨.reference schema node (some token), owner⟩] else []
  | .product _ fields | .sequence _ fields => fields.flatMap (liveOwnedValue heap owner)
  | .variant _ _ payload => liveOwnedValue heap owner payload
  | _ => []

def liveOwned (heap : Heap) (value : Located) : List Located := liveOwnedValue heap value.owner value.value

def temporary (state : State) : Except Invalid (State × Custody.Owner) := do
  let some scope := state.heap.scopes[state.scope.value]? | throw .scope
  if scope.id != state.scope then throw .scope
  let owner := Custody.Owner.temporary state.scope scope.nextOwner
  let scopes := state.heap.scopes.set state.scope.value { scope with nextOwner := scope.nextOwner + 1 }
  return ({ state with heap := { state.heap with scopes := scopes } }, owner)

def require (condition : Bool) (reason : Invalid) : Except Invalid Unit :=
  if condition then .ok () else .error reason

def fromOption (value : Option α) (reason : Invalid) : Except Invalid α :=
  match value with | some value => .ok value | none => .error reason

def lookupObject (state : State) (value : Located) : Except Invalid (NodeId × Object) := do
  require (current state.heap value) .custody
  let .reference _ node _ := value.value | throw .type
  let object ← fromOption (state.heap.lookup node) .reference
  return (node, object)

def finishValue (state : State) (value : Located) : Transition :=
  ⟨{ state with control := .delivered value }, []⟩

def finishTemporary (state : State) (value : Located) : Except Invalid Transition := do
  let some scope := state.heap.scopes[state.scope.value]? | throw .scope
  let scopes := state.heap.scopes.set state.scope.value { scope with holdings := scope.holdings ++ [value] }
  return finishValue { state with heap := { state.heap with scopes := scopes } } value

def scopedValue (state : State) (value : SemanticValue) : Except Invalid Transition := do
  let (after, owner) ← temporary state
  finishTemporary after ⟨value, owner⟩

def makeClosureWithValues (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) : Except Invalid Transition := do
  let vars := Analysis.captures context.captures function
  require (vars.length == values.length && (vars.zip values).all
    (fun (var, value) => context.source.variables[var.value]? == some value.value.schema)) .type
  let (after, owner) ← temporary state
  let node : NodeId := ⟨after.heap.objects.length⟩
  let captured := (vars.zip values).mapIdx (fun index (var, value) =>
    Binding.mk var (retainAt value (.closure node index)))
  let heap ← fromOption (moveValues after.heap values (Custody.Owner.closure node)) .custody
  let (heap, result) ← fromOption (allocateObject heap schema (.closure schema function captured) owner
    (!Traits.check context.source.schemas .copy schema)) .custody
  finishTemporary { after with heap := heap } result

def makeClosure (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (environment : Environment) : Except Invalid Transition := do
  let values ← (Analysis.captures context.captures function).mapM
    (fun var => fromOption (lookupVariable environment var) .reference)
  makeClosureWithValues state context schema function values

def enterExpression (state : State) (context : Context) : Except Invalid Transition := do
  let .expression reference environment := state.control | throw .inactive
  let definition ← fromOption context.source.values[reference.value]? .reference
  match definition.expression with
  | .variable var =>
    let value ← fromOption (lookupVariable environment var) .reference
    require (value.value.schema == definition.schema) .type
    require (current state.heap value) .custody
    return finishValue state value
  | .literal literal =>
    let value ← fromOption context.constants[literal.value]? .reference
    require (value.schema == definition.schema) .type
    scopedValue state value
  | .lambda function => makeClosure state context definition.schema function environment
  | .primitive opcode operands immediate failures =>
    let intent := Intent.primitive definition.schema opcode immediate failures
    match operands with
    | [] => return ⟨{ state with control := .execute intent environment [] }, []⟩
    | first :: rest => return ⟨{ state with
        control := .expression first environment
        stack := .operands intent environment rest [] :: state.stack }, []⟩

def deliverOperand (state : State) : Except Invalid Transition := do
  let .delivered value := state.control | throw .inactive
  let .operands intent environment remaining evaluated :: tail := state.stack | throw .inactive
  match remaining with
  | [] => return ⟨{ state with control := .execute intent environment (evaluated ++ [value]), stack := tail }, []⟩
  | next :: rest => return ⟨{ state with
      control := .expression next environment
      stack := .operands intent environment rest (evaluated ++ [value]) :: tail }, []⟩

def observes : Opcode → Bool
  | .variantTag | .sequenceLength | .sequenceGet => true
  | _ => false

/-- The result receives custody only after primitive success. Dead DropSafe
operands are retired after this atomic transfer; failure enters unwind with
all earlier lexical and temporary owners still present. -/
def commitPure (state : State) (opcode : Opcode) (operands : List Located)
    (result : SemanticValue) : Except Invalid Transition := do
  let (after, owner) ← temporary state
  if observes opcode then
    require (ownedTokens result).isEmpty .custody
    require (operands.all (current after.heap)) .custody
    finishTemporary after ⟨result, owner⟩
  else
    let heap ← fromOption (moveValues after.heap operands (fun _ => owner)) .custody
    let tokens := operands.flatMap (fun value => ownedTokens value.value)
    let kept := ownedTokens result
    require (kept.all tokens.contains) .custody
    let retired := tokens.filter (fun token => !kept.contains token)
    let custody ← fromOption (Custody.consume heap.custody retired owner) .custody
    finishTemporary { after with heap := { heap with custody := custody } } ⟨result, owner⟩

def authoredFailure (state : State) (context : Context) (failures : List (InstructionFailure .source))
    (fault : Fault) : Except Invalid Transition := do
  let failure ← fromOption (failures.find? (fun entry => entry.kind == fault)) .type
  let value ← fromOption context.executionConstants[failure.value.value]? .reference
  require (value.schema == context.source.failure) .type
  return ⟨{ state with control := .unwind ⟨.failure value, [], none⟩ }, []⟩

def frameValues : Frame → List Located
  | .binding _ _ environment _ => environment.map Binding.located
  | .operands _ environment _ evaluated => environment.map Binding.located ++ evaluated
  | .handler activation => activation.environment.map Binding.located ++ activation.state
  | .injection values => values
  | .invocation .. | .restore .. | .lexical _ | .region _ | .protection _ | .cleanupReturn .. | .disposalReturn ..
  | .releaseReturn .. => []

def frameCloneSafe (source : Module) (frame : Frame) : Bool :=
  match frame with
  | .protection _ | .cleanupReturn .. | .disposalReturn .. | .releaseReturn .. => false
  | _ => (frameValues frame).all (fun value =>
      Traits.check source.schemas .clone value.value.schema && (ownedTokens value.value).isEmpty)

def captureCloneSafe (source : Module) (capture : Capture) : Bool :=
  capture.frames.all (frameCloneSafe source) &&
  (capture.delimiter.environment.map Binding.located ++ capture.delimiter.state ++ capture.useSiteCapabilities).all
    (fun value => Traits.check source.schemas .clone value.value.schema && (ownedTokens value.value).isEmpty) &&
  capture.frozenCells.all (fun cell => Traits.check source.schemas .clone cell.content.value.schema &&
    (ownedTokens cell.content.value).isEmpty)

def frameScopes : Frame → List LexicalScopeId
  | .binding _ _ _ scope | .invocation _ scope | .restore _ scope | .lexical scope
  | .releaseReturn scope _ | .disposalReturn _ _ _ scope => [scope]
  | .handler activation => [activation.scope]
  | _ => []

def frameInvocations : Frame → List InvocationId
  | .invocation invocation _ | .restore invocation _ | .cleanupReturn _ invocation _ _
  | .disposalReturn _ _ invocation _ => [invocation]
  | .handler activation => [activation.invocation]
  | _ => []

def captureScopes (capture : Capture) : List LexicalScopeId :=
  (capture.scope :: capture.frames.flatMap frameScopes).filter (· != capture.delimiter.scope)

def captureInvocations (capture : Capture) : List InvocationId :=
  (capture.invocation :: capture.frames.flatMap frameInvocations).filter (· != capture.delimiter.invocation)

def capturedHoldings (heap : Heap) (capture : Capture) : List Located :=
  (captureScopes capture).eraseDups.flatMap fun scope => match heap.scopes[scope.value]? with
    | none => []
    | some scope => scope.holdings.filter (fun value =>
      (ownedTokens value.value).any (fun token => Custody.has heap.custody token value.owner))

def allCaptureCloneSafe (source : Module) (heap : Heap) (capture : Capture) : Bool :=
  captureCloneSafe source capture && (capturedHoldings heap capture).isEmpty

def heapPrimitive (state : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) : Except Invalid Transition := do
  match operation with
  | .computation =>
    let (function, expected) ← fromOption (Analysis.constructors context.source)[immediate]? .reference
    require (schema == expected) .type
    makeClosureWithValues state context schema function operands
  | .cellNew => match operands with
    | [regionValue, initial] =>
      let (_, .region region descriptor _ _) ← lookupObject state regionValue | throw .type
      let .internal (.cell element expectedRegion) ← fromOption context.source.schemas[schema.value]? .type | throw .type
      require (element == initial.value.schema && descriptor == expectedRegion) .type
      let (after, owner) ← temporary state
      let identity : CellId := ⟨after.heap.nextCell⟩
      let heap ← fromOption (moveValues after.heap [initial] (fun _ => .cell identity)) .custody
      let heap := { heap with nextCell := heap.nextCell + 1 }
      let (heap, result) ← fromOption (allocateObject heap schema
        (.cell identity schema region (retainAt initial (.cell identity))) owner false) .custody
      finishTemporary { after with heap := heap } result
    | _ => throw .operands
  | .cellGet => match operands with
    | [value] =>
      let (_, .cell _ _ _ content) ← lookupObject state value | throw .type
      require (content.value.schema == schema && Traits.check context.source.schemas .copy schema) .type
      scopedValue state content.value
    | _ => throw .operands
  | .cellSet => match operands with
    | [value, replacement] =>
      let (node, .cell identity cellSchema region content) ← lookupObject state value | throw .type
      require (content.value.schema == replacement.value.schema &&
        Traits.check context.source.schemas .copy replacement.value.schema) .type
      require ((← fromOption context.source.schemas[schema.value]? .type) == .unit) .type
      let heap ← fromOption (replaceObject state.heap node
        (.cell identity cellSchema region (retainAt replacement (.cell identity)))) .reference
      scopedValue { state with heap := heap } (.scalar schema 0)
    | _ => throw .operands
  | .package => match operands with
    | [value] =>
      let (_, .oneShot _) ← lookupObject state value | throw .type
      let .internal (.suspensionPackage input) ← fromOption context.source.schemas[schema.value]? .type | throw .type
      require (input == value.value.schema) .type
      let (after, owner) ← temporary state
      let node : NodeId := ⟨after.heap.objects.length⟩
      let heap ← fromOption (moveValues after.heap [value] (Custody.Owner.closure node)) .custody
      let (heap, result) ← fromOption (allocateObject heap schema
        (.package schema (retainAt value (.closure node 0))) owner true) .custody
      finishTemporary { after with heap := heap } result
    | _ => throw .operands
  | .unpack => match operands with
    | [value] =>
      let (_, .package _ content) ← lookupObject state value | throw .type
      require (content.value.schema == schema) .type
      let heap ← fromOption (retireObject state.heap value) .custody
      commitPure { state with heap := heap } .move [content] content.value
    | _ => throw .operands
  | .cloneResumption => match operands with
    | [value] =>
      let (_, .oneShot capture) ← lookupObject state value | throw .type
      let .internal (.resumption sourceType) ← fromOption context.source.schemas[value.value.schema.value]? .type | throw .type
      let .internal (.resumption resultType) ← fromOption context.source.schemas[schema.value]? .type | throw .type
      require ((sourceType.use == .linear || sourceType.use == .affine) &&
        resultType == { sourceType with use := .multi }) .type
      require (allCaptureCloneSafe context.source state.heap capture) .custody
      let heap ← fromOption (retireObject state.heap value) .custody
      let (after, owner) ← temporary { state with heap := heap }
      let (heap, result) ← fromOption (allocateObject after.heap schema
        (.multiTemplate { capture with schema := schema }) owner false) .custody
      finishTemporary { after with heap := heap } result
    | _ => throw .operands
  | .resourcePack => match operands with
    | [value] =>
      let .internal (.abstractResource descriptor) ← fromOption context.source.schemas[schema.value]? .type | throw .type
      let resource ← fromOption context.source.resources[descriptor.value]? .reference
      let invocation ← fromOption state.heap.invocations[state.invocation.value]? .scope
      require (resource.introducers.contains invocation.function) .custody
      require (resource.representation == value.value.schema && Traits.check context.source.schemas .external value.value.schema) .type
      let (after, owner) ← temporary state
      let node : NodeId := ⟨after.heap.objects.length⟩
      let (heap, result) ← fromOption (allocateObject after.heap schema
        (.resource schema (retainAt value (.closure node 0))) owner true) .custody
      finishTemporary { after with heap := heap } result
    | _ => throw .operands
  | .resourceUnpack => match operands with
    | [value] =>
      let shape ← fromOption context.source.schemas[value.value.schema.value]? .type
      let resourceSchema := match shape with | .internal (.borrowed inner _) => inner | _ => value.value.schema
      let .internal (.abstractResource descriptor) ← fromOption context.source.schemas[resourceSchema.value]? .type | throw .type
      let resource ← fromOption context.source.resources[descriptor.value]? .reference
      let invocation ← fromOption state.heap.invocations[state.invocation.value]? .scope
      require (resource.eliminators.contains invocation.function && resource.representation == schema) .custody
      let (_, object) ← lookupObject state value
      match object with
      | .resource _ content =>
        require (content.value.schema == schema) .type
        let heap ← fromOption (retireObject state.heap value) .custody
        scopedValue { state with heap := heap } content.value
      | .borrow _ resource region _ =>
        let identity ← fromOption ((state.heap.loans.find? (fun entry => entry.1 == region)).map Prod.snd) .scope
        let obligation ← fromOption state.heap.obligations[identity.value]? .scope
        let .pending := obligation.phase | throw .scope
        require (state.stack.any (fun frame => match frame with | .region active => active == region | _ => false)) .scope
        let .resource _ content ← fromOption (state.heap.lookup resource) .reference | throw .type
        require (content.value.schema == schema) .type
        scopedValue state content.value
      | _ => throw .type
    | _ => throw .operands

def executePrimitive (state : State) (context : Context) : Except Invalid Transition := do
  let .execute (.primitive schema opcode immediate failures) _ operands := state.control | throw .inactive
  require (operands.all (current state.heap)) .custody
  match Primitives.evaluate context.source.schemas context.executionConstants opcode schema immediate (operands.map Located.value) with
  | .error _ => throw .type
  | .ok (.fault fault) => authoredFailure state context failures fault
  | .ok (.value value) => commitPure state opcode operands value
  | .ok (.graph operation) => heapPrimitive state context operation schema immediate operands

theorem evaluating_next_operand_preserves_heap (state : State) (value : Located) (intent : Intent)
    (environment : Environment) (next : SourceValueId) (rest : List SourceValueId)
    (evaluated : List Located) (tail : List Frame)
    (control : state.control = .delivered value)
    (stack : state.stack = .operands intent environment (next :: rest) evaluated :: tail) :
    deliverOperand state = .ok ⟨{ state with
      control := .expression next environment
      stack := .operands intent environment rest (evaluated ++ [value]) :: tail }, []⟩ := by
  simp [deliverOperand, control, stack]
  rfl

end BoundaryV2.Profile.Source.Machine
