import BoundaryV2.TargetControl

namespace BoundaryV2.Profile.Target.Machine

def replaceNode (state : State program) (reference : NodeId) (node : Graph.Node) :
    Except Invalid (State program) := do
  let store ← fromOption (state.store.replace reference node) .reference
  return { state with store := store }

def resumptionType (program : Program) (schema : SchemaId .target) : Except Invalid (ResumptionType .target) := do
  let .internal (.resumption signature) ← fromOption program.schemas[schema.value]? .type | throw .type
  return signature

def cloneCompatible (program : Program) (fromType toType : SchemaId .target) : Bool :=
  match resumptionType program fromType, resumptionType program toType with
  | .ok owned, .ok template =>
    (owned.use == .linear || owned.use == .affine) && template.use == .multi &&
      { owned with use := .multi } == template && Traits.check program.schemas .clone toType
  | _, _ => false

namespace Clone

/-- The captured spine determines fresh frame, handler, and region identities.
The selected delimiter's handler remains outside unless a nested template is
itself copied because one of its borrowed owners changes. -/
def spine (store : Store schemas) (delimiter : NodeId) (includeHandler : Bool) :
    Nat → Option NodeId → Except Invalid (List NodeId)
  | 0, _ => .error .scope
  | _, none => .error .scope
  | depth + 1, some cursor => do
    let node ← fromOption (store.lookup cursor) .reference
    if cursor == delimiter then
      let .attachment handler _ _ _ _ := node | throw .type
      return if includeHandler then [cursor, handler] else [cursor]
    else
      let (extra, parent) ← match node with
        | .continuation saved => pure ([], saved.parent)
        | .attachment handler _ parent _ _ => pure ([handler], parent)
        | .regionScope _ region parent => pure ([region], parent)
        | .injection saved => pure ([], some saved)
        | _ => throw .custody
      return cursor :: (extra ++ (← spine store delimiter includeHandler depth parent))

def captureSpine (store : Store schemas) (capture : Graph.Capture) (includeHandler : Bool) :
    Except Invalid (List NodeId) :=
  spine store capture.delimiter includeHandler (store.nodes.length + 1) capture.capture

def immutable : Graph.Node → Bool
  | .environment .. | .aggregate .. | .computation .. => true
  | _ => false

structure Discovery where
  included : List NodeId := []
  discovered : List NodeId := []
  cells : List NodeId := []
  templates : List NodeId := []
  deriving DecidableEq, Repr

def union (left right : List NodeId) : List NodeId := (left ++ right).eraseDups

def includeNodes (state : Discovery) (nodes : List NodeId) : Discovery :=
  { state with included := union state.included nodes, discovered := union state.discovered nodes }

def templateOwners (store : Store schemas) (capture : Graph.Capture) : Except Invalid (List NodeId) := do
  let .attachment handler outer _ _ _ ← fromOption (store.lookup capture.delimiter) .reference | throw .type
  let .handler _ _ _ region ← fromOption (store.lookup handler) .reference | throw .type
  return outer.toList ++ region.toList

/-- A finite dependency closure, independent of authored execution. Immutable
containers acquire fresh identities precisely when a contained node changes;
cells change with their lexical region, including dependencies through cycles. -/
def expand (store : Store schemas) (state : Discovery) : Except Invalid Discovery := do
  let state ← state.discovered.foldlM (fun state cursor => do
    let node ← fromOption (store.lookup cursor) .reference
    let references := (Graph.nodeEdges node).map Graph.Edge.target
    let state := if immutable node && references.any state.included.contains
      then includeNodes state [cursor] else state
    references.foldlM (fun state reference => do
      let child ← fromOption (store.lookup reference) .reference
      match child with
      | .environment .. | .aggregate .. | .computation .. =>
        return { state with discovered := union state.discovered [reference] }
      | .cell .. => return { state with cells := union state.cells [reference] }
      | .multiTemplate _ => return { state with templates := union state.templates [reference] }
      | _ => pure state) state) state
  let state ← state.cells.foldlM (fun state reference => do
    let .cell _ region _ ← fromOption (store.lookup reference) .reference | throw .type
    return if state.included.contains region then includeNodes state [reference] else state) state
  state.templates.foldlM (fun state reference => do
    if state.included.contains reference then pure state else do
      let .multiTemplate capture ← fromOption (store.lookup reference) .reference | throw .type
      let owners ← templateOwners store capture
      if owners.any state.included.contains then
        return includeNodes state (reference :: (← captureSpine store capture true))
      else pure state) state

