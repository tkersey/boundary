import BoundaryV2.SourceReferenceSafetyControl

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem instantiate_prior_value (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (value : SemanticValue) (good : ValueGood context.source.schemas machine.heap value) :
    ValueGood context.source.schemas after.heap value :=
  ⟨instantiation_keeps_prior_value_valid _ _ _ _ _ accepted _ good.1,
    (instantiate_preserves_custody _ _ _ _ _ accepted) ▸ good.2.1,
    TokenInventory.value_mono _ _ _ good.2.2 (instantiateCapture_allocation _ _ _ _ accepted).heap.custody⟩

theorem takeCapture_valid (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (token : Located) (after : State × Capture)
    (accepted : takeCapture machine context token = .ok after)
    (good : Valid context.source.schemas machine)
    (tokenGood : ValueGood context.source.schemas machine.heap token.value)
    (tokenModes : ValueModes context.source.schemas token.value) :
    Valid context.source.schemas after.1 ∧
    (∀ value ∈ ValueInventory.capture after.2, ValueGood context.source.schemas after.1.heap value) ∧
    (∀ value, ValueModes context.source.schemas value → ValueGood context.source.schemas machine.heap value →
      ValueGood context.source.schemas after.1.heap value) := by
  have modes := ReferenceContracts.initialized_execution_preserves_reference_modes _ _ _ _ _ initialized steps
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  · rename_i saved
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨store, retired, rfl⟩ := accepted
    have shape := retirement_shape _ _ _ retired tokenModes
    refine ⟨retirement_valid _ _ _ retired good shape tokenGood modes, ?_, ?_⟩
    · intro value member
      exact retirement_value _ _ _ _ retired good.live shape tokenGood
        (ValueInventory.lookupObject_preserves_all _ _ _ _ looked _ modes value member)
        (lookup_good _ _ _ _ looked good value member)
    · exact fun value mode holds => retirement_value _ _ _ _ retired good.live shape tokenGood mode holds
  · rename_i saved
    have atNode := (CellStability.lookupObject_reference _ _ _ _ looked).2
    have safety := CloneTraits.reachable_template_instantiation_preserves_references _ _ _ _ _ _
      initialized steps _ _ _ atNode accepted (values_valid good) (values_aligned good) good.live
    have bounded := TokenInventory.instantiate_preserves _ _ _ _ _ accepted (values_bounded good)
      (ValueInventory.lookupObject_preserves_all _ _ _ _ looked _ (values_bounded good))
    have grows := (instantiateCapture_allocation _ _ _ _ accepted).heap.custody
    refine ⟨⟨?_, safety.2.2.1⟩, ?_, fun value _ holds => instantiate_prior_value _ _ _ _ _ accepted value holds⟩
    · intro value member
      exact ⟨safety.1 value member, safety.2.1 value member,
        TokenInventory.value_mono _ _ _ (bounded.1 value member) grows⟩
    · intro value member
      exact ⟨safety.2.2.2.1 value member, safety.2.2.2.2 value member,
        TokenInventory.value_mono _ _ _ (bounded.2 value member) grows⟩

theorem activateCapture_heap (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture machine context saved successor = .ok after) : after.heap = machine.heap := by
  simp only [activateCapture, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨shape, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none =>
    simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted; rfl
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    rfl

theorem activateCapture_valid (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture machine context saved successor = .ok after)
    (good : Valid context.source.schemas machine)
    (captureGood : ∀ value ∈ ValueInventory.capture saved, ValueGood context.source.schemas machine.heap value)
    (successorGood : match successor with
      | none => True
      | some (_, stored, bindings) => (∀ value ∈ stored, ValueGood context.source.schemas machine.heap value.value) ∧
          (∀ binding ∈ bindings, ValueGood context.source.schemas machine.heap binding.located.value)) :
    Valid context.source.schemas after := by
  have values := activateCapture_preserves_all _ _ _ _ _ accepted _ good.values captureGood successorGood
  have heap := activateCapture_heap _ _ _ _ _ accepted
  exact ⟨heap ▸ values, heap ▸ good.live⟩

theorem resumeValue_valid (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after)
    (good : Valid context.source.schemas machine)
    (tokenGood : ValueGood context.source.schemas machine.heap token.value)
    (tokenModes : ValueModes context.source.schemas token.value)
    (argumentGood : ValueGood context.source.schemas machine.heap argument.value)
    (argumentModes : ValueModes context.source.schemas argument.value)
    (successorGood : match successor with
      | none => True
      | some (_, stored, bindings) => (∀ value ∈ stored, ValueGood context.source.schemas machine.heap value.value ∧ ValueModes context.source.schemas value.value) ∧
          (∀ binding ∈ bindings, ValueGood context.source.schemas machine.heap binding.located.value ∧ ValueModes context.source.schemas binding.located.value)) :
    Valid context.source.schemas after.state := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, shape, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have capturedGood := takeCapture_valid _ _ _ _ _ initialized steps _ _ captured good tokenGood tokenModes
  have activeGood := activateCapture_valid _ _ _ _ _ activated capturedGood.1 capturedGood.2.1 (by
    cases successor with
    | none => trivial
    | some successor =>
      exact ⟨fun value member => capturedGood.2.2 _ (successorGood.1 value member).2 (successorGood.1 value member).1,
        fun binding member => capturedGood.2.2 _ (successorGood.2 binding member).2 (successorGood.2 binding member).1⟩)
  have argumentTaken := capturedGood.2.2 _ argumentModes argumentGood
  have argumentActive : ValueGood context.source.schemas active.heap argument.value :=
    (activateCapture_heap _ _ _ _ _ activated) ▸ argumentTaken
  have argumentMiddle := temporary_value _ _ _ _ temporaryOk argumentActive
  exact finishTemporary_valid _ _ _ finished
    (move_valid _ _ _ _ moved (temporary_valid _ _ _ temporaryOk activeGood))
    (move_value _ _ _ _ _ moved argumentMiddle)

theorem resumeComputation_valid (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after)
    (good : Valid context.source.schemas machine)
    (tokenGood : ValueGood context.source.schemas machine.heap token.value)
    (tokenModes : ValueModes context.source.schemas token.value)
    (computationGood : ValueGood context.source.schemas machine.heap computation.value)
    (computationModes : ValueModes context.source.schemas computation.value) : Valid context.source.schemas after.state := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  have capturedGood := takeCapture_valid _ _ _ _ _ initialized steps _ _ captured good tokenGood tokenModes
  have activeGood := activateCapture_valid _ _ _ _ _ activated capturedGood.1 capturedGood.2.1 trivial
  have structures := ReferenceStructureContracts.takeCapture_preserves_reference_structure _ _ _ _ captured
    (ReferenceStructureContracts.initialized_execution_preserves_reference_structure _ _ _ _ _ initialized steps)
  have capturedModes := fun value member => ReferenceStructureContracts.structure_has_reference_modes _ _ (structures.2 value member)
  have activeModes := activateCapture_preserves_all _ _ _ _ _ activated _
    (fun value member => ReferenceStructureContracts.structure_has_reference_modes _ _ (structures.1 value member))
    capturedModes trivial
  have same := activateCapture_heap _ _ _ _ _ activated
  apply applyClosure_valid _ _ _ _ _ applied activeGood activeModes
    (same ▸ capturedGood.2.2 _ computationModes computationGood) computationModes
  · intro value member
    rw [same]
    apply capturedGood.2.1
    simp only [ValueInventory.capture, List.mem_append, List.mem_map]
    exact Or.inl (Or.inr ⟨value, member, rfl⟩)
  · intro value member
    apply capturedModes
    simp only [ValueInventory.capture, List.mem_append, List.mem_map]
    exact Or.inl (Or.inr ⟨value, member, rfl⟩)

end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
