import BoundaryV2.SourceAllocationLaws

namespace BoundaryV2.Profile.Source.Machine

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) : value.bind next = .ok result ↔
      ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem clone_safe_frame_values (source : Module) (frame : Frame)
    (accepted : frameCloneSafe source frame = true) (value : Located)
    (member : value ∈ frameValues frame) :
    Traits.check source.schemas .clone value.value.schema = true ∧ ownedTokens value.value = [] := by
  cases frame <;> simp_all [frameCloneSafe, frameValues, List.all_eq_true, Bool.and_eq_true] <;> grind

theorem clone_safe_captured_values (source : Module) (capture : Capture)
    (accepted : captureCloneSafe source capture = true) :
    (∀ frame ∈ capture.frames, ∀ value ∈ frameValues frame,
      Traits.check source.schemas .clone value.value.schema = true ∧ ownedTokens value.value = []) ∧
    (∀ value ∈ capture.delimiter.environment.map Binding.located ++ capture.delimiter.state ++ capture.useSiteCapabilities,
      Traits.check source.schemas .clone value.value.schema = true ∧ ownedTokens value.value = []) ∧
    (∀ cell ∈ capture.frozenCells,
      Traits.check source.schemas .clone cell.content.value.schema = true ∧ ownedTokens cell.content.value = []) := by
  simp only [captureCloneSafe, Bool.and_eq_true, List.all_eq_true, List.isEmpty_iff] at accepted
  exact ⟨fun frame member value found => clone_safe_frame_values source frame (accepted.1.1 frame member) value found,
    accepted.1.2, accepted.2⟩

theorem clone_safe_has_no_captured_custody (source : Module) (heap : Heap) (capture : Capture)
    (accepted : allCaptureCloneSafe source heap capture = true) :
    captureCloneSafe source capture = true ∧ capturedHoldings heap capture = [] := by
  simpa [allCaptureCloneSafe, Bool.and_eq_true] using accepted

theorem clone_rejects_active_holdings (state : State) (context : Context) (capture : Capture)
    (owned : capturedHoldings state.heap capture ≠ []) :
    instantiateCapture state context capture = .error .custody := by
  have rejected : allCaptureCloneSafe context.source state.heap capture = false := by
    simp [allCaptureCloneSafe, owned]
  simp [instantiateCapture, rejected, require, bind, Except.bind]

/-- Nested dormant templates receive the same structural and live-custody
check as the outer capture before any copies are installed. -/
theorem instantiation_checks_dormant_templates (state after : State) (context : Context)
    (capture instantiated inner : Capture) (node : NodeId)
    (member : node ∈ cloneSupport state.heap capture)
    (found : state.heap.lookup node = some (.multiTemplate inner))
    (accepted : instantiateCapture state context capture = .ok (after, instantiated)) :
    allCaptureCloneSafe context.source state.heap inner = true := by
  simp only [instantiateCapture, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, dormant, _⟩ := accepted
  have checked : ((cloneSupport state.heap capture).filterMap (fun node =>
      match state.heap.lookup node with | some (.multiTemplate inner) => some inner | _ => none)).all
        (allCaptureCloneSafe context.source state.heap) = true := by
    unfold require at dormant
    split at dormant
    · assumption
    · contradiction
  exact List.all_eq_true.mp checked inner (List.mem_filterMap.mpr ⟨node, member, by rw [found]⟩)

theorem instantiate_preserves_custody (state after : State) (context : Context)
    (capture instantiated : Capture)
    (accepted : instantiateCapture state context capture = .ok (after, instantiated)) :
    after.heap.custody = state.heap.custody := by
  simp only [instantiateCapture, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, exactState⟩ := accepted
  cases exactState
  rfl

theorem retirement_consumes_each_token (before after : Heap) (value : Located)
    (token : CustodyToken) (member : token ∈ ownedTokens value.value)
    (accepted : retireObject before value = some after) :
    token ∉ after.custody.entries.map Custody.Entry.token := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, heap, consumed, rfl⟩ := accepted
  unfold consumeValue at consumed
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at consumed
  obtain ⟨custody, consumed, rfl⟩ := consumed
  exact Custody.consumed_token_absent _ _ _ _ consumed member

theorem temporary_retains_custody (before after : State) (owner : Custody.Owner)
    (accepted : temporary before = .ok (after, owner)) : after.heap.custody = before.heap.custody := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem finishTemporary_retains_custody (state : State) (value : Located) (after : Transition)
    (accepted : finishTemporary state value = .ok after) : after.state.heap.custody = state.heap.custody := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem reusable_allocation_retains_custody (before after : Heap) (schema : SchemaId .source)
    (object : Object) (owner : Custody.Owner) (value : Located)
    (accepted : allocateObject before schema object owner false = some (after, value)) :
    after.custody = before.custody := by
  simp [allocateObject] at accepted
  obtain ⟨rfl, _⟩ := accepted
  rfl

/-- Conversion retires the original one-shot custody before allocating the
reusable template. Every original token is absent from the completed result. -/
theorem one_shot_conversion_consumes_original (state : State) (context : Context)
    (schema : SchemaId .source) (immediate : Nat) (value : Located) (after : Transition)
    (token : CustodyToken) (member : token ∈ ownedTokens value.value)
    (accepted : heapPrimitive state context .cloneResumption schema immediate [value] = .ok after) :
    token ∉ after.state.heap.custody.entries.map Custody.Entry.token := by
  simp only [heapPrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → retirement_consumes_each_token,
    → temporary_retains_custody, → finishTemporary_retains_custody, → reusable_allocation_retains_custody]

end BoundaryV2.Profile.Source.Machine