def close (store : Store schemas) : Nat → Discovery → Except Invalid Discovery
  | 0, state => do
    require ((← expand store state) == state) .witness
    return state
  | remaining + 1, state => do
    let next ← expand store state
    if next == state then return state else close store remaining next

/-- Four monotone subsets of the finite original graph bound construction.
Closure is rechecked at exhaustion; it cannot manufacture a clone witness. -/
def discover (store : Store schemas) (capture : Graph.Capture) : Except Invalid Discovery := do
  let initial := includeNodes {} (← captureSpine store capture false)
  close store (4 * store.nodes.length + 1) initial

def rename (originals : List NodeId) (fresh : Nat) (node : NodeId) : NodeId :=
  match originals.idxOf? node with
  | some index => ⟨fresh + index⟩
  | none => node

def instantiate (store : Store schemas) (capture : Graph.Capture) :
    Except Invalid (Store schemas × Graph.Capture) := do
  let discovered ← discover store capture
  let originals := discovered.included
  let renamed := rename originals store.nodes.length
  let copies ← originals.mapM fun node => do
    return Graph.mapNode renamed (← fromOption (store.lookup node) .reference)
  return ({ store with nodes := store.nodes ++ copies }, Graph.mapCapture renamed capture)

theorem rename_outside (originals : List NodeId) (fresh : Nat) (node : NodeId)
    (absent : originals.idxOf? node = none) : rename originals fresh node = node := by
  simp [rename, absent]

theorem rename_inside (originals : List NodeId) (fresh : Nat) (node : NodeId) (index : Nat)
    (found : originals.idxOf? node = some index) : (rename originals fresh node).value = fresh + index := by
  simp [rename, found]

theorem reserved_interval (originals : List NodeId) (fresh : Nat) (node : NodeId)
    (member : node ∈ originals) :
    fresh ≤ (rename originals fresh node).value ∧ (rename originals fresh node).value < fresh + originals.length := by
  cases found : originals.idxOf? node with
  | none => exact False.elim ((List.idxOf?_eq_none_iff.mp found) member)
  | some index =>
    obtain ⟨bound, _, _⟩ := List.idxOf?_eq_some_iff.mp found
    rw [rename_inside originals fresh node index found]
    omega

theorem injective_on_captured_nodes (originals : List NodeId) (fresh : Nat) (left right : NodeId)
    (leftMember : left ∈ originals) (rightMember : right ∈ originals)
    (equal : rename originals fresh left = rename originals fresh right) : left = right := by
  cases leftFound : originals.idxOf? left with
  | none => exact False.elim ((List.idxOf?_eq_none_iff.mp leftFound) leftMember)
  | some leftIndex =>
    cases rightFound : originals.idxOf? right with
    | none => exact False.elim ((List.idxOf?_eq_none_iff.mp rightFound) rightMember)
    | some rightIndex =>
      have indices := congrArg Ref.value equal
      simp [rename, leftFound, rightFound] at indices
      obtain ⟨_, leftAt, _⟩ := List.idxOf?_eq_some_iff.mp leftFound
      obtain ⟨_, rightAt, _⟩ := List.idxOf?_eq_some_iff.mp rightFound
      subst rightIndex
      exact leftAt.symm.trans rightAt

theorem borrowed_outside_identity_preserved (originals : List NodeId) (fresh : Nat) (node : NodeId)
    (outside : node ∉ originals) : rename originals fresh node = node :=
  rename_outside originals fresh node (List.idxOf?_eq_none_iff.mpr outside)

