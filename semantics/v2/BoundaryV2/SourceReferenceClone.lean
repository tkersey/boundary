import BoundaryV2.SourceReferenceStorage
import BoundaryV2.SourceCaptureValueTypes

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceContracts

theorem renamed_matches (schemas : List (Schema .source)) (schema : SchemaId .source)
    (mapping : Renaming) (stored : Object) (compatible : Matches schemas schema stored) :
    Matches schemas schema (renameObject mapping stored) := by
  cases stored <;> simpa only [Matches, renameObject, renameCapture] using compatible

theorem frozen_matches (schemas : List (Schema .source)) (schema : SchemaId .source)
    (saved : Capture) (dormant : List Capture) (node : NodeId) (stored : Object)
    (compatible : Matches schemas schema stored) : Matches schemas schema (frozenObject saved dormant node stored) := by
  cases stored <;> simpa only [Matches, frozenObject] using compatible

theorem rename_value_valid (schemas : List (Schema .source)) (before after : Heap)
    (mapping : Renaming) (value : SemanticValue) (valid : ValueValid schemas before value)
    (references : ∀ schema node token, ReferenceValid schemas before schema node token →
      ReferenceValid schemas after schema (renamed mapping.nodes node) token) :
    ValueValid schemas after (renameValue mapping value) := by
  cases value with
  | scalar _ _ | blob _ _ => simp [ValueValid, renameValue, Primitives.ReferencesSatisfy]
  | reference schema node token =>
    simp only [ValueValid, Primitives.ReferencesSatisfy] at valid
    simpa only [ValueValid, renameValue, Primitives.ReferencesSatisfy] using references schema node token valid
  | product _ fields | sequence _ fields =>
    simp only [ValueValid, Primitives.ReferencesSatisfy] at valid
    simp only [ValueValid, renameValue, Primitives.ReferencesSatisfy]
    intro child member
    obtain ⟨original, childMember, rfl⟩ := List.mem_map.mp member
    exact rename_value_valid schemas before after mapping original (valid original childMember) references
  | variant _ _ payload =>
    simp only [ValueValid, Primitives.ReferencesSatisfy] at valid
    simpa only [ValueValid, renameValue, Primitives.ReferencesSatisfy] using
      rename_value_valid schemas before after mapping payload valid references
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem childMember) (by omega)

theorem instantiation_keeps_prior_value_valid (state after : State) (context : Context)
    (saved instantiated : Capture) (accepted : instantiateCapture state context saved = .ok (after, instantiated))
    (value : SemanticValue) (valid : ValueValid context.source.schemas state.heap value) :
    ValueValid context.source.schemas after.heap value := by
  have sameBook := (source_instantiation_retains_old_heap _ _ _ _ _ accepted).1
  apply references_mono value _ _ valid
  intro schema node token checked usable
  obtain ⟨stored, found, compatible⟩ := checked (sameBook ▸ usable)
  have bound : node.value < state.heap.objects.length := by
    simp only [Heap.lookup, Option.bind_eq_some_iff] at found
    obtain ⟨entry, atNode, _⟩ := found
    exact (List.getElem?_eq_some_iff.mp atNode).choose
  exact ⟨stored, (source_instantiation_retains_outside_lookup _ _ _ _ _ node bound accepted).trans found, compatible⟩

