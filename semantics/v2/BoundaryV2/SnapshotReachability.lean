import BoundaryV2.Snapshot

namespace BoundaryV2.Profile.Graph.Snapshot

/-- Blob references denote full immutable content; node references retain
identity even when two node records have equal contents. -/
def Represented (state : State) (found : Discovery) : Reference → Prop
  | .node reference => reference ∈ found.order
  | .blob reference => ∃ blob, state.blobs[reference.value]? = some blob ∧ blob ∈ found.blobs

private theorem represented_mono (state : State) (before after : Discovery)
    (nodes : before.order ⊆ after.order) (blobs : before.blobs ⊆ after.blobs)
    (reference : Reference) (prior : Represented state before reference) : Represented state after reference := by
  cases reference with
  | node reference => exact nodes prior
  | blob reference => rcases prior with ⟨blob, atBlob, member⟩; exact ⟨blob, atBlob, blobs member⟩

def Inventoried (state : State) (remaining : List NodeId) (found : Discovery) : Prop :=
  ∀ reference, reference.value < state.nodes.length → reference ∈ remaining ∨ reference ∈ found.order

private theorem inventoried_visit (state : State) (remaining : List NodeId) (found : Discovery)
    (inventory : Inventoried state remaining found) (reference : NodeId) :
    Inventoried state (remaining.erase reference) { found with order := found.order ++ [reference] } := by
  intro other bounded
  by_cases same : other = reference
  · right; simp [same]
  · rcases inventory other bounded with pending | visited
    · left; exact (List.mem_erase_of_ne same).mpr pending
    · right; exact List.mem_append_left _ visited

private theorem inventoried_initial (state : State) :
    Inventoried state ((List.range state.nodes.length).map (fun index => ⟨index⟩)) {} := by
  intro reference bounded
  left
  exact List.mem_map.mpr ⟨reference.value, List.mem_range.mpr bounded, by cases reference; rfl⟩

theorem walk_represents_pending (state : State) (remaining : List NodeId) (pending : List Reference)
    (found result : Discovery) (accepted : walk state remaining pending found = some result)
    (inventory : Inventoried state remaining found) :
    ∀ reference ∈ pending, Represented state result reference := by
  induction remaining, pending, found using walk.induct state generalizing result with
  | case1 remaining found => simp
  | case2 remaining found reference tail absent => simp [walk, absent] at accepted
  | case3 remaining found reference tail node atNode fresh ih =>
    simp only [walk, atNode, fresh, ↓reduceDIte] at accepted
    have covered := ih result accepted (inventoried_visit state remaining found inventory reference)
    have grows := walk_preserves_discovery state _ _ _ result accepted
    intro target member
    rcases List.mem_cons.mp member with same | later
    · subst target
      exact grows.1 (by simp)
    · exact covered target (List.mem_append_right _ later)
  | case4 remaining found reference tail node atNode old ih =>
    simp only [walk, atNode, old, ↓reduceDIte] at accepted
    have covered := ih result accepted inventory
    have grows := walk_preserves_discovery state _ _ _ result accepted
    intro target member
    rcases List.mem_cons.mp member with same | later
    · subst target
      exact grows.1 ((inventory reference (List.getElem?_eq_some_iff.mp atNode).1).resolve_left old)
    · exact covered target later
  | case5 remaining found reference tail absent => simp [walk, absent] at accepted
  | case6 remaining found reference tail blob atBlob ih =>
    simp only [walk, atBlob] at accepted
    have covered := ih result accepted inventory
    have grows := walk_preserves_discovery state _ _ _ result accepted
    intro target member
    rcases List.mem_cons.mp member with same | later
    · subst target
      refine ⟨blob, atBlob, grows.2 ?_⟩
      split <;> simp_all
    · exact covered target later

theorem walk_represents_new_node_edges (state : State) (remaining : List NodeId) (pending : List Reference)
    (found result : Discovery) (accepted : walk state remaining pending found = some result)
    (inventory : Inventoried state remaining found) :
    ∀ reference ∈ result.order, reference ∉ found.order →
      ∃ node, state.nodes[reference.value]? = some node ∧
        ∀ child ∈ nodeReferences node, Represented state result child := by
  induction remaining, pending, found using walk.induct state generalizing result with
  | case1 remaining found =>
    simp only [walk, Option.some.injEq] at accepted
    cases accepted
    intro reference member absent
    exact False.elim (absent member)
  | case2 remaining found reference tail absent => simp [walk, absent] at accepted
  | case3 remaining found reference tail node atNode fresh ih =>
    simp only [walk, atNode, fresh, ↓reduceDIte] at accepted
    have nextInventory := inventoried_visit state remaining found inventory reference
    intro target member absent
    by_cases same : target = reference
    · subst target
      refine ⟨node, atNode, ?_⟩
      intro child edge
      exact walk_represents_pending state _ _ _ result accepted nextInventory child (List.mem_append_left _ edge)
    · apply ih result accepted nextInventory target member
      simpa using And.intro absent same
  | case4 remaining found reference tail node atNode old ih =>
    simp only [walk, atNode, old, ↓reduceDIte] at accepted
    exact ih result accepted inventory
  | case5 remaining found reference tail absent => simp [walk, absent] at accepted
  | case6 remaining found reference tail blob atBlob ih =>
    simp only [walk, atBlob] at accepted
    exact ih result accepted inventory

