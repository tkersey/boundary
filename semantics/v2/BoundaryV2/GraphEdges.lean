import BoundaryV2.Traits

namespace BoundaryV2.Profile.Graph

inductive EdgeRole where
  | reference | owned | frame | environment | regionOwner
  deriving DecidableEq, Repr
structure Edge where
  role : EdgeRole
  target : NodeId
  deriving DecidableEq, Repr

def optionalEdges (role : EdgeRole) (target : Option NodeId) : List Edge :=
  target.toList.map (⟨role, ·⟩)

def valueEdges (value : Value) : List Edge := match value.body with
  | .reference node => [⟨.reference, node⟩]
  | .owned owned => [⟨.owned, owned.node⟩]
  | .scalar _ | .blob _ => []

def valuesEdges (values : List Value) : List Edge := values.flatMap valueEdges

def captureEdges (capture : Capture) : List Edge :=
  optionalEdges .frame capture.capture ++ [⟨.reference, capture.delimiter⟩] ++
  optionalEdges .reference capture.evidence ++ valuesEdges capture.useSiteCapabilities

def exitEdges (exit : Exit) : List Edge :=
  (match exit.reason with | .normal value | .failure value => valueEdges value | _ => []) ++
  valuesEdges exit.cleanupFailures ++ optionalEdges .reference exit.stop ++
  optionalEdges .reference exit.outer ++ valuesEdges exit.discarded

/-- Each physical field occurrence appears once. Traversing a shared path a
second time does not add a custodian; two owned fields do add two custodians. -/
def nodeEdges : Node → List Edge
  | .control control =>
    valuesEdges control.arguments ++ optionalEdges .frame control.parent ++
    optionalEdges .reference control.evidence ++ optionalEdges .reference control.region
  | .continuation saved =>
    valuesEdges (saved.arguments.filterMap id) ++ optionalEdges .frame saved.parent ++
    optionalEdges .reference saved.evidence ++ optionalEdges .reference saved.region
  | .handler _ state evidence region =>
    valuesEdges state ++ optionalEdges .reference evidence ++ optionalEdges .reference region
  | .attachment handler outer returnTo _ region =>
    [⟨.reference, handler⟩] ++ optionalEdges .reference outer ++ optionalEdges .frame returnTo ++ optionalEdges .reference region
  | .environment values tail => valuesEdges values ++ optionalEdges .reference tail
  | .aggregate _ _ fields => valuesEdges fields
  | .region _ outer obligations => optionalEdges .reference outer ++ obligations.map (fun value => ⟨.owned, value.node⟩)
  | .regionScope _ region returnTo => [⟨.regionOwner, region⟩] ++ optionalEdges .frame returnTo
  | .injection continuation => [⟨.frame, continuation⟩]
  | .protection _ obligation returnTo evidence region loan =>
    [⟨.owned, obligation.node⟩] ++ optionalEdges .frame returnTo ++ optionalEdges .reference evidence ++
    optionalEdges .reference region ++ optionalEdges .regionOwner loan
  | .cleanupReturn obligation parent exit =>
    [⟨.owned, obligation.node⟩] ++ optionalEdges .frame parent ++ [⟨.reference, exit⟩]
  | .disposalReturn _ parent values => optionalEdges .frame parent ++ valuesEdges values
  | .unwind cursor values => optionalEdges .frame cursor ++ valuesEdges values
  | .cell _ region value => [⟨.reference, region⟩] ++ valuesEdges value.toList
  | .oneShot capture | .multiTemplate capture => captureEdges capture
  | .branch template attachment regions => [⟨.reference, template⟩, ⟨.reference, attachment⟩] ++
    regions.flatMap (fun pair => [⟨.reference, pair.1⟩, ⟨.reference, pair.2⟩])
  | .package _ continuation => valueEdges continuation
  | .computation _ environment => [⟨.environment, environment⟩]
  | .resource _ value => valueEdges value
  | .borrow _ resource region => [⟨.reference, resource⟩, ⟨.reference, region⟩]
  | .obligation _ cleanup resource status =>
    valuesEdges cleanup.toList ++ valuesEdges resource.toList ++
    (match status with
    | .running position => [⟨.reference, position⟩]
    | .failed value => valueEdges value
    | .pending | .completed => [])
  | .pending _ payload continuation _ => valueEdges payload ++ [⟨.frame, continuation⟩]
  | .exit exit => exitEdges exit

def rootEdges (roots : Roots) : List Edge :=
  optionalEdges .frame roots.current ++ optionalEdges .reference roots.evidence ++
  roots.detached.map (fun owned => ⟨.owned, owned.node⟩) ++
  optionalEdges .reference roots.exit ++ optionalEdges .reference roots.pending

inductive OwnerLocation where
  | root : Nat → OwnerLocation
  | node : NodeId → Nat → OwnerLocation
  deriving DecidableEq, Repr
structure LocatedEdge where
  source : OwnerLocation
  edge : Edge
  deriving DecidableEq, Repr

