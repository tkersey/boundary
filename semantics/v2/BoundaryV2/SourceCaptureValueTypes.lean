import BoundaryV2.SourceControlTypes

namespace BoundaryV2.Profile.Source.Machine

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

theorem rename_capture_preserves_value_shapes (mapping : Renaming) (saved : Capture)
    (typed : ∀ value ∈ ValueInventory.capture saved, ValueShape schemas value) :
    ∀ value ∈ ValueInventory.capture (renameCapture mapping saved), ValueShape schemas value := by
  rw [ValueInventory.rename_capture]
  intro value member
  obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
  exact renaming_preserves_value_shape schemas mapping original (typed original originalMember)

namespace ValueInventory

theorem lookup_preserves_all (machine : State) (node : NodeId) (stored : Object)
    (found : machine.heap.lookup node = some stored)
    (property : SemanticValue → Prop) (holds : All property machine) :
    ∀ value ∈ object stored, property value := by
  simp only [Heap.lookup, Option.bind_eq_some_iff] at found
  obtain ⟨entry, atNode, present⟩ := found
  have nodeMember := List.mem_of_getElem? atNode
  cases entry <;> simp [id] at present
  cases present
  intro value member
  apply holds
  simp only [state, heap, List.mem_append, List.mem_flatMap]
  grind only [Option.toList_some, List.mem_singleton]

end ValueInventory

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

theorem instantiateCapture_preserves_value_shapes (machine : State) (context : Context)
    (saved : Capture) (after : State × Capture)
    (accepted : instantiateCapture machine context saved = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine)
    (captureTyped : ∀ value ∈ ValueInventory.capture saved, ValueShape context.source.schemas value) :
    ValueInventory.All (ValueShape context.source.schemas) after.1 ∧
    (∀ value ∈ ValueInventory.capture after.2, ValueShape context.source.schemas value) := by
  let dormant := (cloneSupport machine.heap saved).filterMap (fun node => match machine.heap.lookup node with
    | some (.multiTemplate inner) => some inner | _ => none)
  have dormantTyped (inner : Capture) (member : inner ∈ dormant) :
      ∀ value ∈ ValueInventory.capture inner, ValueShape context.source.schemas value := by
    obtain ⟨node, _, found⟩ := List.mem_filterMap.mp member
    split at found <;> try contradiction
    rename_i capture lookup
    cases found
    exact ValueInventory.lookup_preserves_all machine node (.multiTemplate inner) lookup _ typed
  have frozenTyped (cell : FrozenCell) (member : cell ∈ saved.frozenCells ++ dormant.flatMap Capture.frozenCells) :
      ValueShape context.source.schemas cell.content.value := by
    rcases List.mem_append.mp member with member | member
    · apply captureTyped
      simp only [ValueInventory.capture, List.mem_append, List.mem_map]
      exact Or.inr ⟨cell, member, rfl⟩
    · obtain ⟨inner, innerMember, cellMember⟩ := List.mem_flatMap.mp member
      apply dormantTyped inner innerMember
      simp only [ValueInventory.capture, List.mem_append, List.mem_map]
      exact Or.inr ⟨cell, cellMember, rfl⟩
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨objects, objectsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨scopes, scopesAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨invocations, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  have objectsTyped : ∀ entry ∈ objects, ∀ value ∈ entry.toList.flatMap ValueInventory.object,
      ValueShape context.source.schemas value := by
    refine mapM_preserves _ (fun entry : Option Object => ∀ value ∈ entry.toList.flatMap ValueInventory.object,
      ValueShape context.source.schemas value) ?_ _ _ objectsAt
    intro input output checked
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨stored, lookup, rfl⟩ := checked
    have storedTyped := ValueInventory.lookup_preserves_all machine input stored lookup _ typed
    simp only [Option.toList_some, List.flatMap_cons, List.flatMap_nil, List.append_nil,
      ValueInventory.rename_object]
    intro value member
    obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
    apply renaming_preserves_value_shape
    cases stored <;> try exact storedTyped original originalMember
    rename_i identity schema region content
    simp only [ValueInventory.object, List.mem_singleton] at originalMember
    cases originalMember
    change ValueShape context.source.schemas
      ((((saved.frozenCells ++ dormant.flatMap Capture.frozenCells).find? (fun cell => cell.node == input)).map FrozenCell.content).getD content).value
    cases found : (saved.frozenCells ++ dormant.flatMap Capture.frozenCells).find? (fun cell => cell.node == input) with
    | none => simpa only [found, Option.map_none, Option.getD_none] using storedTyped content.value (by simp [ValueInventory.object])
    | some cell =>
      simpa only [found, Option.map_some, Option.getD_some] using frozenTyped cell (List.mem_of_find?_eq_some found)
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
  have objectsAll : ∀ value ∈ objects.flatMap (fun entry => entry.toList.flatMap ValueInventory.object),
      ValueShape context.source.schemas value := by
    intro value member
    obtain ⟨entry, entryMember, member⟩ := List.mem_flatMap.mp member
    exact objectsTyped entry entryMember value member
  constructor
  · simp only [ValueInventory.All, ValueInventory.state, ValueInventory.heap,
      List.flatMap_append, scopesNil, List.append_nil, List.mem_append] at typed ⊢
    grind only []
  · exact rename_capture_preserves_value_shapes _ saved captureTyped

end BoundaryV2.Profile.Source.Machine
