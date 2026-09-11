import BoundaryV2.SourceValues

namespace BoundaryV2.Profile.Source.Machine

private theorem bind_success (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) (accepted : value.bind next = .ok result) :
    ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value with
  | error error => cases accepted
  | ok input => exact ⟨input, rfl, accepted⟩

private theorem temporary_preserves_objects (state after : State) (owner : Custody.Owner)
    (accepted : temporary state = .ok (after, owner)) : after.heap.objects = state.heap.objects := by
  unfold temporary at accepted
  split at accepted
  · split at accepted
    · simp [bind, Except.bind] at accepted
    · cases accepted; rfl
  · cases accepted

private theorem finish_temporary_delivers (state : State) (value : Located) (transition : Transition)
    (accepted : finishTemporary state value = .ok transition) :
    transition.state.heap.objects = state.heap.objects ∧
      transition.state.control = .delivered value ∧ transition.events = [] := by
  unfold finishTemporary at accepted
  split at accepted
  · cases accepted; exact ⟨rfl, rfl, rfl⟩
  · cases accepted

theorem scoped_value_retains_storage (state : State) (value : SemanticValue) (transition : Transition)
    (accepted : scopedValue state value = .ok transition) :
    transition.state.heap.objects = state.heap.objects ∧
      ∃ owner, transition.state.control = .delivered ⟨value, owner⟩ ∧ transition.events = [] := by
  unfold scopedValue at accepted
  obtain ⟨⟨after, owner⟩, temporaryChecked, accepted⟩ := bind_success _ _ _ accepted
  have delivered := finish_temporary_delivers _ _ _ accepted
  exact ⟨delivered.1.trans (temporary_preserves_objects _ _ _ temporaryChecked), owner, delivered.2⟩

theorem replace_object_updates_only_selected_node (before after : Heap) (reference : NodeId)
    (object : Object) (accepted : replaceObject before reference object = some after) :
    after.lookup reference = some object ∧
      ∀ other : NodeId, other ≠ reference → after.lookup other = before.lookup other := by
  unfold replaceObject at accepted
  split at accepted
  · rename_i bound
    cases accepted
    constructor
    · simp [Heap.lookup, List.getElem?_set_self bound]
    · intro other different
      have indices : other.value ≠ reference.value := by
        intro same
        cases other; cases reference
        exact different (congrArg Ref.mk same)
      simp [Heap.lookup, List.getElem?_set_ne indices.symm]
  · cases accepted

/-- A successful read returns the contents of the selected physical cell;
scope bookkeeping cannot alter that cell or any other storage. -/
theorem cell_get_reads_current_storage (state : State) (context : Context) (schema : SchemaId .source)
    (value content : Located) (reference : NodeId) (identity : CellId)
    (cellSchema : SchemaId .source) (region : RegionInstanceId) (transition : Transition)
    (lookup : lookupObject state value = .ok (reference, .cell identity cellSchema region content))
    (accepted : heapPrimitive state context .cellGet schema 0 [value] = .ok transition) :
    transition.state.heap.objects = state.heap.objects ∧
      ∃ owner, transition.state.control = .delivered ⟨content.value, owner⟩ ∧ transition.events = [] := by
  simp only [heapPrimitive, lookup, bind, Except.bind] at accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  exact scoped_value_retains_storage _ _ _ accepted

/-- Every alias of the selected node observes the replacement. All distinct
physical cells retain their current objects, including outside region cells. -/
theorem cell_set_preserves_identity_and_other_cells (state : State) (context : Context)
    (schema : SchemaId .source) (value replacement content : Located) (reference : NodeId)
    (identity : CellId) (cellSchema : SchemaId .source) (region : RegionInstanceId)
    (transition : Transition)
    (lookup : lookupObject state value = .ok (reference, .cell identity cellSchema region content))
    (accepted : heapPrimitive state context .cellSet schema 0 [value, replacement] = .ok transition) :
    transition.state.heap.lookup reference =
      some (.cell identity cellSchema region (retainAt replacement (.cell identity))) ∧
      ∀ other : NodeId, other ≠ reference → transition.state.heap.lookup other = state.heap.lookup other := by
  simp only [heapPrimitive, lookup, bind, Except.bind] at accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨heap, replaced, accepted⟩ := bind_success _ _ _ accepted
  have replaced : replaceObject state.heap reference
      (.cell identity cellSchema region (retainAt replacement (.cell identity))) = some heap := by
    cases found : replaceObject state.heap reference
        (.cell identity cellSchema region (retainAt replacement (.cell identity))) <;>
      simp [fromOption, found] at replaced
    subst heap
    rfl
  have retained := (scoped_value_retains_storage _ _ _ accepted).1
  simpa only [Heap.lookup, retained] using replace_object_updates_only_selected_node _ _ _ _ replaced

end BoundaryV2.Profile.Source.Machine
