import BoundaryV2.GraphEdges

namespace BoundaryV2.Profile.Graph

/-- Snapshot traversal has two disjoint reference domains. Ordinary integers,
catalog identifiers, scalar bytes and blob bytes are never traversed. -/
inductive Reference where
  | node : NodeId → Reference
  | blob : BlobId → Reference
  deriving DecidableEq, Repr

namespace Reference
def node? : Reference → Option NodeId
  | .node target => some target
  | .blob _ => none
def map (nodes : NodeId → NodeId) (blobs : BlobId → BlobId) : Reference → Reference
  | .node target => .node (nodes target)
  | .blob target => .blob (blobs target)
end Reference

def optionalReferences (value : Option NodeId) : List Reference := value.toList.map .node

def valueReferences (value : Value) : List Reference := match value.body with
  | .scalar _ => []
  | .blob blob => [.blob blob]
  | .reference node => [.node node]
  | .owned owned => [.node owned.node]

def valuesReferences (values : List Value) : List Reference := values.flatMap valueReferences

def captureReferences (capture : Capture) : List Reference :=
  optionalReferences capture.capture ++ [.node capture.delimiter] ++ optionalReferences capture.evidence ++
  valuesReferences capture.useSiteCapabilities

def exitReferences (exit : Exit) : List Reference :=
  (match exit.reason with | .normal value | .failure value => valueReferences value | _ => []) ++
  valuesReferences exit.cleanupFailures ++ optionalReferences exit.stop ++ optionalReferences exit.outer ++
  valuesReferences exit.discarded

/-- The production record field order, including interleaved blob references.
Every physical occurrence is retained, including repeated aliases. -/
def nodeReferences : Node → List Reference
  | .control control => valuesReferences control.arguments ++ optionalReferences control.parent ++
    optionalReferences control.evidence ++ optionalReferences control.region
  | .continuation saved => valuesReferences (saved.arguments.filterMap id) ++ optionalReferences saved.parent ++
    optionalReferences saved.evidence ++ optionalReferences saved.region
  | .handler _ state evidence region => valuesReferences state ++ optionalReferences evidence ++ optionalReferences region
  | .attachment handler outer returnTo _ region =>
    [.node handler] ++ optionalReferences outer ++ optionalReferences returnTo ++ optionalReferences region
  | .environment values tail => valuesReferences values ++ optionalReferences tail
  | .aggregate _ _ fields => valuesReferences fields
  | .region _ outer obligations => optionalReferences outer ++ obligations.map (fun owned => .node owned.node)
  | .regionScope _ region returnTo => [.node region] ++ optionalReferences returnTo
  | .injection continuation => [.node continuation]
  | .protection _ obligation returnTo evidence region loan => [.node obligation.node] ++
    optionalReferences returnTo ++ optionalReferences evidence ++ optionalReferences region ++ optionalReferences loan
  | .cleanupReturn obligation parent exit => [.node obligation.node] ++ optionalReferences parent ++ [.node exit]
  | .disposalReturn _ parent values | .unwind parent values => optionalReferences parent ++ valuesReferences values
  | .cell _ region value => [.node region] ++ valuesReferences value.toList
  | .oneShot capture | .multiTemplate capture => captureReferences capture
  | .branch template attachment regions => [.node template, .node attachment] ++
    regions.flatMap (fun pair => [.node pair.1, .node pair.2])
  | .package _ value | .resource _ value => valueReferences value
  | .computation _ environment => [.node environment]
  | .borrow _ resource region => [.node resource, .node region]
  | .obligation _ cleanup resource status => valuesReferences cleanup.toList ++ valuesReferences resource.toList ++
    (match status with
    | .running position => [.node position]
    | .failed value => valueReferences value
    | .pending | .completed => [])
  | .pending _ payload continuation _ => valueReferences payload ++ [.node continuation]
  | .exit exit => exitReferences exit

def rootReferences (roots : Roots) : List Reference :=
  optionalReferences roots.current ++ optionalReferences roots.evidence ++ roots.detached.map (fun owned => .node owned.node) ++
  optionalReferences roots.exit ++ optionalReferences roots.pending

def mapBlobValue (rename : BlobId → BlobId) (value : Value) : Value :=
  { value with body := match value.body with
    | .blob blob => .blob (rename blob)
    | body => body }

def mapBlobCapture (rename : BlobId → BlobId) (capture : Capture) : Capture :=
  { capture with useSiteCapabilities := capture.useSiteCapabilities.map (mapBlobValue rename) }

def mapBlobExit (rename : BlobId → BlobId) (exit : Exit) : Exit :=
  { exit with
    reason := match exit.reason with
      | .normal value => .normal (mapBlobValue rename value)
      | .failure value => .failure (mapBlobValue rename value)
      | reason => reason
    cleanupFailures := exit.cleanupFailures.map (mapBlobValue rename)
    discarded := exit.discarded.map (mapBlobValue rename) }

