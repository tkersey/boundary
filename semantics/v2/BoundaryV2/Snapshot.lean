import BoundaryV2.GraphReferences
import BoundaryV2.Images

namespace BoundaryV2.Profile.Graph.Snapshot

structure Discovery where
  order : List NodeId := []
  blobs : List Blob := []
  deriving DecidableEq, Repr

/-- Preorder depth-first traversal. The decreasing measure counts unvisited
nodes, then pending references. Cycles terminate by removing each newly visited
node from the finite inventory; this is unrelated to machine execution fuel. -/
def walk (state : State) (remaining : List NodeId) (pending : List Reference) (found : Discovery) :
    Option Discovery :=
  match pending with
  | [] => some found
  | .node reference :: tail =>
    match state.nodes[reference.value]? with
    | none => none
    | some node =>
      if _fresh : reference ∈ remaining then
        walk state (remaining.erase reference) (nodeReferences node ++ tail)
          { found with order := found.order ++ [reference] }
      else walk state remaining tail found
  | .blob reference :: tail =>
    match state.blobs[reference.value]? with
    | none => none
    | some blob => walk state remaining tail
      { found with blobs := if blob ∈ found.blobs then found.blobs else found.blobs ++ [blob] }
termination_by (remaining.length, pending.length)
decreasing_by
  all_goals simp_wf
  · have size := List.length_erase_of_mem _fresh
    have positive : 0 < remaining.length := List.length_pos_of_mem _fresh
    omega
  all_goals exact Prod.Lex.right _ (by omega)

def discover (state : State) : Option Discovery :=
  walk state ((List.range state.nodes.length).map (fun index => ⟨index⟩)) (rootReferences state.roots) {}

def renameNode (found : Discovery) (reference : NodeId) : NodeId := ⟨found.order.idxOf reference⟩

def renameBlob (state : State) (found : Discovery) (reference : BlobId) : BlobId :=
  ⟨match state.blobs[reference.value]? with
    | some blob => found.blobs.idxOf blob
    | none => found.blobs.length⟩

def materialize (state : State) (found : Discovery) : Option State := do
  let nodes ← found.order.mapM (fun reference => do
    let node ← state.nodes[reference.value]?
    return remapNode (renameNode found) (renameBlob state found) node)
  return { state with
    roots := remapRoots (renameNode found) state.roots
    nodes := nodes
    blobs := found.blobs }

/-- Garbage is omitted, distinct nodes are retained, and full equal blobs are
interned in first-encounter order. No hash injectivity assumption is used. -/
def canonicalize (state : State) : Option State := do
  let found ← discover state
  materialize state found

def encode (state : State) : Option Bytes := do
  let normalized ← canonicalize state
  if Images.rawState.valid normalized then some (Images.rawState.encode normalized) else none

/-- PST2 decoding includes canonical graph admission, separate from the
program-relative typing, custody and scope obligations. -/
def decode (bytes : Bytes) : Option State := do
  let (state, rest) ← Images.rawState.read bytes
  if !rest.isEmpty then none else do
    let normalized ← canonicalize state
    if normalized == state then some state else none

theorem walk_preserves_discovery (state : State) (remaining : List NodeId) (pending : List Reference)
    (found result : Discovery) (accepted : walk state remaining pending found = some result) :
    found.order ⊆ result.order ∧ found.blobs ⊆ result.blobs := by
  induction remaining, pending, found using walk.induct state generalizing result with
  | case1 remaining found =>
    simp only [walk, Option.some.injEq] at accepted
    cases accepted
    exact ⟨List.Subset.refl _, List.Subset.refl _⟩
  | case2 remaining found reference tail absent => simp [walk, absent] at accepted
  | case3 remaining found reference tail node atNode fresh ih =>
    simp only [walk, atNode, fresh, ↓reduceDIte] at accepted
    have next := ih result accepted
    exact ⟨fun _ member => next.1 (List.mem_append_left _ member), next.2⟩
  | case4 remaining found reference tail node atNode old ih =>
    simp only [walk, atNode, old, ↓reduceDIte] at accepted
    exact ih result accepted
  | case5 remaining found reference tail absent => simp [walk, absent] at accepted
  | case6 remaining found reference tail blob atBlob ih =>
    simp only [walk, atBlob] at accepted
    have next := ih result accepted
    refine ⟨next.1, fun reference member => next.2 ?_⟩
    split <;> simp_all

