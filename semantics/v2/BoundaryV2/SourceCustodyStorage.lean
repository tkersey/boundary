import BoundaryV2.SourceCustodyCoverage

namespace BoundaryV2.Profile.Source.Machine
namespace CustodyCoverage

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem flatMap_remove_subset (values : List α) (index : Nat) (removed replacement : α)
    (f : α → List β) (found : values[index]? = some removed) :
    values.flatMap f ⊆ (values.set index replacement).flatMap f ++ f removed := by
  induction values generalizing index with
  | nil => simp at found
  | cons value values induction =>
    cases index with
    | zero =>
      cases found
      intro child member
      rcases List.mem_append.mp member with first | rest
      · exact List.mem_append_right _ first
      · exact List.mem_append_left _ (List.mem_append_right _ rest)
    | succ index =>
      intro child member
      rcases List.mem_append.mp member with first | rest
      · exact List.mem_append_left _ (List.mem_append_left _ first)
      · rcases List.mem_append.mp (induction index found rest) with kept | lost
        · exact List.mem_append_left _ (List.mem_append_right _ kept)
        · exact List.mem_append_right _ lost

theorem erase_object_fields (machine : State) (node : NodeId) (stored : Object)
    (found : machine.heap.lookup node = some stored) :
    fields machine ⊆ fields {machine with heap := {machine.heap with objects := machine.heap.objects.set node.value none}} ++
      (OwningFields.object stored ++ QueueCustody.objectFields stored) := by
  have position : machine.heap.objects[node.value]? = some (some stored) := by
    simp only [Heap.lookup, Option.bind_eq_some_iff] at found
    obtain ⟨entry, atEntry, isStored⟩ := found
    cases entry <;> try contradiction
    cases isStored
    exact atEntry
  have objects := flatMap_remove_subset machine.heap.objects node.value (some stored) none
    (fun entry => entry.toList.flatMap OwningFields.object) position
  have queues := (QueueCustody.erase_object_partition machine node stored found).subset
  intro value member
  rcases List.mem_append.mp member with heap | queued
  · simp only [OwningFields.heap, List.mem_append] at heap
    rcases heap with (object | protection) | holding
    · rcases List.mem_append.mp (objects object) with kept | lost
      · exact List.mem_append_left _ (List.mem_append_left _ (List.mem_append_left _ (List.mem_append_left _ kept)))
      · exact List.mem_append_right _ (List.mem_append_left _ (by simpa using lost))
    · exact List.mem_append_left _ (List.mem_append_left _ (List.mem_append_left _ (List.mem_append_right _ protection)))
    · exact List.mem_append_left _ (List.mem_append_left _ (List.mem_append_right _ holding))
  · rcases List.mem_append.mp (queues queued) with kept | lost
    · exact List.mem_append_left _ (List.mem_append_right _ kept)
    · exact List.mem_append_right _ (List.mem_append_right _ lost)

