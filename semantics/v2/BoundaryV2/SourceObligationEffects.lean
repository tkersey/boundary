import BoundaryV2.SourceObligationControl

namespace BoundaryV2.Profile.Source.Machine
namespace ObligationLocations

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem allocate_partition_valid (machine : State) (heap : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (heap, value))
    (valid : (fields machine ++ object stored).Perm (expected machine.heap)) : Valid {machine with heap := heap} := by
  obtain ⟨same, obligations⟩ := allocate_parts _ _ _ _ _ _ _ accepted
  simpa only [Valid, same, expected, obligations] using valid

theorem temporary_partition (machine after : State) (owner : Custody.Owner) (extra : List Entry)
    (accepted : temporary machine = .ok (after, owner))
    (valid : (fields machine ++ extra).Perm (expected machine.heap)) :
    (fields after ++ extra).Perm (expected after.heap) := by
  obtain ⟨same, obligations⟩ := temporary_parts _ _ _ accepted
  simpa only [same, expected, obligations] using valid

theorem trim_frame (context : Context) (saved : Frame) : frame (trimFrame context saved) = frame saved := by
  cases saved <;> rfl

theorem selected_partition (machine : State) (context : Context) (identity : AttachmentId) (selected : Selection)
    (found : selectAttachment identity machine.stack = some selected) (valid : Valid machine) :
    (fields {machine with stack := selected.outside} ++
      (selected.inside.map (trimFrame context)).flatMap frame).Perm (expected machine.heap) := by
  have trimmed : (selected.inside.map (trimFrame context)).flatMap frame = selected.inside.flatMap frame := by
    simp only [List.flatMap_map, trim_frame]
  rw [trimmed]
  have shape := selection_reconstructs _ _ _ found
  apply List.Perm.trans (List.perm_append_comm (l₁ := fields {machine with stack := selected.outside}))
  simpa only [Valid, fields, shape, List.flatMap_append, List.flatMap_cons, frame,
    List.nil_append, List.append_assoc] using valid

theorem openRequest_valid (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition)
    (accepted : openRequest machine context operation operands = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨effect, _, _, _, payload, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact valid
  · simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
    cases stored <;> try contradiction
    rename_i identity nominal looked
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, selected, selectedAt, definition, _, clause, _, accepted⟩ := accepted
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_valid _ _ _ _ _ _ invoked valid
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨shape, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i signature shapeAt
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have moved := (fromOption_ok _ _ _).mp moved
      have storeValid := move_valid _ _ _ _ moved valid
      have partition := selected_partition {machine with heap := store} context identity selected selectedAt storeValid
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, reserved, ⟨finalStore, token⟩, allocated, staged, stagedOk, invoked⟩ := accepted
        have temporaryValid := temporary_partition _ _ _ _ reserved partition
        have created := allocate_partition_valid _ _ _ _ _ _ _ allocated (by
          first
          | simpa only [object] using temporaryValid
          | split <;> simpa only [object] using temporaryValid)
        have stagedValid := finishTemporary_valid _ _ _ stagedOk created
        exact invokeFunction_valid _ _ _ _ _ _ invoked stagedValid

private theorem foldlM_preserves (items : List β) (step : α → β → Except Invalid α)
    (property : α → Prop) (preserved : ∀ before item after, step before item = .ok after → property before → property after)
    (before after : α) (accepted : items.foldlM step before = .ok after) (holds : property before) : property after := by
  induction items generalizing before with
  | nil => cases accepted; exact holds
  | cons item items induction =>
    simp only [List.foldlM_cons, bind, except_bind_ok] at accepted
    obtain ⟨middle, stepped, rest⟩ := accepted
    exact induction middle rest (preserved before item middle stepped holds)

theorem installHandler_valid (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  have heap : Valid {machine with heap := store} := by
    apply foldlM_preserves _ _ (fun pair : Heap × List Located => Valid {machine with heap := pair.1}) ?_ _ _ allocated valid
    intro before item after accepted formed
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := accepted
    exact allocate_empty_valid {machine with heap := heap} _ _ _ _ _ _ allocated formed rfl
  let active : Activation := ⟨⟨machine.heap.nextAttachment⟩, handler, handlerEnvironment context definition bindings,
    stored, machine.invocation, machine.scope, (activeAttachments machine.stack).head?⟩
  have next := stack_valid {machine with heap := store} (.handler active :: machine.stack) heap rfl
  exact applyClosure_valid _ _ _ _ _ applied next

theorem completeHandler_valid (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i active tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact stack_valid machine tail valid (by simp [stacked, frame])

theorem enterRegion_valid (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, signature, _, schema, _, _, _, ⟨heap, value⟩, allocated, applied⟩ := accepted
  have seed := same_storage_valid machine {machine.heap with nextRegion := machine.heap.nextRegion + 1} valid rfl rfl
  have next := allocate_empty_valid _ _ _ _ _ _ _ allocated seed rfl
  have stacked := stack_valid {machine with heap := heap} (.region ⟨machine.heap.nextRegion⟩ :: machine.stack) next rfl
  exact applyClosure_valid _ _ _ _ _ applied stacked

theorem executeEffectTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_valid _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    exact installHandler_valid _ _ _ _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    exact resumeValue_valid _ _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    exact resumeValue_valid _ _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    exact resumeComputation_valid _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    exact enterRegion_valid _ _ _ _ _ _ accepted valid

end ObligationLocations
end BoundaryV2.Profile.Source.Machine
