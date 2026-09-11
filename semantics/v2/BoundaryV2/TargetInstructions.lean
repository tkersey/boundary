import BoundaryV2.TargetClone

namespace BoundaryV2.Profile.Target.Machine

def materialize (state : State program) (value : SemanticValue) : Except Invalid (State program × Graph.Value) := do
  let (store, value) ← storeValue state.store value
  return ({ state with store := store }, value)

def scalar (state : State program) (schema : SchemaId .target) (value : Int) : Except Invalid (State program × Graph.Value) :=
  materialize state (.scalar schema value)

/-- Internal aggregates retain the supplied physical fields and their aliases.
External aggregates instead use the uniquely checked canonical byte encoding. -/
def aggregate (state : State program) (schema : SchemaId .target) (tag : Nat) (fields : List Graph.Value) :
    Except Invalid (State program × Graph.Value) := do
  let shape ← fromOption program.schemas[schema.value]? .type
  match shape with
  | .product types => require (tag == 0 && fields.map Graph.Value.schema == types) .type
  | .sum types =>
    let [field] := fields | throw .type
    require (tag < wordLimit && types[tag]? == some field.schema) .type
  | .seq _ | .vector .. | .array .. =>
    require (tag == 0 && Profile.Value.sequenceLengthValid shape fields.length &&
      fields.all (fun field => Profile.Value.sequenceElement shape == some field.schema)) .type
  | _ => throw .type
  if Traits.check program.schemas .external schema then
    let meanings ← fields.mapM (loadValue state.store)
    let value ← match shape, meanings with
      | .product _, _ => pure (.product schema meanings)
      | .sum _, [payload] => pure (.variant schema tag payload)
      | .seq _, _ | .vector .., _ | .array .., _ => pure (.sequence schema meanings)
      | _, _ => throw .type
    materialize state value
  else
    let (store, node) := state.store.add (.aggregate schema tag fields)
    return ({ state with store := store }, reference program.schemas schema node)

def splitAggregate (state : State program) (value : Graph.Value) :
    Except Invalid (State program × Nat × List Graph.Value) := do
  let meaning ← loadValue state.store value
  match value.body with
  | .reference node | .owned ⟨node⟩ =>
    let .aggregate _ tag fields ← fromOption (state.store.lookup node) .reference | throw .type
    return (state, tag, fields)
  | _ =>
    let (tag, fields) ← match meaning with
      | .product _ fields | .sequence _ fields => pure (0, fields)
      | .variant _ tag payload => pure (tag, [payload])
      | _ => throw .type
    let (state, fields) ← fields.foldlM (fun (state, prior) field => do
      let (state, field) ← materialize state field
      pure (state, prior ++ [field])) (state, [])
    return (state, tag, fields)

def natural (state : State program) (value : Graph.Value) : Except Invalid Nat := do
  let .scalar _ number ← loadValue state.store value | throw .type
  require (0 ≤ number && number < wordLimit) .type
  return number.toNat

/-- The shared primitive evaluator checks ordered faults before these graph
realizations. These cases preserve references when projecting or moving an
internal value, rather than reconstructing its immutable aggregate subtree. -/
def realizeValue (state : State program) (instruction : Instruction) (operands : List Graph.Value)
    (meaning : SemanticValue) : Except Invalid (State program × Graph.Value) := do
  let type := instruction.resultType
  match instruction.opcode, operands with
  | .move, [value] => pure (state, value)
  | .select, [condition, yes, no] => pure (state, if (← natural state condition) == 1 then yes else no)
  | .product, _ | .variant, _ | .sequence, _ => aggregate state type instruction.immediate operands
  | .field, [source] =>
    let (state, _, fields) ← splitAggregate state source
    return (state, ← fromOption fields[instruction.immediate]? .operands)
  | .variantPayload, [source] =>
    let (state, _, fields) ← splitAggregate state source
    return (state, ← fromOption fields[0]? .operands)
  | .sequenceAppend, [source, item] =>
    let (state, _, fields) ← splitAggregate state source
    aggregate state type 0 (fields ++ [item])
  | .sequenceConcat, [left, right] =>
    let (state, _, a) ← splitAggregate state left
    let (state, _, b) ← splitAggregate state right
    aggregate state type 0 (a ++ b)
  | .sequenceSet, [source, index, item] =>
    let selected ← natural state index
    let (state, _, fields) ← splitAggregate state source
    aggregate state type 0 (fields.set selected item)
  | .sequenceTake, [source, index] =>
    let selected ← natural state index
    let (state, _, fields) ← splitAggregate state source
    aggregate state type 0 (fields.take selected)
  | .sequenceGet, [source, index] =>
    let selected ← natural state index
    let (state, _, fields) ← splitAggregate state source
    let .sum [empty, _] ← fromOption program.schemas[type.value]? .type | throw .type
    match fields[selected]? with
    | some item => aggregate state type 1 [item]
    | none =>
      let (state, unit) ← scalar state empty 0
      aggregate state type 0 [unit]
  | .sequencePop, [source] =>
    let (state, _, fields) ← splitAggregate state source
    let .sum [empty, pair] ← fromOption program.schemas[type.value]? .type | throw .type
    match fields with
    | [] =>
      let (state, unit) ← scalar state empty 0
      aggregate state type 0 [unit]
    | head :: tail =>
      let (state, tail) ← aggregate state source.schema 0 tail
      let (state, pair) ← aggregate state pair 0 [head, tail]
      aggregate state type 1 [pair]
  | .sequencePopLast, [source] =>
    let (state, _, fields) ← splitAggregate state source
    let .product [_, optional] ← fromOption program.schemas[type.value]? .type | throw .type
    let .sum [empty, _] ← fromOption program.schemas[optional.value]? .type | throw .type
    let (state, rest) ← aggregate state source.schema 0 fields.dropLast
    let (state, last) ← match fields.getLast? with
      | some item => aggregate state optional 1 [item]
      | none => do
        let (state, unit) ← scalar state empty 0
        aggregate state optional 0 [unit]
    aggregate state type 0 [rest, last]
  | _, _ => materialize state meaning