def mapBlobNode (rename : BlobId → BlobId) : Node → Node
  | .control value => .control { value with arguments := value.arguments.map (mapBlobValue rename) }
  | .continuation value => .continuation { value with arguments := value.arguments.map (Option.map (mapBlobValue rename)) }
  | .handler definition values evidence region => .handler definition (values.map (mapBlobValue rename)) evidence region
  | .environment values tail => .environment (values.map (mapBlobValue rename)) tail
  | .aggregate schema tag fields => .aggregate schema tag (fields.map (mapBlobValue rename))
  | .disposalReturn schema parent values => .disposalReturn schema parent (values.map (mapBlobValue rename))
  | .unwind cursor values => .unwind cursor (values.map (mapBlobValue rename))
  | .cell schema region value => .cell schema region (value.map (mapBlobValue rename))
  | .oneShot capture => .oneShot (mapBlobCapture rename capture)
  | .multiTemplate capture => .multiTemplate (mapBlobCapture rename capture)
  | .package schema value => .package schema (mapBlobValue rename value)
  | .resource schema value => .resource schema (mapBlobValue rename value)
  | .obligation block cleanup resource status => .obligation block (cleanup.map (mapBlobValue rename))
    (resource.map (mapBlobValue rename)) (match status with
      | .failed value => .failed (mapBlobValue rename value)
      | status => status)
  | .pending effect payload continuation block => .pending effect (mapBlobValue rename payload) continuation block
  | .exit exit => .exit (mapBlobExit rename exit)
  | node => node

def remapNode (nodes : NodeId → NodeId) (blobs : BlobId → BlobId) (node : Node) : Node :=
  mapNode nodes (mapBlobNode blobs node)

def remapRoots (rename : NodeId → NodeId) (roots : Roots) : Roots :=
  ⟨roots.current.map rename, roots.evidence.map rename,
    roots.detached.map (fun owned => ⟨rename owned.node⟩), roots.exit.map rename, roots.pending.map rename⟩

theorem valueReferences_node_projection (value : Value) :
    (valueReferences value).filterMap Reference.node? = (valueEdges value).map Edge.target := by
  cases value with | mk schema body => cases body <;> rfl

theorem valuesReferences_node_projection (values : List Value) :
    (valuesReferences values).filterMap Reference.node? = (valuesEdges values).map Edge.target := by
  simp [valuesReferences, valuesEdges, List.filterMap_flatMap, List.map_flatMap,
    valueReferences_node_projection]

private theorem optional_node_projection (role : EdgeRole) (value : Option NodeId) :
    (optionalEdges role value).map Edge.target = value.toList := by
  cases value <;> rfl

private theorem optional_references_projection (value : Option NodeId) :
    (optionalReferences value).filterMap Reference.node? = value.toList := by
  cases value <;> rfl

theorem captureReferences_node_projection (capture : Capture) :
    (captureReferences capture).filterMap Reference.node? = (captureEdges capture).map Edge.target := by
  simp [captureReferences, captureEdges, List.filterMap_append, List.map_append,
    valuesReferences_node_projection, optional_node_projection, optional_references_projection, Reference.node?]

theorem exitReferences_node_projection (exit : Exit) :
    (exitReferences exit).filterMap Reference.node? = (exitEdges exit).map Edge.target := by
  cases reason : exit.reason <;>
    simp [exitReferences, exitEdges, reason, List.filterMap_append, List.map_append,
      valuesReferences_node_projection, valueReferences_node_projection, optional_node_projection, optional_references_projection]

theorem nodeReferences_node_projection (node : Node) :
    (nodeReferences node).filterMap Reference.node? = (nodeEdges node).map Edge.target := by
  cases node <;>
    simp [nodeReferences, nodeEdges, List.filterMap_append, List.map_append,
      valuesReferences_node_projection, valueReferences_node_projection, optional_node_projection, optional_references_projection,
      captureReferences_node_projection, exitReferences_node_projection, Reference.node?,
      List.filterMap_map, List.filterMap_flatMap, List.map_map, List.map_flatMap, Function.comp_def]
  all_goals first
    | rfl
    | (rename_i status; cases status <;> simp [valueReferences_node_projection, Reference.node?])

theorem rootReferences_node_projection (roots : Roots) :
    (rootReferences roots).filterMap Reference.node? = (rootEdges roots).map Edge.target := by
  simp [rootReferences, rootEdges, List.filterMap_append, List.map_append, optional_node_projection, optional_references_projection,
    Reference.node?, List.filterMap_map, List.map_map, Function.comp_def]

theorem mapValue_references (rename : NodeId → NodeId) (value : Value) :
    valueReferences (mapValue rename value) = (valueReferences value).map (Reference.map rename id) := by
  cases value with | mk schema body => cases body <;> rfl

theorem mapBlobValue_references (rename : BlobId → BlobId) (value : Value) :
    valueReferences (mapBlobValue rename value) = (valueReferences value).map (Reference.map id rename) := by
  cases value with | mk schema body => cases body <;> rfl

