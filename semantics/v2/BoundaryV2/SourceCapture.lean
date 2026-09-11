import BoundaryV2.SourceControl

namespace BoundaryV2.Profile.Source.Machine

/-- Retain only variables demanded by the source continuation, and retain
already evaluated operands in their original order. -/
def restrictEnvironment (environment : Environment) (variables : List VariableId) : Environment :=
  environment.filter (fun binding => variables.contains binding.var)

def continuationVariables (context : Context) (intent : Intent) : List VariableId := match intent with
  | .primitive .. => []
  | .term term =>
    ((Analysis.termChildren term).flatMap fun (child, bound) =>
      ((context.captures.row (.term child)).map Prod.fst).filter (fun var => !bound.contains var)) ++
    (match term with | .call function _ => Analysis.captures context.captures function | _ => [])

def trimFrame (context : Context) : Frame → Frame
  | .binding var next environment scope =>
    .binding var next (restrictEnvironment environment
      (((context.captures.row (.term next)).map Prod.fst).filter (· != var))) scope
  | .operands intent environment remaining evaluated =>
    let vars := remaining.flatMap (fun value => (context.captures.row (.value value)).map Prod.fst)
    .operands intent (restrictEnvironment environment (vars ++ continuationVariables context intent)) remaining evaluated
  | frame => frame

structure Selection where
  inside : List Frame
  activation : Activation
  outside : List Frame

def selectAttachment (identity : AttachmentId) : List Frame → Option Selection
  | [] => none
  | .handler activation :: tail =>
    if identity == activation.identity then some ⟨[], activation, tail⟩
    else (selectAttachment identity tail).map (fun selected => { selected with inside := .handler activation :: selected.inside })
  | frame :: tail => (selectAttachment identity tail).map (fun selected => { selected with inside := frame :: selected.inside })

theorem selection_reconstructs (identity : AttachmentId) (frames : List Frame) (selected : Selection)
    (found : selectAttachment identity frames = some selected) :
    frames = selected.inside ++ .handler selected.activation :: selected.outside := by
  induction frames generalizing selected with
  | nil => simp [selectAttachment] at found
  | cons frame tail induction =>
    cases frame <;> simp only [selectAttachment] at found
    all_goals first
      | (split at found
         · cases found; rfl
         · obtain ⟨next, nextFound, rfl⟩ := Option.map_eq_some_iff.mp found
           simp only [induction next nextFound, List.cons_append])
      | (obtain ⟨next, nextFound, rfl⟩ := Option.map_eq_some_iff.mp found
         simp only [induction next nextFound, List.cons_append])

def valueReferences : SemanticValue → List NodeId
  | .reference _ reference _ => [reference]
  | .product _ fields | .sequence _ fields => fields.flatMap valueReferences
  | .variant _ _ payload => valueReferences payload
  | .scalar .. | .blob .. => []

def exitValues (exit : Cleanup.Exit .source) : List SemanticValue :=
  (match exit.primary with | .normal value | .failure value => [value] | _ => []) ++ exit.failures

def frameReferences (frame : Frame) : List NodeId :=
  (frameValues frame).flatMap (fun value => valueReferences value.value) ++
  (match frame with
    | .cleanupReturn _ _ exit normal => (exitValues exit).flatMap valueReferences ++ normal.toList.flatMap (fun value => valueReferences value.value)
    | .disposalReturn values _ _ _ => values.flatMap (fun value => valueReferences value.value)
    | .releaseReturn _ (.deliver value) => valueReferences value.value
    | .releaseReturn _ (.unwind exit) => (exitValues exit).flatMap valueReferences
    | _ => [])

def activationReferences (activation : Activation) : List NodeId :=
  (activation.environment.map Binding.located ++ activation.state).flatMap (fun value => valueReferences value.value)

def captureReferences (capture : Capture) : List NodeId :=
  capture.frames.flatMap frameReferences ++ activationReferences capture.delimiter ++
  capture.useSiteCapabilities.flatMap (fun value => valueReferences value.value) ++
  capture.frozenCells.flatMap (fun cell => cell.node :: valueReferences cell.content.value)

