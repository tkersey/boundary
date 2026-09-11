import BoundaryV2.SourceReferenceSafetyHandlers

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

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

theorem openRequest_valid (machine : State) (context : Context)
    (operation : Operation) (operands : List Located) (after : Transition)
    (accepted : openRequest machine context operation operands = .ok after)
    (good : Valid context.source.schemas machine)
    (inputs : ∀ value ∈ operands, ValueGood context.source.schemas machine.heap value.value) :
    Valid context.source.schemas after.state := by
  have typed := good.values
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨effect, _, _, _, payload, payloadAt, _, _, accepted⟩ := accepted
  have payloadTyped := inputs payload (List.mem_of_mem_drop (List.mem_of_head? payloadAt))
  have bodiesTyped : ∀ value ∈ ((operands.drop operation.capability.toList.length).drop 1).take operation.bodies.length,
      ValueGood context.source.schemas machine.heap value.value := by
    intro value member
    exact inputs value (List.mem_of_mem_drop (List.mem_of_mem_drop (List.mem_of_mem_take member)))
  have capsTyped : ∀ value ∈ (operands.drop operation.capability.toList.length).drop (1 + operation.bodies.length),
      ValueGood context.source.schemas machine.heap value.value := by
    intro value member
    exact inputs value (List.mem_of_mem_drop (List.mem_of_mem_drop member))
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    refine ⟨?_, good.live⟩
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.status,
      List.map_append, List.mem_append, List.mem_cons, List.mem_map] at typed ⊢
    grind only []
  · simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
    cases stored <;> try contradiction
    rename_i identity nominal lookup
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, selected, selectedAt, definition, _, clause, _, accepted⟩ := accepted
    have reconstructed := selection_reconstructs identity machine.stack selected selectedAt
    have activationTyped : ∀ value ∈ ValueInventory.activation selected.activation, ValueGood context.source.schemas machine.heap value := by
      intro value member
      apply typed
      simp [ValueInventory.state, reconstructed, ValueInventory.frame, member]
    have outer : ∀ binding ∈ selected.activation.environment, ValueGood context.source.schemas machine.heap binding.located.value := by
      intro binding member
      apply activationTyped
      simp only [ValueInventory.activation, ValueInventory.environment, List.mem_append, List.mem_map]
      exact Or.inl ⟨binding, member, rfl⟩
    have storedTyped : ∀ value ∈ selected.activation.state, ValueGood context.source.schemas machine.heap value.value := by
      intro value member
      apply activationTyped
      simp only [ValueInventory.activation, List.mem_append, List.mem_map]
      exact Or.inr ⟨value, member, rfl⟩
    have outsideTyped : ∀ value ∈ selected.outside.flatMap ValueInventory.frame, ValueGood context.source.schemas machine.heap value := by
      intro value member
      apply typed
      simp [ValueInventory.state, reconstructed, member]
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      apply invokeFunction_valid _ _ _ _ _ _ invoked good outer
      intro value member
      rcases List.mem_append.mp member with member | member
      · exact storedTyped value member
      · cases List.mem_singleton.mp member; exact payloadTyped
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨shape, shapeAt, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i signature
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have moved : moveValues machine.heap (payload :: ((operands.drop operation.capability.toList.length).drop 1).take operation.bodies.length)
          (Custody.Owner.receiver ⟨machine.heap.nextInvocation⟩) = some store := (fromOption_ok _ _ _).mp moved
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, temporaryOk, ⟨finalStore, token⟩, allocated, staged, stagedOk, rfl⟩ := accepted
        have movedLive := moveValues_preserves_live_objects _ _ _ _ moved good.live
        have temporaryFields := temporary_fields _ _ _ temporaryOk
        have outsideLive : outside.heap.CustodyLive := by
          intro entry member
          simpa only [Heap.lookup, temporaryFields.1] using movedLive entry (temporaryFields.2.1 ▸ member)
        have finalLive := allocateObject_preserves_live_objects _ _ _ _ _ _ _ allocated outsideLive
        have finishFields := finishTemporary_fields _ _ _ stagedOk
        have stagedLive : staged.state.heap.CustodyLive := by
          intro entry member
          simpa only [Heap.lookup, finishFields.1] using finalLive entry (finishFields.2.1 ▸ member)
        have transport : ∀ value, ValueGood context.source.schemas machine.heap value →
            ValueGood context.source.schemas staged.state.heap value := by
          intro value holds
          exact finishTemporary_value _ _ _ _ stagedOk (allocation_value _ _ _ _ _ _ _ _ allocated
            (temporary_value _ _ _ _ temporaryOk (move_value _ _ _ _ _ moved holds)))
        have typed : ValueInventory.All (ValueGood context.source.schemas staged.state.heap) machine :=
          fun value member => transport value (typed value member)
        have payloadTyped := transport _ payloadTyped
        have bodiesTyped := fun value member => transport _ (bodiesTyped value member)
        have capsTyped := fun value member => transport _ (capsTyped value member)
        have activationTyped := fun value member => transport _ (activationTyped value member)
        have outer := fun binding member => transport _ (outer binding member)
        have storedTyped := fun value member => transport _ (storedTyped value member)
        have outsideTyped := fun value member => transport _ (outsideTyped value member)
        have movedTyped := ValueInventory.moveValues_preserves_all machine store _ _ moved _ typed
        have framesTyped : ∀ value ∈ (selected.inside.map (trimFrame context)).flatMap ValueInventory.frame,
            ValueGood context.source.schemas staged.state.heap value := by
          intro value member
          simp only [List.flatMap_map, List.mem_flatMap] at member
          obtain ⟨saved, savedMember, member⟩ := member
          have originalMember := ValueInventory.trim_frame_subset context saved member
          apply typed
          simp only [ValueInventory.state, reconstructed, List.flatMap_append, List.mem_append, List.mem_flatMap]
          grind only []
        have frozenTyped := ValueInventory.frozen_cells_preserve_all { machine with heap := store }
          (activeRegions (selected.inside.map (trimFrame context))) _ movedTyped
        have captureTyped : ∀ value ∈ ValueInventory.capture
            ⟨clause.resumption, selected.inside.map (trimFrame context), selected.activation,
              (operands.drop operation.capability.toList.length).drop (1 + operation.bodies.length),
              activeRegions (selected.inside.map (trimFrame context)),
              frozenCells store (activeRegions (selected.inside.map (trimFrame context))), machine.scope, machine.invocation⟩,
            ValueGood context.source.schemas staged.state.heap value := by
          simp only [ValueInventory.capture, List.mem_append, List.mem_map]
          grind only []
        have startingTyped : ValueInventory.All (ValueGood context.source.schemas staged.state.heap)
            { machine with heap := store, stack := selected.outside, scope := selected.activation.scope, invocation := selected.activation.invocation } := by
          simp only [ValueInventory.All, ValueInventory.state, List.mem_append] at movedTyped ⊢
          grind only []
        have outsideTypes := ValueInventory.temporary_preserves_all _ _ _ temporaryOk _ startingTyped
        have allocatedTypes := ValueInventory.allocateObject_preserves_all outside finalStore clause.resumption
          _ owner (signature.use != .multi) token allocated _ outsideTypes (by
            first | exact captureTyped | (split <;> exact captureTyped))
        have tokenTyped : ValueGood context.source.schemas staged.state.heap token.value :=
          finishTemporary_value _ _ _ _ stagedOk (allocation_result _ _ _ _ _ _ _ allocated (by
            first | rfl | (split <;> rfl)))
        have stagedTypes := ValueInventory.finishTemporary_preserves_all _ _ _ stagedOk _ allocatedTypes tokenTyped
        have outgoingTyped : ∀ value ∈ (payload :: ((operands.drop operation.capability.toList.length).drop 1).take operation.bodies.length).mapIdx
            (fun index value => retainAt value (.receiver ⟨machine.heap.nextInvocation⟩ index)),
            ValueGood context.source.schemas staged.state.heap value.value := by
          intro value member
          simp only [List.mapIdx_eq_zipIdx_map, List.mem_map] at member
          obtain ⟨⟨original, index⟩, member, rfl⟩ := member
          rcases List.mem_cons.mp (List.fst_mem_of_mem_zipIdx member) with equal | member
          · cases equal; exact payloadTyped
          · exact bodiesTyped original member
        refine ⟨?_, stagedLive⟩
        simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.environment,
          List.map_append, List.mem_append, List.mem_map, List.mem_singleton] at stagedTypes ⊢
        grind only []


end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