theorem consumeValue_covered (machine : State) (heap : Heap) (value : Located) (extra : List Located)
    (accepted : consumeValue machine.heap value = some heap)
    (covered : Covered machine.heap.custody (fields machine ++ extra)) :
    Covered heap.custody (fields {machine with heap := heap} ++ extra) := by
  simp only [consumeValue, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨book, consumed, rfl⟩ := accepted
  exact consume_covered _ _ _ _ _ consumed covered

theorem retireObject_covered (machine : State) (heap : Heap) (value : Located) (node : NodeId) (stored : Object)
    (extra : List Located) (looked : lookupObject machine value = .ok (node, stored))
    (accepted : retireObject machine.heap value = some heap)
    (covered : Covered machine.heap.custody (fields machine ++ extra)) :
    Covered heap.custody (fields {machine with heap := heap} ++
      (OwningFields.object stored ++ QueueCustody.objectFields stored) ++ extra) := by
  obtain ⟨⟨schema, token, reference⟩, found⟩ := CellStability.lookupObject_reference _ _ _ _ looked
  unfold retireObject at accepted
  rw [reference] at accepted
  cases token <;> try contradiction
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  have next := consumeValue_covered machine middle value extra consumed covered
  have objects := ObjectOwners.consume_objects _ _ _ consumed
  have foundMiddle : middle.lookup node = some stored := by simpa only [Heap.lookup, objects] using found
  apply Covered.mono _ _ _ next
  intro field member
  rcases List.mem_append.mp member with prior | extraAt
  · exact List.mem_append_left _ (erase_object_fields {machine with heap := middle} node stored foundMiddle prior)
  · exact List.mem_append_right _ extraAt

private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

theorem lookup_binding (bindings : Environment) (binding : Binding)
    (unique : (bindings.map Binding.var).Nodup) (member : binding ∈ bindings) :
    lookupVariable bindings binding.var = some binding.located := by
  induction bindings with
  | nil => simp at member
  | cons head tail induction =>
    have parts := List.nodup_cons.mp unique
    rcases List.mem_cons.mp member with rfl | rest
    · simp [lookupVariable]
    · have different : head.var ≠ binding.var := by
        intro same
        exact parts.1 (same ▸ List.mem_map.mpr ⟨binding, rest, rfl⟩)
      simpa [lookupVariable, different] using induction parts.2 rest

private theorem mapM_map_ok (inputs : List α) (key : α → β) (f : β → Except Invalid γ) (g : α → γ)
    (checked : ∀ input ∈ inputs, f (key input) = .ok (g input)) :
    (inputs.map key).mapM f = .ok (inputs.map g) := by
  induction inputs with
  | nil => rfl
  | cons head tail induction =>
    simp only [List.map_cons, List.mapM_cons, checked head (by simp), bind, Except.bind,
      induction (fun input member => checked input (List.mem_cons_of_mem _ member)), pure, Except.pure]

theorem invoke_captures_unique (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) :
    (Analysis.captures context.captures function).Nodup := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, _, _, _, created, _⟩ := accepted
  simp only [createScope, bind, except_bind_ok] at created
  obtain ⟨_, checked, _⟩ := created
  have unique : ((Analysis.captures context.captures function) ++ definition.parameters).Nodup := by
    have admitted := require_ok _ _ _ checked
    simp only [bindArguments, Bool.and_eq_true, decide_eq_true_eq] at admitted
    exact admitted.1.2
  exact (List.nodup_append.mp unique).1

theorem applyClosure_valid (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = [])
    (contracts : ClosureContracts.Valid context machine.heap.objects) : Valid after.state := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  case closure schema function bindings =>
    obtain ⟨⟨rootSchema, token, reference⟩, found⟩ := CellStability.lookupObject_reference _ _ _ _ looked
    have contract := ClosureContracts.heap_lookup context machine.heap node _ found contracts
    have order := contract.2
    rw [reference] at accepted
    cases token with
    | none =>
      simp only [pure, Except.pure, Except.bind] at accepted
      exact invokeFunction_valid _ _ _ _ _ _ accepted valid empty
    | some token =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨heap, consumed, invoked⟩ := accepted
      have unique := invoke_captures_unique _ _ _ _ _ _ invoked
      have captured : (Analysis.captures context.captures function).mapM
          (fun binder => fromOption (lookupVariable bindings binder) .reference) = .ok (bindings.map Binding.located) := by
        rw [← order]
        apply mapM_map_ok
        intro binding member
        simp only [lookup_binding bindings binding (order ▸ unique) member, fromOption]
      have next := retireObject_covered machine heap closure node _ [] looked consumed (by simpa [Valid] using valid)
      apply invokeFunction_covered _ _ _ _ _ _ _ captured invoked ?_ empty
      apply Covered.mono _ _ _ next
      intro field member
      simp only [List.append_nil, OwningFields.object, QueueCustody.objectFields, DisposalShape.object,
        List.filter_nil, List.append_nil] at member
      rcases List.mem_append.mp member with prior | child
      · exact List.mem_append_left _ prior
      · exact List.mem_append_right _ (List.mem_append_left _ child)

theorem allocateObject_fields (machine : State) (heap : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (heap, value)) :
    fields machine ++ (OwningFields.object stored ++ QueueCustody.objectFields stored) ⊆ fields {machine with heap := heap} := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, rfl⟩ := accepted
    intro field member
    simp only [fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.heapFields,
      List.flatMap_append, List.flatMap_singleton, Option.toList_some, List.mem_append] at member ⊢
    grind only []
  · obtain ⟨_, _, rfl, rfl⟩ := accepted
    intro field member
    simp only [fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.heapFields,
      List.flatMap_append, List.flatMap_singleton, Option.toList_some, List.mem_append] at member ⊢
    grind only []

theorem allocate_covered (machine : State) (heap : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located) (extra : List Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (heap, value))
    (covered : Covered machine.heap.custody
      (fields machine ++ (OwningFields.object stored ++ QueueCustody.objectFields stored) ++ extra)) :
    Covered heap.custody (fields {machine with heap := heap} ++ value :: extra) := by
  have next := allocateObject_covered _ _ _ _ _ _ _ _ accepted covered
  apply Covered.mono _ _ _ next
  intro field member
  rcases List.mem_append.mp member with prior | new
  · rcases List.mem_append.mp prior with prior | extraAt
    · exact List.mem_append_left _ (allocateObject_fields _ _ _ _ _ _ _ accepted prior)
    · exact List.mem_append_right _ (List.mem_cons_of_mem _ extraAt)
  · exact List.mem_append_right _ (List.mem_cons.mpr (Or.inl (List.mem_singleton.mp new)))

theorem makeClosureWithValues_valid (machine : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, checked, ⟨middle, owner⟩, reserved, moved, movedAt, ⟨heap, result⟩, allocated, finished⟩ := accepted
  have count : (Analysis.captures context.captures function).length = values.length := by
    simpa only [Bool.and_eq_true, beq_iff_eq] using (Bool.and_eq_true_iff.mp (require_ok _ _ _ checked)).1
  have next := temporary_covered machine middle owner [] reserved (by simpa [Valid] using valid)
  have movedCover := moveValues_covered _ _ _ _ _ movedAt (by simpa using next)
  rw [← move_fields _ _ _ _ movedAt] at movedCover
  have allocatedCover := allocate_covered {middle with heap := moved} heap _ _ owner _ result [] allocated (by
    apply Covered.mono _ _ _ movedCover
    intro field member
    rcases List.mem_append.mp member with prior | incoming
    · exact List.mem_append_left _ (List.mem_append_left _ prior)
    · obtain ⟨index, bounded, rfl⟩ := List.mem_mapIdx.mp incoming
      apply List.mem_append_left
      apply List.mem_append_right
      apply List.mem_append_left
      apply List.mem_map.mpr
      refine ⟨_, List.mem_mapIdx.mpr ⟨index, ?_, rfl⟩, ?_⟩
      · simpa only [List.length_zip, count, Nat.min_self] using bounded
      · simp only [List.getElem_zip])
  have done := finishTemporary_covered _ _ [] _ finished
    (by simpa only [temporary_control _ _ _ reserved] using empty) allocatedCover
  simpa only [Valid, List.append_nil] using done

theorem makeClosure_valid (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨values, _, created⟩ := accepted
  exact makeClosureWithValues_valid _ _ _ _ _ _ created valid empty

theorem consume_result_covered (book after : Custody.Book) (values operands : List Located)
    (owner : Custody.Owner) (result : SemanticValue)
    (accepted : Custody.consume book ((operands.flatMap fun value => ownedTokens value.value).filter
      (fun token => !(ownedTokens result).contains token)) owner = some after)
    (covered : Covered book (values ++ operands.mapIdx (fun _ value => retainAt value owner))) :
    Covered after (values ++ [Located.mk result owner]) := by
  unfold Custody.consume at accepted
  split at accepted <;> try contradiction
  cases accepted
  intro entry member
  have prior := (List.mem_filter.mp member).1
  have kept := (List.mem_filter.mp member).2
  obtain ⟨field, fieldAt, ownerAt, tokenAt⟩ := covered entry prior
  rcases List.mem_append.mp fieldAt with old | moved
  · exact ⟨field, List.mem_append_left _ old, ownerAt, tokenAt⟩
  · obtain ⟨index, bounded, rfl⟩ := List.mem_mapIdx.mp moved
    refine ⟨⟨result, owner⟩, List.mem_append_right _ (by simp), ownerAt, ?_⟩
    have inputAt : entry.token ∈ operands.flatMap (fun value => ownedTokens value.value) :=
      List.mem_flatMap.mpr ⟨operands[index], List.getElem_mem _, tokenAt⟩
    by_cases resultAt : entry.token ∈ ownedTokens result
    · exact resultAt
    · have removedAt : entry.token ∈ (operands.flatMap fun value => ownedTokens value.value).filter
          (fun token => !(ownedTokens result).contains token) :=
        List.mem_filter.mpr ⟨inputAt, by simpa using resultAt⟩
      have present : ((operands.flatMap fun value => ownedTokens value.value).filter
          (fun token => !(ownedTokens result).contains token)).contains entry.token = true := by
        simpa only [List.contains_iff_mem] using removedAt
      rw [present] at kept
      contradiction

theorem commitPure_valid (machine : State) (opcode : Opcode) (operands : List Located)
    (result : SemanticValue) (after : Transition)
    (accepted : commitPure machine opcode operands result = .ok after) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, accepted⟩ := accepted
  have next := temporary_covered machine middle owner [] reserved (by simpa [Valid] using valid)
  have emptyMiddle : QueueCustody.controlFields middle.control = [] := by
    rw [temporary_control _ _ _ reserved]; exact empty
  split at accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, finished⟩ := accepted
    have done := finishTemporary_covered _ _ [] _ finished emptyMiddle
      (Covered.mono _ _ _ (by simpa using next) (fun _ member => List.mem_append_left _ member))
    simpa only [Valid, List.append_nil] using done
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨heap, moved, _, _, custody, consumed, finished⟩ := accepted
    have movedCover := moveValues_covered _ _ _ _ _ moved (by simpa using next)
    have resultCover := consume_result_covered _ _ _ _ _ _ consumed movedCover
    rw [← move_fields _ _ _ _ moved] at resultCover
    have done := finishTemporary_covered _ _ [] _ finished emptyMiddle resultCover
    simpa only [Valid, List.append_nil] using done

end CustodyCoverage
end BoundaryV2.Profile.Source.Machine