def capturedCloneSafe (state : State program) (capture : Graph.Capture) : Except Invalid Unit := do
  let discovery ← Clone.discover state.store capture
  discovery.included.forM fun reference => do
    let node ← fromOption (state.store.lookup reference) .reference
    let fields ← match node with
      | .continuation saved => pure (saved.arguments.filterMap id)
      | .handler _ fields _ _ | .environment fields _ | .aggregate _ _ fields => pure fields
      | .cell _ _ value => pure value.toList
      | .region _ _ obligations => require obligations.isEmpty .custody; pure []
      | .protection .. | .cleanupReturn .. | .obligation .. | .oneShot _ | .resource .. | .package .. => throw .custody
      | _ => pure []
    require (fields.all (fun value => Traits.check program.schemas .clone value.schema)) .custody

def graphInstruction (state : State program) (control : Graph.Control) (instruction : Instruction)
    (operation : Primitives.GraphOperation) (operands : List Graph.Value) :
    Except Invalid (State program × Graph.Value) := do
  let type := instruction.resultType
  let shape ← fromOption program.schemas[type.value]? .type
  match operation, operands with
  | .computation, fields =>
    let .internal (.computation signature) := shape | throw .type
    let definition ← fromOption program.constructors[instruction.immediate]? .reference
    let capture ← fromOption program.scopes.captures[definition.capture.value]? .reference
    let function ← fromOption program.functions[definition.function.value]? .reference
    require (definition.schema == type && fields.map Graph.Value.schema == capture.fields &&
      function.parameters == capture.fields ++ signature.parameters && function.result == signature.result) .type
    let (store, environment) := state.store.add (.environment fields none)
    let (store, node) := store.add (.computation ⟨instruction.immediate⟩ environment)
    return ({ state with store := store }, reference program.schemas type node)
  | .cellNew, [regionValue, value] =>
    let .internal (.cell element descriptor) := shape | throw .type
    require (value.schema == element &&
      program.schemas[regionValue.schema.value]? == some (.internal (.region descriptor))) .type
    let region ← valueReference regionValue
    let .region actual _ _ ← fromOption (state.store.lookup region) .reference | throw .type
    require (actual == descriptor) .scope
    let (store, node) := state.store.add (.cell type region (some value))
    return ({ state with store := store }, ⟨type, .reference node⟩)
  | .cellGet, [cell] =>
    let .cell actual _ value ← fromOption (state.store.lookup (← valueReference cell)) .reference | throw .type
    require (actual == cell.schema) .type
    let value ← fromOption value .custody
    require (value.schema == type) .type
    return (state, value)
  | .cellSet, [cell, value] =>
    require (shape == .unit) .type
    let reference ← valueReference cell
    let .cell actual region _ ← fromOption (state.store.lookup reference) .reference | throw .type
    let .internal (.cell element _) ← fromOption program.schemas[actual.value]? .type | throw .type
    require (actual == cell.schema && value.schema == element) .type
    let state ← replaceNode state reference (.cell actual region (some value))
    scalar state type 0
  | .package, [value] =>
    let .internal (.suspensionPackage element) := shape | throw .type
    require (value.schema == element) .type
    let (store, node) := state.store.add (.package type value)
    return ({ state with store := store }, ⟨type, .owned ⟨node⟩⟩)
  | .unpack, [value] =>
    let .package actual inner ← fromOption (state.store.lookup (← valueReference value)) .reference | throw .type
    require (actual == value.schema && inner.schema == type) .type
    return (state, inner)
  | .resourcePack, [value] =>
    let .internal (.abstractResource descriptor) := shape | throw .type
    let resource ← fromOption program.scopes.resources[descriptor.value]? .reference
    let block ← fromOption program.blocks[control.block.value]? .reference
    require (value.schema == resource.representation && resource.introducers.contains block.function) .type
    let (store, node) := state.store.add (.resource type value)
    return ({ state with store := store }, ⟨type, .owned ⟨node⟩⟩)
  | .resourceUnpack, [value] =>
    let node ← fromOption (state.store.lookup (← valueReference value)) .reference
    let node ← match node with
      | .borrow actual resource _ =>
        require (actual == value.schema) .type
        fromOption (state.store.lookup resource) .reference
      | node => pure node
    let .resource actual inner := node | throw .type
    let .internal (.abstractResource descriptor) ← fromOption program.schemas[actual.value]? .type | throw .type
    let resource ← fromOption program.scopes.resources[descriptor.value]? .reference
    let block ← fromOption program.blocks[control.block.value]? .reference
    require (inner.schema == type && resource.eliminators.contains block.function) .type
    return (state, inner)
  | .cloneResumption, [value] =>
    require (cloneCompatible program value.schema type) .custody
    let (state, capture) ← takeCapture state value
    capturedCloneSafe state capture
    let (store, node) := state.store.add (.multiTemplate { capture with schema := type })
    return ({ state with store := store }, ⟨type, .reference node⟩)
  | _, _ => throw .operands