/-- The actual clone map preserves schema compatibility of every usable
reference. Ownership alignment is a separate obligation. -/
theorem instantiation_reference_map (state after : State) (context : Context)
    (saved instantiated : Capture) (accepted : instantiateCapture state context saved = .ok (after, instantiated)) :
    ∃ mapping : Renaming, instantiated = renameCapture mapping saved ∧
      (∀ value, ValueValid context.source.schemas state.heap value →
        ValueValid context.source.schemas after.heap (renameValue mapping value)) ∧
      ∀ entry ∈ after.heap.objects, entry ∈ state.heap.objects ∨
        ∃ node stored dormant, state.heap.lookup node = some stored ∧
          (∀ inner ∈ dormant, ∃ innerNode, state.heap.lookup innerNode = some (.multiTemplate inner)) ∧
          entry = some (renameObject mapping (frozenObject saved dormant node stored)) := by
  obtain ⟨mapping, nodes, renamedCapture, copied, inventory⟩ :=
    instantiation_inventory state after context saved instantiated accepted
  have sameBook := (source_instantiation_retains_old_heap _ _ _ _ _ accepted).1
  refine ⟨mapping, renamedCapture, ?_, ?_⟩
  · intro value valid
    apply rename_value_valid _ state.heap after.heap mapping value valid
    intro schema node token checked usable
    obtain ⟨stored, found, compatible⟩ := checked (sameBook ▸ usable)
    by_cases copiedNode : node ∈ (cloneSupport state.heap saved).filter (fun reference =>
      match state.heap.lookup reference with
      | some (.cell _ _ region _) | some (.region region _ _ _) =>
        (saved.localRegions ++ ((cloneSupport state.heap saved).filterMap (fun node =>
          match state.heap.lookup node with | some (.multiTemplate inner) => some inner | _ => none)).flatMap Capture.localRegions).eraseDups.contains region
      | some (.capability identity _) =>
        (saved.delimiter.identity :: activeAttachments saved.frames ++
          ((cloneSupport state.heap saved).filterMap (fun node =>
            match state.heap.lookup node with | some (.multiTemplate inner) => some inner | _ => none)).flatMap
            (fun inner => inner.delimiter.identity :: activeAttachments inner.frames)).eraseDups.contains identity
      | some (.closure ..) | some (.multiTemplate _) => true
      | _ => false)
    · obtain ⟨original, originalAt, copiedAt⟩ := copied node copiedNode
      have equal := Option.some.inj (found.symm.trans originalAt)
      subst original
      exact ⟨_, copiedAt, renamed_matches _ _ mapping _ (frozen_matches _ _ _ _ node stored compatible)⟩
    · have unmapped := renamed_outside_fresh_map .runtime .node state.heap.objects.length _ node copiedNode
      have unchanged : renamed mapping.nodes node = node := by
        rw [nodes]
        exact unmapped
      rw [unchanged]
      have bound : node.value < state.heap.objects.length := by
        simp only [Heap.lookup, Option.bind_eq_some_iff] at found
        obtain ⟨entry, atNode, _⟩ := found
        exact (List.getElem?_eq_some_iff.mp atNode).choose
      exact ⟨stored, (source_instantiation_retains_outside_lookup _ _ _ _ _ node bound accepted).trans found, compatible⟩
  · intro entry member
    rcases inventory entry member with old | added
    · exact Or.inl old
    · obtain ⟨node, _, stored, found, same⟩ := added
      refine Or.inr ⟨node, stored, _, found, ?_, same⟩
      intro inner member
      obtain ⟨node, _, found⟩ := List.mem_filterMap.mp member
      split at found <;> try contradiction
      rename_i original atNode
      cases found
      exact ⟨node, atNode⟩

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem mapM_preserves (function : α → Except Invalid β) (property : β → Prop)
    (preserves : ∀ input output, function input = .ok output → property output)
    (inputs : List α) (outputs : List β) (accepted : inputs.mapM function = .ok outputs) :
    ∀ output ∈ outputs, property output := by
  induction inputs generalizing outputs with
  | nil => cases accepted; simp
  | cons head tail induction =>
    simp only [List.mapM_cons, bind, except_bind_ok] at accepted
    obtain ⟨first, firstAt, rest, restAt, accepted⟩ := accepted
    cases accepted
    exact fun value member => (List.mem_cons.mp member).elim
      (fun equal => equal ▸ preserves head first firstAt) (induction rest restAt value)