private theorem values_map_references (f : Value → Value) (g : Reference → Reference)
    (pointwise : ∀ value, valueReferences (f value) = (valueReferences value).map g) (values : List Value) :
    valuesReferences (values.map f) = (valuesReferences values).map g := by
  simp [valuesReferences, List.flatMap_map, List.map_flatMap, pointwise]

private theorem optional_map_references (rename : NodeId → NodeId) (blobs : BlobId → BlobId) (value : Option NodeId) :
    (optionalReferences value).map (Reference.map rename blobs) = optionalReferences (value.map rename) := by
  cases value <;> rfl

private theorem optional_blob_references (rename : BlobId → BlobId) (value : Option NodeId) :
    (optionalReferences value).map (Reference.map id rename) = optionalReferences value := by
  cases value <;> rfl

private theorem saved_map_references (f : Value → Value) (values : List (Option Value)) :
    values.filterMap (fun value => value.map f) = (values.filterMap id).map f := by
  induction values with
  | nil => rfl
  | cons head tail ih => cases head <;> simp [ih]

theorem mapCapture_references (rename : NodeId → NodeId) (capture : Capture) :
    captureReferences (mapCapture rename capture) = (captureReferences capture).map (Reference.map rename id) := by
  simp [captureReferences, mapCapture, List.map_append, optional_map_references,
    values_map_references _ _ (mapValue_references rename), Reference.map]

theorem mapBlobCapture_references (rename : BlobId → BlobId) (capture : Capture) :
    captureReferences (mapBlobCapture rename capture) = (captureReferences capture).map (Reference.map id rename) := by
  simp [captureReferences, mapBlobCapture, List.map_append, optional_blob_references,
    values_map_references _ _ (mapBlobValue_references rename), Reference.map]

theorem mapExit_references (rename : NodeId → NodeId) (exit : Exit) :
    exitReferences (mapExit rename exit) = (exitReferences exit).map (Reference.map rename id) := by
  cases reason : exit.reason <;>
    simp [exitReferences, mapExit, reason, List.map_append, optional_map_references,
      values_map_references _ _ (mapValue_references rename), mapValue_references]

theorem mapBlobExit_references (rename : BlobId → BlobId) (exit : Exit) :
    exitReferences (mapBlobExit rename exit) = (exitReferences exit).map (Reference.map id rename) := by
  cases reason : exit.reason <;>
    simp [exitReferences, mapBlobExit, reason, List.map_append, optional_blob_references,
      values_map_references _ _ (mapBlobValue_references rename), mapBlobValue_references]

theorem mapNode_references (rename : NodeId → NodeId) (node : Node) :
    nodeReferences (mapNode rename node) = (nodeReferences node).map (Reference.map rename id) := by
  cases node <;>
    simp [nodeReferences, mapNode, List.map_append, optional_map_references,
      values_map_references _ _ (mapValue_references rename), mapValue_references,
      mapCapture_references, mapExit_references, List.map_map, List.flatMap_map,
      List.map_flatMap, Function.comp_def, Reference.map, saved_map_references]
  all_goals first
    | rfl
    | (rename_i status; cases status <;>
        simp [mapValue_references, valuesReferences, Option.toList_map, List.flatMap_map,
          List.map_flatMap, Reference.map])

theorem mapBlobNode_references (rename : BlobId → BlobId) (node : Node) :
    nodeReferences (mapBlobNode rename node) = (nodeReferences node).map (Reference.map id rename) := by
  cases node <;>
    simp [nodeReferences, mapBlobNode, List.map_append, optional_blob_references,
      values_map_references _ _ (mapBlobValue_references rename), mapBlobValue_references,
      mapBlobCapture_references, mapBlobExit_references, List.map_map,
      List.map_flatMap, Function.comp_def, Reference.map, saved_map_references]
  all_goals first
    | rfl
    | (rename_i status; cases status <;>
        simp [mapBlobValue_references, valuesReferences, Option.toList_map, List.flatMap_map,
          List.map_flatMap, Reference.map])

theorem remapNode_references (nodes : NodeId → NodeId) (blobs : BlobId → BlobId) (node : Node) :
    nodeReferences (remapNode nodes blobs node) = (nodeReferences node).map (Reference.map nodes blobs) := by
  rw [remapNode, mapNode_references, mapBlobNode_references, List.map_map]
  apply List.map_congr_left
  intro reference _
  cases reference <;> rfl

theorem remapRoots_references (nodes : NodeId → NodeId) (blobs : BlobId → BlobId) (roots : Roots) :
    rootReferences (remapRoots nodes roots) = (rootReferences roots).map (Reference.map nodes blobs) := by
  simp [rootReferences, remapRoots, List.map_append, optional_map_references, List.map_map,
    Function.comp_def, Reference.map]

end BoundaryV2.Profile.Graph