def locatedEdges (state : State) : List LocatedEdge :=
  (rootEdges state.roots).mapIdx (fun index edge => ⟨.root index, edge⟩) ++
  (state.nodes.mapIdx fun index node =>
    (nodeEdges node).mapIdx (fun offset edge => ⟨.node ⟨index⟩ offset, edge⟩)).flatten

def edges (state : State) : List Edge := rootEdges state.roots ++ state.nodes.flatMap nodeEdges

def owningCount (state : State) (role : EdgeRole) (target : NodeId) : Nat :=
  (edges state).countP (fun edge => edge.role == role && edge.target == target)

def isFrame : Node → Bool
  | .control _ | .continuation _ | .attachment .. | .regionScope .. | .injection _
  | .protection .. | .cleanupReturn .. | .disposalReturn .. | .unwind .. => true
  | _ => false

def frameParent : Node → Option NodeId
  | .control value => value.parent
  | .continuation value => value.parent
  | .attachment _ _ returnTo _ _ | .regionScope _ _ returnTo
  | .protection _ _ returnTo _ _ _ => returnTo
  | .injection continuation => some continuation
  | .cleanupReturn _ parent _ | .disposalReturn _ parent _ | .unwind parent _ => parent
  | _ => none

def treeParent : Node → Option NodeId
  | .region _ outer _ => outer
  | .attachment _ outer _ .suspended _ => outer
  | node => frameParent node

def exclusive (program : Target.Program) : Node → Bool
  | .oneShot _ | .package .. | .resource .. | .obligation .. => true
  | .aggregate type _ _ => !Traits.check program.schemas .copy type
  | .computation constructor _ => match program.constructors[constructor.value]? with
    | some definition => !Traits.check program.schemas .copy definition.schema
    | none => true
  | _ => false

/-- This is only custody. Type, scope, identity, pending, and cleanup invariants
are separate obligations of full graph admission. -/
def custody (program : Target.Program) (state : State) : Bool :=
  (edges state).all (fun edge => edge.target.value < state.nodes.length) &&
  state.nodes.zipIdx.all (fun (node, index) =>
    let reference : NodeId := ⟨index⟩
    owningCount state .owned reference == (if exclusive program node then 1 else 0) &&
    (if isFrame node then owningCount state .frame reference == 1 else owningCount state .frame reference == 0) &&
    (match node with
    | .region .. => owningCount state .regionOwner reference == 1
    | _ => owningCount state .regionOwner reference == 0) &&
    (match node with
    | .environment values _ =>
      values.all (fun value => Traits.check program.schemas .copy value.schema || owningCount state .environment reference == 1)
    | _ => owningCount state .environment reference == 0))

def mapValue (rename : NodeId → NodeId) (value : Value) : Value :=
  { value with body := match value.body with
    | .reference node => .reference (rename node)
    | .owned owned => .owned ⟨rename owned.node⟩
    | .scalar bytes => .scalar bytes
    | .blob blob => .blob blob }

def mapCapture (rename : NodeId → NodeId) (capture : Capture) : Capture :=
  { capture with
    capture := capture.capture.map rename
    delimiter := rename capture.delimiter
    evidence := capture.evidence.map rename
    useSiteCapabilities := capture.useSiteCapabilities.map (mapValue rename) }

def mapExit (rename : NodeId → NodeId) (exit : Exit) : Exit :=
  { exit with
    reason := match exit.reason with
      | .normal value => .normal (mapValue rename value)
      | .failure value => .failure (mapValue rename value)
      | .cancellation => .cancellation
      | .abandoned => .abandoned
    cleanupFailures := exit.cleanupFailures.map (mapValue rename)
    stop := exit.stop.map rename
    outer := exit.outer.map rename
    discarded := exit.discarded.map (mapValue rename) }