def objectReferences : Object → List NodeId
  | .closure _ _ environment => environment.flatMap (fun binding => valueReferences binding.located.value)
  | .cell _ _ _ value | .package _ value | .resource _ value => valueReferences value.value
  | .oneShot capture | .multiTemplate capture => captureReferences capture
  | .borrow _ resource _ _ => [resource]
  | .capability .. | .region .. => []

/-- The finite graph walk follows dormant templates. Outside mutable cells stop
traversal because a branch must read their current storage. -/
def cloneChildren (heap : Heap) (localRegions : List RegionInstanceId) (reference : NodeId) : List NodeId :=
  match heap.lookup reference with
  | some (.cell _ _ region content) => if localRegions.contains region then valueReferences content.value else []
  | some (.region ..) | some (.capability ..) => []
  | some object => objectReferences object
  | none => []

def expandCloneSupport (heap : Heap) (localRegions : List RegionInstanceId) (support : List NodeId) : List NodeId :=
  (support ++ support.flatMap (cloneChildren heap localRegions)).eraseDups

def cloneSupport (heap : Heap) (capture : Capture) : List NodeId :=
  (List.range heap.objects.length).foldl (fun support _ => expandCloneSupport heap capture.localRegions support)
    (captureReferences capture).eraseDups

structure Renaming where
  nodes : List (NodeId × NodeId) := []
  attachments : List (AttachmentId × AttachmentId) := []
  regions : List (RegionInstanceId × RegionInstanceId) := []
  cells : List (CellId × CellId) := []
  scopes : List (LexicalScopeId × LexicalScopeId) := []
  invocations : List (InvocationId × InvocationId) := []

def renamed [BEq α] (mapping : List (α × α)) (value : α) : α :=
  ((mapping.find? (fun entry => entry.1 == value)).map Prod.snd).getD value

def renameOwner (mapping : Renaming) : Custody.Owner → Custody.Owner
  | .lexical scope index => .lexical (renamed mapping.scopes scope) index
  | .temporary scope index => .temporary (renamed mapping.scopes scope) index
  | .closure node index => .closure (renamed mapping.nodes node) index
  | .frame node index => .frame (renamed mapping.nodes node) index
  | .cell cell => .cell (renamed mapping.cells cell)
  | .unwind scope index => .unwind (renamed mapping.scopes scope) index
  | .receiver invocation index => .receiver (renamed mapping.invocations invocation) index
  | owner => owner

def renameValue (mapping : Renaming) : SemanticValue → SemanticValue
  | .reference schema node token => .reference schema (renamed mapping.nodes node) token
  | .product schema fields => .product schema (fields.map (renameValue mapping))
  | .sequence schema fields => .sequence schema (fields.map (renameValue mapping))
  | .variant schema tag payload => .variant schema tag (renameValue mapping payload)
  | value => value

def renameLocated (mapping : Renaming) (value : Located) : Located :=
  ⟨renameValue mapping value.value, renameOwner mapping value.owner⟩

def renameEnvironment (mapping : Renaming) (environment : Environment) : Environment :=
  environment.map (fun binding => { binding with located := renameLocated mapping binding.located })

def renameExit (mapping : Renaming) (exit : Cleanup.Exit .source) : Cleanup.Exit .source :=
  { exit with
    primary := match exit.primary with
      | .normal value => .normal (renameValue mapping value)
      | .failure value => .failure (renameValue mapping value)
      | primary => primary
    failures := exit.failures.map (renameValue mapping) }

def renameAfter (mapping : Renaming) : AfterRelease → AfterRelease
  | .deliver value => .deliver (renameLocated mapping value)
  | .unwind exit => .unwind (renameExit mapping exit)