theorem discovery_covers_roots_and_edges (state : State) (found : Discovery)
    (accepted : discover state = some found) :
    (∀ reference ∈ rootReferences state.roots, Represented state found reference) ∧
    (∀ reference ∈ found.order, ∃ node, state.nodes[reference.value]? = some node ∧
      ∀ child ∈ nodeReferences node, Represented state found child) := by
  refine ⟨walk_represents_pending state _ _ {} found accepted (inventoried_initial state), ?_⟩
  intro reference member
  exact walk_represents_new_node_edges state _ _ {} found accepted (inventoried_initial state)
    reference member (by simp)

inductive Reachable (state : State) : Reference → Prop
  | root : reference ∈ rootReferences state.roots → Reachable state reference
  | child : Reachable state (.node parent) → state.nodes[parent.value]? = some node →
      reference ∈ nodeReferences node → Reachable state reference

def DiscoveryReachable (state : State) (found : Discovery) : Prop :=
  (∀ reference ∈ found.order, Reachable state (.node reference)) ∧
  (∀ blob ∈ found.blobs, ∃ reference, Reachable state (.blob reference) ∧ state.blobs[reference.value]? = some blob)

theorem walk_collects_only_reachable (state : State) (remaining : List NodeId) (pending : List Reference)
    (found result : Discovery) (accepted : walk state remaining pending found = some result)
    (pendingLive : ∀ reference ∈ pending, Reachable state reference)
    (foundLive : DiscoveryReachable state found) : DiscoveryReachable state result := by
  induction remaining, pending, found using walk.induct state generalizing result with
  | case1 remaining found =>
    simp only [walk, Option.some.injEq] at accepted
    cases accepted
    exact foundLive
  | case2 remaining found reference tail absent => simp [walk, absent] at accepted
  | case3 remaining found reference tail node atNode fresh ih =>
    simp only [walk, atNode, fresh, ↓reduceDIte] at accepted
    have parentLive := pendingLive _ (List.mem_cons_self ..)
    apply ih result accepted
    · intro child member
      rcases List.mem_append.mp member with edge | later
      · exact .child parentLive atNode edge
      · exact pendingLive child (List.mem_cons_of_mem _ later)
    · refine ⟨?_, foundLive.2⟩
      intro other member
      rcases List.mem_append.mp member with prior | last
      · exact foundLive.1 other prior
      · have same : other = reference := by simpa using last
        simpa [same] using parentLive
  | case4 remaining found reference tail node atNode old ih =>
    simp only [walk, atNode, old, ↓reduceDIte] at accepted
    exact ih result accepted (fun other member => pendingLive other (List.mem_cons_of_mem _ member)) foundLive
  | case5 remaining found reference tail absent => simp [walk, absent] at accepted
  | case6 remaining found reference tail blob atBlob ih =>
    simp only [walk, atBlob] at accepted
    apply ih result accepted (fun other member => pendingLive other (List.mem_cons_of_mem _ member))
    refine ⟨foundLive.1, ?_⟩
    intro other member
    split at member
    · exact foundLive.2 other member
    · rcases List.mem_append.mp member with prior | last
      · exact foundLive.2 other prior
      · have same : other = blob := by simpa using last
        exact ⟨reference, pendingLive _ (List.mem_cons_self ..), by simpa [same] using atBlob⟩

theorem discovery_represents_reachable (state : State) (found : Discovery)
    (accepted : discover state = some found) (target : Reference)
    (reachable : Reachable state target) : Represented state found target := by
  have covered := discovery_covers_roots_and_edges state found accepted
  induction reachable with
  | root member => exact covered.1 _ member
  | child prior atNode edge ih =>
    rcases covered.2 _ ih with ⟨node, atParent, children⟩
    have same := Option.some.inj (atParent.symm.trans atNode)
    exact children _ (by simpa [same] using edge)

theorem discovery_exactly_reachable_nodes (state : State) (found : Discovery)
    (accepted : discover state = some found) (reference : NodeId) :
    reference ∈ found.order ↔ Reachable state (.node reference) := by
  have live := walk_collects_only_reachable state _ _ {} found accepted
    (fun _ member => .root member) (by constructor <;> simp)
  exact ⟨live.1 reference, discovery_represents_reachable state found accepted _⟩

end BoundaryV2.Profile.Graph.Snapshot