/-- Renaming never touches nominal/catalog identities or ordinary numbers. -/
def mapNode (rename : NodeId → NodeId) : Node → Node
  | .control value => .control { value with
      arguments := value.arguments.map (mapValue rename)
      parent := value.parent.map rename
      evidence := value.evidence.map rename
      region := value.region.map rename }
  | .continuation value => .continuation { value with
      arguments := value.arguments.map (Option.map (mapValue rename))
      parent := value.parent.map rename
      evidence := value.evidence.map rename
      region := value.region.map rename }
  | .handler definition state evidence region => .handler definition (state.map (mapValue rename)) (evidence.map rename) (region.map rename)
  | .attachment handler outer returnTo phase region => .attachment (rename handler) (outer.map rename) (returnTo.map rename) phase (region.map rename)
  | .environment values tail => .environment (values.map (mapValue rename)) (tail.map rename)
  | .aggregate schema tag fields => .aggregate schema tag (fields.map (mapValue rename))
  | .region descriptor outer obligations => .region descriptor (outer.map rename) (obligations.map (fun value => ⟨rename value.node⟩))
  | .regionScope block region returnTo => .regionScope block (rename region) (returnTo.map rename)
  | .injection continuation => .injection (rename continuation)
  | .protection block obligation returnTo evidence region loan =>
    .protection block ⟨rename obligation.node⟩ (returnTo.map rename) (evidence.map rename) (region.map rename) (loan.map rename)
  | .cleanupReturn obligation parent exit => .cleanupReturn ⟨rename obligation.node⟩ (parent.map rename) (rename exit)
  | .disposalReturn schema parent values => .disposalReturn schema (parent.map rename) (values.map (mapValue rename))
  | .unwind cursor values => .unwind (cursor.map rename) (values.map (mapValue rename))
  | .cell schema region value => .cell schema (rename region) (value.map (mapValue rename))
  | .oneShot capture => .oneShot (mapCapture rename capture)
  | .multiTemplate capture => .multiTemplate (mapCapture rename capture)
  | .branch template attachment regions => .branch (rename template) (rename attachment) (regions.map (fun (a, b) => (rename a, rename b)))
  | .package schema value => .package schema (mapValue rename value)
  | .computation constructor environment => .computation constructor (rename environment)
  | .resource schema value => .resource schema (mapValue rename value)
  | .borrow schema resource region => .borrow schema (rename resource) (rename region)
  | .obligation block cleanup resource status => .obligation block (cleanup.map (mapValue rename)) (resource.map (mapValue rename))
      (match status with
      | .running position => .running (rename position)
      | .failed value => .failed (mapValue rename value)
      | .pending => .pending
      | .completed => .completed)
  | .pending effect payload continuation block => .pending effect (mapValue rename payload) (rename continuation) block
  | .exit exit => .exit (mapExit rename exit)

def mapEdge (rename : NodeId → NodeId) (edge : Edge) : Edge := { edge with target := rename edge.target }

theorem mapValue_edges (rename : NodeId → NodeId) (value : Value) :
    valueEdges (mapValue rename value) = (valueEdges value).map (mapEdge rename) := by
  cases value with
  | mk schema body => cases body <;> rfl

theorem mapValues_edges (rename : NodeId → NodeId) (values : List Value) :
    valuesEdges (values.map (mapValue rename)) = (valuesEdges values).map (mapEdge rename) := by
  simp [valuesEdges, List.flatMap_map, List.map_flatMap, mapValue_edges]

private theorem mapOptional_edges (rename : NodeId → NodeId) (role : EdgeRole) (value : Option NodeId) :
    optionalEdges role (value.map rename) = (optionalEdges role value).map (mapEdge rename) := by
  cases value <;> rfl

theorem mapCapture_edges (rename : NodeId → NodeId) (value : Capture) :
    captureEdges (mapCapture rename value) = (captureEdges value).map (mapEdge rename) := by
  simp [captureEdges, mapCapture, List.map_append, mapOptional_edges, mapValues_edges, mapEdge]

theorem mapExit_edges (rename : NodeId → NodeId) (value : Exit) :
    exitEdges (mapExit rename value) = (exitEdges value).map (mapEdge rename) := by
  cases reason : value.reason <;>
    simp [exitEdges, mapExit, reason, List.map_append, mapOptional_edges, mapValues_edges, mapValue_edges]

private theorem saved_values_map (rename : NodeId → NodeId) (values : List (Option Value)) :
    values.filterMap (fun value => value.map (mapValue rename)) =
      (values.filterMap id).map (mapValue rename) := by
  induction values with
  | nil => rfl
  | cons head tail induction => cases head <;> simp [induction]

theorem mapNode_edges (rename : NodeId → NodeId) (node : Node) :
    nodeEdges (mapNode rename node) = (nodeEdges node).map (mapEdge rename) := by
  cases node <;>
    simp [nodeEdges, mapNode, List.map_append, mapOptional_edges, mapValues_edges,
      mapValue_edges, mapCapture_edges, mapExit_edges, List.map_map,
      List.flatMap_map, List.map_flatMap, Function.comp_def, mapEdge, saved_values_map]
  all_goals first
    | rfl
    | (rename_i status; cases status <;>
        simp [mapValue_edges, valuesEdges, Option.toList_map, List.flatMap_map,
          List.map_flatMap, mapEdge])

theorem injective_renaming_preserves_aliases (rename : NodeId → NodeId)
    (injective : Function.Injective rename) (left right : NodeId) :
    rename left = rename right ↔ left = right := ⟨fun equal => injective equal, congrArg rename⟩

theorem no_owned_edge_hidden_in_aggregate (schema : SchemaId .target) (tag : Nat)
    (fields : List Value) : nodeEdges (.aggregate schema tag fields) = fields.flatMap valueEdges := rfl

theorem equal_owned_fields_are_two_occurrences (schema : SchemaId .target) (target : NodeId) :
    nodeEdges (.aggregate schema 0 [⟨schema, .owned ⟨target⟩⟩, ⟨schema, .owned ⟨target⟩⟩]) =
      [⟨.owned, target⟩, ⟨.owned, target⟩] := rfl

end BoundaryV2.Profile.Graph