def renameActivation (mapping : Renaming) (activation : Activation) : Activation :=
  { activation with
    identity := renamed mapping.attachments activation.identity
    environment := renameEnvironment mapping activation.environment
    state := activation.state.map (renameLocated mapping)
    invocation := renamed mapping.invocations activation.invocation
    scope := renamed mapping.scopes activation.scope
    outer := activation.outer.map (renamed mapping.attachments) }

def renameFrame (mapping : Renaming) : Frame → Frame
  | .binding var term environment scope => .binding var term (renameEnvironment mapping environment) (renamed mapping.scopes scope)
  | .operands intent environment remaining evaluated =>
    .operands intent (renameEnvironment mapping environment) remaining (evaluated.map (renameLocated mapping))
  | .invocation invocation scope => .invocation (renamed mapping.invocations invocation) (renamed mapping.scopes scope)
  | .restore invocation scope => .restore (renamed mapping.invocations invocation) (renamed mapping.scopes scope)
  | .lexical scope => .lexical (renamed mapping.scopes scope)
  | .handler activation => .handler (renameActivation mapping activation)
  | .region region => .region (renamed mapping.regions region)
  | .protection obligation => .protection obligation
  | .cleanupReturn obligation invocation exit normal => .cleanupReturn obligation (renamed mapping.invocations invocation)
    (renameExit mapping exit) (normal.map (renameLocated mapping))
  | .disposalReturn values after invocation scope => .disposalReturn (values.map (renameLocated mapping))
    (renameAfter mapping after) (renamed mapping.invocations invocation) (renamed mapping.scopes scope)
  | .injection values => .injection (values.map (renameLocated mapping))
  | .releaseReturn scope after => .releaseReturn (renamed mapping.scopes scope) (renameAfter mapping after)

def renameCapture (mapping : Renaming) (capture : Capture) : Capture :=
  { capture with
    frames := capture.frames.map (renameFrame mapping)
    delimiter := renameActivation mapping capture.delimiter
    useSiteCapabilities := capture.useSiteCapabilities.map (renameLocated mapping)
    localRegions := capture.localRegions.map (renamed mapping.regions)
    frozenCells := capture.frozenCells.map (fun cell => {
      node := renamed mapping.nodes cell.node
      identity := renamed mapping.cells cell.identity
      region := renamed mapping.regions cell.region
      content := renameLocated mapping cell.content })
    scope := renamed mapping.scopes capture.scope
    invocation := renamed mapping.invocations capture.invocation }

def renameObject (mapping : Renaming) : Object → Object
  | .closure schema function environment => .closure schema function (renameEnvironment mapping environment)
  | .capability identity effect => .capability (renamed mapping.attachments identity) effect
  | .region identity descriptor invocation outer => .region (renamed mapping.regions identity) descriptor
    (renamed mapping.invocations invocation) (outer.map (renamed mapping.regions))
  | .cell identity schema region content => .cell (renamed mapping.cells identity) schema
    (renamed mapping.regions region) (renameLocated mapping content)
  | .oneShot capture => .oneShot (renameCapture mapping capture)
  | .multiTemplate capture => .multiTemplate (renameCapture mapping capture)
  | .package schema content => .package schema (renameLocated mapping content)
  | .resource schema content => .resource schema (renameLocated mapping content)
  | .borrow schema resource region invocation => .borrow schema (renamed mapping.nodes resource)
    (renamed mapping.regions region) (renamed mapping.invocations invocation)

def freshMap (space : Space) (domain : Domain) (start : Nat) (identities : List (Ref space domain)) :=
  identities.eraseDups.mapIdx (fun index identity => (identity, (⟨start + index⟩ : Ref space domain)))