inductive InstructionResult (program : Program) where
  | value : State program → Graph.Value → InstructionResult program
  | fault : State program → Graph.Value → InstructionResult program

def evaluateInstruction (context : Context) (state : State context.program) (control : Graph.Control)
    (instruction : Instruction) (values : List Graph.Value) : Except Invalid (InstructionResult context.program) := do
  let operands ← slots values instruction.operands
  let meanings ← operands.mapM (loadValue state.store)
  let result ← match Primitives.evaluate context.program.schemas (context.constants.map StoredBlob.meaning)
      instruction.opcode instruction.resultType instruction.immediate meanings with
    | .ok result => pure result
    | .error _ => throw .type
  match result with
  | .value meaning =>
    let (state, value) ← realizeValue state instruction operands meaning
    return .value state value
  | .fault kind =>
    let failure ← fromOption (instruction.failures.find? (fun failure => failure.kind == kind)) .type
    let literal ← fromOption context.constants[failure.value.value]? .reference
    require (literal.raw.schema == context.program.roots.failure) .type
    let (state, value) ← materialize state literal.meaning
    return .fault state value
  | .graph operation =>
    let (state, value) ← graphInstruction state control instruction operation operands
    return .value state value

/-- A fault retains the exact successful instruction prior and live slots.
The unwind transition, rather than the evaluator, receives their custody. -/
inductive BlockResult (program : Program) where
  | complete : State program → List Graph.Value → BlockResult program
  | failed : State program → Graph.Value → List Graph.Value → List Instruction → BlockResult program

def evaluateInstructions (context : Context) (control : Graph.Control) :
    List Instruction → State context.program → List Graph.Value → List Instruction → Except Invalid (BlockResult context.program)
  | [], state, values, _ => .ok (.complete state values)
  | instruction :: rest, state, values, prior => do
    match ← evaluateInstruction context state control instruction values with
    | .value state value => evaluateInstructions context control rest state (values ++ [value]) (prior ++ [instruction])
    | .fault state failure => return .failed state failure values prior

def evaluateBlock (context : Context) (state : State context.program) (control : Graph.Control) :
    Except Invalid (BlockResult context.program) := do
  let block ← fromOption context.program.blocks[control.block.value]? .reference
  require (control.arguments.map Graph.Value.schema == block.parameters) .type
  evaluateInstructions context control block.instructions state control.arguments []

theorem first_instruction_fault_preserves_prefix (context : Context) (control : Graph.Control)
    (instruction : Instruction) (rest : List Instruction) (state failed : State context.program)
    (values : List Graph.Value) (prior : List Instruction) (failure : Graph.Value)
    (fault : evaluateInstruction context state control instruction values = .ok (.fault failed failure)) :
    evaluateInstructions context control (instruction :: rest) state values prior =
      .ok (.failed failed failure values prior) := by
  simp [evaluateInstructions, fault]
  rfl

end BoundaryV2.Profile.Target.Machine
