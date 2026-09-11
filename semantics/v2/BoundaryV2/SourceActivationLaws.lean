import BoundaryV2.SourceCapture

namespace BoundaryV2.Profile.Source.Machine

/-- Runtime maps reserve consecutive identities after the old supply. Repeated
aliases occupy one position because the map's input domain is deduplicated. -/
theorem fresh_map_member (space : Space) (domain : Domain) (start : Nat)
    (identities : List (Ref space domain)) (before after : Ref space domain)
    (member : (before, after) ∈ freshMap space domain start identities) :
    before ∈ identities ∧ start ≤ after.value ∧
      after.value < start + identities.eraseDups.length := by
  obtain ⟨index, inBounds, atIndex⟩ := List.mem_mapIdx.mp member
  have source := congrArg Prod.fst atIndex
  have target := congrArg (fun pair => pair.2.value) atIndex
  simp only at source target
  refine ⟨List.mem_eraseDups.mp (source ▸ List.getElem_mem inBounds), ?_, ?_⟩ <;> omega

theorem fresh_map_targets_identify_sources (space : Space) (domain : Domain) (start : Nat)
    (identities : List (Ref space domain)) (left right target : Ref space domain)
    (leftMember : (left, target) ∈ freshMap space domain start identities)
    (rightMember : (right, target) ∈ freshMap space domain start identities) : left = right := by
  obtain ⟨leftIndex, leftBound, leftAt⟩ := List.mem_mapIdx.mp leftMember
  obtain ⟨rightIndex, rightBound, rightAt⟩ := List.mem_mapIdx.mp rightMember
  have leftValue := congrArg (fun pair => pair.2.value) leftAt
  have rightValue := congrArg (fun pair => pair.2.value) rightAt
  simp only at leftValue rightValue
  have same : leftIndex = rightIndex := by omega
  subst rightIndex
  exact (congrArg Prod.fst leftAt).symm.trans (congrArg Prod.fst rightAt)

theorem renamed_outside_fresh_map (space : Space) (domain : Domain) (start : Nat)
    (identities : List (Ref space domain)) (identity : Ref space domain)
    (outside : identity ∉ identities) :
    renamed (freshMap space domain start identities) identity = identity := by
  unfold renamed
  have absent : (freshMap space domain start identities).find? (fun pair => pair.1 == identity) = none := by
    apply List.find?_eq_none.mpr
    intro pair member
    have original := (fresh_map_member _ _ _ _ _ _ member).1
    by_cases equal : pair.1 = identity
    · exact False.elim (outside (equal ▸ original))
    · simpa using equal
  simp [absent]

theorem renamed_inside_fresh_map (space : Space) (domain : Domain) (start : Nat)
    (identities : List (Ref space domain)) (identity : Ref space domain)
    (inside : identity ∈ identities) :
    (identity, renamed (freshMap space domain start identities) identity) ∈
      freshMap space domain start identities := by
  have source : identity ∈ identities.eraseDups := List.mem_eraseDups.mpr inside
  obtain ⟨index, inBounds, atIndex⟩ := List.mem_iff_getElem.mp source
  have supplied : (identity, (⟨start + index⟩ : Ref space domain)) ∈ freshMap space domain start identities := by
    exact List.mem_mapIdx.mpr ⟨index, inBounds, by simp [atIndex]⟩
  cases found : (freshMap space domain start identities).find? (fun pair => pair.1 == identity) with
  | none =>
    have absent := List.find?_eq_none.mp found _ supplied
    simp at absent
  | some pair =>
    have equal : pair.1 = identity := by simpa using List.find?_some found
    have selected : renamed (freshMap space domain start identities) identity = pair.2 := by
      simp [renamed, found]
    rw [selected, ← equal]
    exact List.mem_of_find?_eq_some found

theorem source_activation_interval (space : Space) (domain : Domain) (start : Nat)
    (identities : List (Ref space domain)) (identity : Ref space domain)
    (inside : identity ∈ identities) :
    start ≤ (renamed (freshMap space domain start identities) identity).value ∧
    (renamed (freshMap space domain start identities) identity).value < start + identities.eraseDups.length :=
  (fresh_map_member _ _ _ _ _ _ (renamed_inside_fresh_map _ _ _ _ _ inside)).2

theorem source_activation_injective (space : Space) (domain : Domain) (start : Nat)
    (identities : List (Ref space domain)) (left right : Ref space domain)
    (leftInside : left ∈ identities) (rightInside : right ∈ identities)
    (same : renamed (freshMap space domain start identities) left =
      renamed (freshMap space domain start identities) right) : left = right := by
  have leftMap := renamed_inside_fresh_map space domain start identities left leftInside
  have rightMap := renamed_inside_fresh_map space domain start identities right rightInside
  rw [same] at leftMap
  exact fresh_map_targets_identify_sources _ _ _ _ _ _ _ leftMap rightMap

theorem source_activation_avoids_old_identities (space : Space) (domain : Domain) (start : Nat)
    (identities : List (Ref space domain)) (inside outside : Ref space domain)
    (member : inside ∈ identities) (old : outside.value < start) :
    renamed (freshMap space domain start identities) inside ≠ outside := by
  have lower := (source_activation_interval space domain start identities inside member).1
  intro same
  rw [same] at lower
  omega

theorem successive_source_activations_separate (space : Space) (domain : Domain) (start : Nat)
    (first second : List (Ref space domain)) (left right : Ref space domain)
    (leftInside : left ∈ first) (rightInside : right ∈ second) :
    renamed (freshMap space domain start first) left ≠
      renamed (freshMap space domain (start + first.eraseDups.length) second) right := by
  have upper := (source_activation_interval space domain start first left leftInside).2
  have lower := (source_activation_interval space domain (start + first.eraseDups.length) second right rightInside).1
  intro same
  rw [same] at upper
  omega

private theorem bind_success (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) (accepted : value.bind next = .ok result) :
    ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value with
  | error error => cases accepted
  | ok input => exact ⟨input, rfl, accepted⟩

/-- Instantiation appends new objects. Current outside cells and references
retain their original objects, independently of the captured local snapshots. -/
theorem source_instantiation_retains_old_heap (state after : State) (context : Context)
    (capture instantiated : Capture)
    (accepted : instantiateCapture state context capture = .ok (after, instantiated)) :
    after.heap.custody = state.heap.custody ∧
      ∃ copied, after.heap.objects = state.heap.objects ++ copied := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨copied, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  cases accepted
  exact ⟨rfl, copied, rfl⟩

theorem source_instantiation_retains_outside_lookup (state after : State) (context : Context)
    (capture instantiated : Capture) (reference : NodeId)
    (old : reference.value < state.heap.objects.length)
    (accepted : instantiateCapture state context capture = .ok (after, instantiated)) :
    after.heap.lookup reference = state.heap.lookup reference := by
  obtain ⟨_, copied, retained⟩ := source_instantiation_retains_old_heap _ _ _ _ _ accepted
  simp only [Heap.lookup, retained, List.getElem?_append_left old]

theorem source_instantiation_checks_clone_safety (state after : State) (context : Context)
    (capture instantiated : Capture)
    (accepted : instantiateCapture state context capture = .ok (after, instantiated)) :
    allCaptureCloneSafe context.source state.heap capture = true := by
  unfold instantiateCapture at accepted
  obtain ⟨checked, safe, _⟩ := bind_success _ _ _ accepted
  unfold require at safe
  split at safe
  · assumption
  · cases safe

end BoundaryV2.Profile.Source.Machine