def instantiateCapture (state : State) (context : Context) (capture : Capture) : Except Invalid (State × Capture) := do
  require (allCaptureCloneSafe context.source state.heap capture) .custody
  let support := cloneSupport state.heap capture
  require (support.all (fun node => (state.heap.lookup node).isSome)) .reference
  require ((support.flatMap (cloneChildren state.heap capture.localRegions)).all support.contains) .reference
  let dormant := support.filterMap (fun node => match state.heap.lookup node with
    | some (.multiTemplate inner) => some inner | _ => none)
  require (dormant.all (allCaptureCloneSafe context.source state.heap)) .custody
  let scopes := (captureScopes capture ++ dormant.flatMap captureScopes).eraseDups
  let invocations := (captureInvocations capture ++ dormant.flatMap captureInvocations).eraseDups
  let regions := (capture.localRegions ++ dormant.flatMap Capture.localRegions).eraseDups
  let attachments := (capture.delimiter.identity :: activeAttachments capture.frames ++
    dormant.flatMap (fun inner => inner.delimiter.identity :: activeAttachments inner.frames)).eraseDups
  let copyNodes := support.filter fun node => match state.heap.lookup node with
    | some (.cell _ _ region _) | some (.region region _ _ _) => regions.contains region
    | some (.capability identity _) => attachments.contains identity
    | some (.closure ..) | some (.multiTemplate _) => true
    | _ => false
  let cells := copyNodes.filterMap (fun node => match state.heap.lookup node with
    | some (.cell identity _ _ _) => some identity | _ => none)
  let mapping : Renaming := {
    nodes := freshMap .runtime .node state.heap.objects.length copyNodes
    attachments := freshMap .runtime .attachment state.heap.nextAttachment attachments
    regions := freshMap .runtime .regionInstance state.heap.nextRegion regions
    cells := freshMap .runtime .cell state.heap.nextCell cells
    scopes := freshMap .runtime .lexicalScope state.heap.nextScope scopes
    invocations := freshMap .runtime .invocation state.heap.nextInvocation invocations }
  let copied ← copyNodes.mapM fun node => do
    let object ← fromOption (state.heap.lookup node) .reference
    let object := match object with
      | .cell identity schema region content =>
        let frozen := (capture.frozenCells ++ dormant.flatMap Capture.frozenCells).find? (fun saved => saved.node == node)
        .cell identity schema region ((frozen.map FrozenCell.content).getD content)
      | object => object
    pure (some (renameObject mapping object))
  let newScopes ← scopes.mapM fun scope => do
    let original ← fromOption state.heap.scopes[scope.value]? .scope
    pure { original with
      id := renamed mapping.scopes scope
      invocation := renamed mapping.invocations original.invocation
      parent := original.parent.map (renamed mapping.scopes)
      holdings := [] }
  let newInvocations ← invocations.mapM fun invocation => do
    let original ← fromOption state.heap.invocations[invocation.value]? .scope
    pure { original with
      id := renamed mapping.invocations invocation
      capabilityParents := original.capabilityParents.map (renamed mapping.attachments)
      regionParents := original.regionParents.map (renamed mapping.regions) }
  let heap := { state.heap with
    objects := state.heap.objects ++ copied
    scopes := state.heap.scopes ++ newScopes
    invocations := state.heap.invocations ++ newInvocations
    nextScope := state.heap.nextScope + scopes.length
    nextInvocation := state.heap.nextInvocation + invocations.length
    nextAttachment := state.heap.nextAttachment + attachments.length
    nextRegion := state.heap.nextRegion + regions.length
    nextCell := state.heap.nextCell + cells.length }
  return ({ state with heap := heap }, renameCapture mapping capture)

/-- Literal numbers and nominal catalog identities are never in runtime maps. -/
theorem rename_scalar_preserves_payload (mapping : Renaming) (schema : SchemaId .source) (value : Int) :
    renameValue mapping (.scalar schema value) = .scalar schema value := by simp [renameValue]

theorem rename_same_reference_preserves_alias (mapping : Renaming) (schema firstSchema : SchemaId .source)
    (node : NodeId) :
    renameValue mapping (.reference schema node none) = .reference schema (renamed mapping.nodes node) none ∧
    renameValue mapping (.reference firstSchema node none) = .reference firstSchema (renamed mapping.nodes node) none := by simp [renameValue]

end BoundaryV2.Profile.Source.Machine