theorem walk_does_not_duplicate (state : State) (remaining : List NodeId) (pending : List Reference)
    (found result : Discovery) (accepted : walk state remaining pending found = some result)
    (unvisitedUnique : remaining.Nodup) (foundUnique : found.order.Nodup) (blobsUnique : found.blobs.Nodup)
    (separate : ∀ reference ∈ found.order, reference ∉ remaining) :
    result.order.Nodup ∧ result.blobs.Nodup := by
  induction remaining, pending, found using walk.induct state generalizing result with
  | case1 remaining found =>
    simp only [walk, Option.some.injEq] at accepted
    cases accepted
    exact ⟨foundUnique, blobsUnique⟩
  | case2 remaining found reference tail absent => simp [walk, absent] at accepted
  | case3 remaining found reference tail node atNode fresh ih =>
    simp only [walk, atNode, fresh, ↓reduceDIte] at accepted
    have newUnique : (found.order ++ [reference]).Nodup := by
      rw [List.nodup_append]
      refine ⟨foundUnique, by simp, ?_⟩
      intro other member last lastMember equal
      have same : last = reference := by simpa using lastMember
      exact separate reference ((equal.trans same) ▸ member) fresh
    apply ih result accepted (unvisitedUnique.erase reference) newUnique blobsUnique
    intro other member unvisited
    rcases List.mem_append.mp member with prior | last
    · exact separate other prior (List.mem_of_mem_erase unvisited)
    · have same : other = reference := by simpa using last
      subst other
      exact unvisitedUnique.not_mem_erase unvisited
  | case4 remaining found reference tail node atNode old ih =>
    simp only [walk, atNode, old, ↓reduceDIte] at accepted
    exact ih result accepted unvisitedUnique foundUnique blobsUnique separate
  | case5 remaining found reference tail absent => simp [walk, absent] at accepted
  | case6 remaining found reference tail blob atBlob ih =>
    simp only [walk, atBlob] at accepted
    apply ih result accepted unvisitedUnique foundUnique _ separate
    split
    · exact blobsUnique
    · rename_i fresh
      rw [List.nodup_append]
      refine ⟨blobsUnique, by simp, ?_⟩
      intro other member last lastMember equal
      have same : last = blob := by simpa using lastMember
      exact fresh ((equal.trans same) ▸ member)

theorem discovery_has_distinct_nodes_and_blobs (state : State) (found : Discovery)
    (accepted : discover state = some found) : found.order.Nodup ∧ found.blobs.Nodup := by
  apply walk_does_not_duplicate state _ _ {} found accepted
  · apply List.nodup_range.map
    intro a b different equal
    exact different (congrArg Ref.value equal)
  · exact List.nodup_nil
  · exact List.nodup_nil
  · simp

theorem renaming_injective_on_live_nodes (found : Discovery) (left right : NodeId)
    (leftLive : left ∈ found.order) (rightLive : right ∈ found.order) :
    renameNode found left = renameNode found right ↔ left = right := by
  constructor
  · intro equal
    have indices : found.order.idxOf left = found.order.idxOf right := congrArg Ref.value equal
    have leftAt := List.getElem_idxOf (List.idxOf_lt_length_of_mem leftLive)
    have rightAt := List.getElem_idxOf (List.idxOf_lt_length_of_mem rightLive)
    have same : found.order[found.order.idxOf right]'(List.idxOf_lt_length_of_mem rightLive) = left :=
      by simpa only [indices] using leftAt
    exact same.symm.trans rightAt
  · intro equal; cases equal; rfl

theorem renaming_within_output_inventory (found : Discovery) (reference : NodeId)
    (live : reference ∈ found.order) : (renameNode found reference).value < found.order.length :=
  List.idxOf_lt_length_of_mem live

theorem blob_interning_identifies_only_equal_bytes (state : State) (found : Discovery)
    (left right : BlobId) (leftBlob rightBlob : Blob)
    (leftAt : state.blobs[left.value]? = some leftBlob)
    (rightAt : state.blobs[right.value]? = some rightBlob)
    (leftLive : leftBlob ∈ found.blobs) (rightLive : rightBlob ∈ found.blobs) :
    renameBlob state found left = renameBlob state found right ↔ leftBlob = rightBlob := by
  simp only [renameBlob, leftAt, rightAt, Ref.mk.injEq]
  constructor
  · intro indices
    have leftGet := List.getElem_idxOf (List.idxOf_lt_length_of_mem leftLive)
    have rightGet := List.getElem_idxOf (List.idxOf_lt_length_of_mem rightLive)
    have same : found.blobs[found.blobs.idxOf rightBlob]'(List.idxOf_lt_length_of_mem rightLive) = leftBlob :=
      by simpa only [indices] using leftGet
    exact same.symm.trans rightGet
  · intro equal; rw [equal]

theorem decode_exact (bytes : Bytes) (state : State) (accepted : decode bytes = some state) :
    Images.rawState.valid state = true ∧ Images.rawState.encode state = bytes ∧
      canonicalize state = some state := by
  unfold decode at accepted
  cases parsed : Images.rawState.read bytes with
  | none => simp [parsed] at accepted
  | some pair =>
    rcases pair with ⟨raw, rest⟩
    simp only [parsed, bind, Option.bind] at accepted
    split at accepted
    · cases accepted
    · rename_i empty
      have exhausted : rest = [] := by simpa using empty
      cases normalized : canonicalize raw with
      | none => simp [normalized] at accepted
      | some result =>
        simp only [normalized] at accepted
        split at accepted
        · rename_i equal
          have same : result = raw := by simpa using equal
          cases accepted
          exact ⟨Images.rawState.readValid bytes state rest parsed,
            by simpa [exhausted] using Images.rawState.readExact bytes state rest parsed,
            by simpa [same] using normalized⟩
        · cases accepted

end BoundaryV2.Profile.Graph.Snapshot