theorem fresh_capture_separated_from_old_graph (originals : List NodeId) (fresh : Nat) (inside outside : NodeId)
    (member : inside ∈ originals) (old : outside.value < fresh) : rename originals fresh inside ≠ outside := by
  have lower := (reserved_interval originals fresh inside member).1
  intro equal
  rw [equal] at lower
  omega

theorem successive_capture_intervals_disjoint (first second : List NodeId) (fresh : Nat) (left right : NodeId)
    (leftMember : left ∈ first) (rightMember : right ∈ second) :
    rename first fresh left ≠ rename second (fresh + first.length) right := by
  have upper := (reserved_interval first fresh left leftMember).2
  have lower := (reserved_interval second (fresh + first.length) right rightMember).1
  intro equal
  rw [equal] at upper
  omega

theorem remapping_preserves_every_reference (originals : List NodeId) (fresh : Nat) (node : Graph.Node) :
    Graph.nodeEdges (Graph.mapNode (rename originals fresh) node) =
      (Graph.nodeEdges node).map (Graph.mapEdge (rename originals fresh)) :=
  Graph.mapNode_edges _ _

end Clone

/-- A one-shot token loses its capture before control can enter it. Reusable
templates instead instantiate a separate finite graph with fresh local nodes. -/
def takeCapture (state : State program) (value : Graph.Value) : Except Invalid (State program × Graph.Capture) := do
  let signature ← resumptionType program value.schema
  let reference ← valueReference value
  let node ← fromOption (state.store.lookup reference) .reference
  if signature.use == .multi then
    let .multiTemplate capture := node | throw .type
    require (capture.schema == value.schema && Traits.check program.schemas .clone value.schema) .custody
    let (store, capture) ← Clone.instantiate state.store capture
    return ({ state with store := store }, capture)
  else
    let .oneShot capture := node | throw .type
    require (capture.schema == value.schema && capture.capture.isSome) .custody
    let state ← replaceNode state reference (.oneShot { capture with capture := none })
    return (state, capture)

def activate (state : State program) (capture : Graph.Capture) (after : NodeId) : Except Invalid (State program) := do
  let .attachment handler outer _ _ region ← fromOption (state.store.lookup capture.delimiter) .reference | throw .type
  replaceNode state capture.delimiter (.attachment handler outer (some after) .active region)

/-- These are lexical-context links. Explicit capability values retain their
attachment identity when a shallow delimiter is replaced by the caller. -/
def bypassEvidence (selected : NodeId) (outer : Option NodeId) (node : Graph.Node) : Graph.Node :=
  let bypass := fun link => if link == some selected then outer else link
  match node with
  | .control control => .control { control with evidence := bypass control.evidence }
  | .continuation saved => .continuation { saved with evidence := bypass saved.evidence }
  | .handler definition values evidence region => .handler definition values (bypass evidence) region
  | .attachment handler evidence parent phase region => .attachment handler (bypass evidence) parent phase region
  | .protection block obligation parent evidence region loan => .protection block obligation parent (bypass evidence) region loan
  | .oneShot capture => .oneShot { capture with evidence := bypass capture.evidence }
  | .multiTemplate capture => .multiTemplate { capture with evidence := bypass capture.evidence }
  | node => node

def prepareResumption (state : State program) (capture : Graph.Capture) (after : NodeId) :
    Except Invalid (State program × Option NodeId) := do
  let signature ← resumptionType program capture.schema
  if signature.mode == .deep then return (← activate state capture after, capture.evidence)
  else
    let .attachment _ outer _ _ _ ← fromOption (state.store.lookup capture.delimiter) .reference | throw .type
    let caller ← fromOption (state.store.lookup after) .reference
    let state ← replaceNode state capture.delimiter caller
    return ({ state with store := { state.store with nodes := state.store.nodes.map (bypassEvidence capture.delimiter outer) } },
      if capture.evidence == some capture.delimiter then outer else capture.evidence)

end BoundaryV2.Profile.Target.Machine