theorem instantiation_inventory_preserves_all (machine after : State) (context : Context)
    (saved instantiated : Capture) (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (property : SemanticValue → Prop) (holds : ValueInventory.All property machine)
    (objectsValid : ∀ entry ∈ after.heap.objects, ∀ value ∈ entry.toList.flatMap ValueInventory.object, property value) :
    ValueInventory.All property after := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨objects, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨scopes, scopesAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨invocations, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  have scopesEmpty : ∀ scope ∈ scopes, scope.holdings = [] := by
    refine mapM_preserves _ (fun scope : Scope => scope.holdings = []) ?_ _ _ scopesAt
    intro input output checked
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨_, _, rfl⟩ := checked
    rfl
  have scopesNil : scopes.flatMap (fun scope => scope.holdings.map Located.value) = [] := by
    simp only [List.flatMap_eq_nil_iff]
    intro scope member
    simp [scopesEmpty scope member]
  have allObjects : ∀ value ∈ (machine.heap.objects ++ objects).flatMap (fun entry => entry.toList.flatMap ValueInventory.object),
      property value := by
    intro value member
    obtain ⟨entry, entryMember, member⟩ := List.mem_flatMap.mp member
    exact objectsValid entry entryMember value member
  simp only [ValueInventory.All, ValueInventory.state, ValueInventory.heap,
    List.flatMap_append, scopesNil, List.append_nil, List.mem_append] at holds ⊢
  grind only [List.mem_append, List.mem_flatMap]

theorem instantiation_values_of_inventory (machine after : State) (context : Context)
    (saved instantiated : Capture) (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (mapping : Renaming) (captured : instantiated = renameCapture mapping saved)
    (beforeProperty afterProperty : SemanticValue → Prop)
    (holds : ValueInventory.All beforeProperty machine)
    (captureHolds : ∀ value ∈ ValueInventory.capture saved, beforeProperty value)
    (retains : ∀ value, beforeProperty value → afterProperty value)
    (renames : ∀ value, beforeProperty value → afterProperty (renameValue mapping value))
    (inventory : ∀ entry ∈ after.heap.objects, entry ∈ machine.heap.objects ∨
      ∃ node stored dormant, machine.heap.lookup node = some stored ∧
        (∀ inner ∈ dormant, ∃ innerNode, machine.heap.lookup innerNode = some (.multiTemplate inner)) ∧
        entry = some (renameObject mapping (frozenObject saved dormant node stored))) :
    ValueInventory.All afterProperty after ∧ (∀ value ∈ ValueInventory.capture instantiated, afterProperty value) := by
  have oldValid := ValueInventory.all_mono _ _ machine holds retains
  have objectsValid : ∀ entry ∈ after.heap.objects,
      ∀ value ∈ entry.toList.flatMap ValueInventory.object, afterProperty value := by
    intro entry member value valueMember
    rcases inventory entry member with old | added
    · apply oldValid value
      simp only [ValueInventory.state, ValueInventory.heap, List.mem_append, List.mem_flatMap]
      exact Or.inl (Or.inr (Or.inl (Or.inl ⟨entry, old, List.mem_flatMap.mp valueMember⟩)))
    · obtain ⟨node, stored, dormant, found, dormantStored, equal⟩ := added
      have objectValid := ValueInventory.lookup_preserves_all machine node stored found _ holds
      have frozenValid (cell : FrozenCell) (member : cell ∈ saved.frozenCells ++ dormant.flatMap Capture.frozenCells) :
          beforeProperty cell.content.value := by
        rcases List.mem_append.mp member with own | nested
        · apply captureHolds
          simp only [ValueInventory.capture, List.mem_append, List.mem_map]
          exact Or.inr ⟨cell, own, rfl⟩
        · obtain ⟨inner, innerMember, cellMember⟩ := List.mem_flatMap.mp nested
          obtain ⟨innerNode, innerFound⟩ := dormantStored inner innerMember
          apply ValueInventory.lookup_preserves_all machine innerNode (.multiTemplate inner) innerFound _ holds
          simp only [ValueInventory.object, ValueInventory.capture, List.mem_append, List.mem_map]
          exact Or.inr ⟨cell, cellMember, rfl⟩
      rw [equal] at valueMember
      simp only [Option.toList_some, List.flatMap_cons, List.flatMap_nil, List.append_nil,
        ValueInventory.rename_object] at valueMember
      obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp valueMember
      apply renames
      cases stored <;> try exact objectValid original originalMember
      rename_i identity schema region content
      simp only [frozenObject, ValueInventory.object, List.mem_singleton] at originalMember
      cases originalMember
      change beforeProperty
        ((((saved.frozenCells ++ dormant.flatMap Capture.frozenCells).find? (fun cell => cell.node == node)).map FrozenCell.content).getD content).value
      cases frozen : (saved.frozenCells ++ dormant.flatMap Capture.frozenCells).find? (fun cell => cell.node == node) with
      | none => simpa only [frozen, Option.map_none, Option.getD_none] using objectValid content.value (by simp [ValueInventory.object])
      | some cell =>
        simpa only [frozen, Option.map_some, Option.getD_some] using frozenValid cell (List.mem_of_find?_eq_some frozen)
  have captureAfter : ∀ value ∈ ValueInventory.capture instantiated, afterProperty value := by
    rw [captured, ValueInventory.rename_capture]
    intro value member
    obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
    exact renames original (captureHolds original originalMember)
  exact ⟨instantiation_inventory_preserves_all machine after context saved instantiated accepted _ oldValid objectsValid, captureAfter⟩

theorem instantiateCapture_preserves_reference_validity (machine after : State) (context : Context)
    (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (valid : ValueInventory.All (ValueValid context.source.schemas machine.heap) machine)
    (captureValid : ∀ value ∈ ValueInventory.capture saved, ValueValid context.source.schemas machine.heap value) :
    ValueInventory.All (ValueValid context.source.schemas after.heap) after ∧
      (∀ value ∈ ValueInventory.capture instantiated, ValueValid context.source.schemas after.heap value) := by
  obtain ⟨mapping, captured, renames, inventory⟩ := instantiation_reference_map machine after context saved instantiated accepted
  exact instantiation_values_of_inventory machine after context saved instantiated accepted mapping captured _ _
    valid captureValid (instantiation_keeps_prior_value_valid machine after context saved instantiated accepted) renames inventory

end ReferenceContracts
end BoundaryV2.Profile.Source.Machine
