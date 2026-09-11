import BoundaryV2.SourceFailureSchemas

namespace BoundaryV2.Profile.Source.Machine
namespace FailureSchemas

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

theorem heapPrimitive_preserves_types (machine : State) (context : Context)
    (operation : Primitives.GraphOperation) (schema : SchemaId .source) (immediate : Nat)
    (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after)
    (typed : All context.source machine) : All context.source after.state := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact makeClosureWithValues_preserves_types _ _ _ _ _ _ accepted typed
  case cellNew =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, moveOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleTyped := temporary_preserves_types _ _ _ _ temporaryOk typed
    have movedTyped := moveValues_preserves_types _ _ _ _ _ moveOk middleTyped
    have allocatedTyped := allocateObject_preserves_types _
      { middle with heap := { moved with nextCell := moved.nextCell + 1 } }
      _ _ _ _ _ _ allocated movedTyped (by simp [object, Types])
    exact finishTemporary_preserves_types _ _ _ _ finished allocatedTyped
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_preserves_types _ _ _ _ accepted typed
  case cellSet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, store, replaced, accepted⟩ := accepted
    have storeTyped := replaceObject_preserves_types _ _ _ _ _ replaced typed (by simp [object, Types])
    exact scopedValue_preserves_types _ _ _ _ accepted storeTyped
  case package =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, moveOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleTyped := temporary_preserves_types _ _ _ _ temporaryOk typed
    have movedTyped := moveValues_preserves_types _ _ _ _ _ moveOk middleTyped
    have allocatedTyped := allocateObject_preserves_types _ _ _ _ _ _ _ _ allocated movedTyped (by simp [object, Types])
    exact finishTemporary_preserves_types _ _ _ _ finished allocatedTyped
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    have storeTyped := retireObject_preserves_types _ _ _ _ retired typed
    exact commitPure_preserves_types _ _ _ _ _ _ accepted storeTyped
  case cloneResumption =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i storedNode saved matched
    cases matched
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, retired, retireOk, ⟨middle, owner⟩, temporaryOk,
      ⟨store, result⟩, allocated, finished⟩ := accepted
    have captureTyped := lookupObject_types _ _ _ _ _ looked typed
    have retiredTyped := retireObject_preserves_types _ _ _ _ retireOk typed
    have middleTyped := temporary_preserves_types _ _ _ _ temporaryOk retiredTyped
    have allocatedTyped := allocateObject_preserves_types _ _ _ _ _ _ _ _ allocated middleTyped captureTyped
    exact finishTemporary_preserves_types _ _ _ _ finished allocatedTyped
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleTyped := temporary_preserves_types _ _ _ _ temporaryOk typed
    have allocatedTyped := allocateObject_preserves_types _ _ _ _ _ _ _ _ allocated middleTyped (by simp [object, Types])
    exact finishTemporary_preserves_types _ _ _ _ finished allocatedTyped
  case resourceUnpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, store, retired, accepted⟩ := accepted
      have storeTyped := retireObject_preserves_types _ _ _ _ retired typed
      exact scopedValue_preserves_types _ _ _ _ accepted storeTyped
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_preserves_types _ _ _ _ accepted typed
    · contradiction

theorem executePrimitive_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after)
    (typed : All context.source machine) : All context.source after.state := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · exact authoredFailure_preserves_types _ _ _ _ _ accepted typed
  · exact commitPure_preserves_types _ _ _ _ _ _ accepted typed
  · exact heapPrimitive_preserves_types _ _ _ _ _ _ _ accepted typed

theorem completeHandler_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i active tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  simp only [All, Types, state, stacked, control, frame, List.flatMap_cons,
    List.mem_append] at typed ⊢
  grind only []

theorem enterRegion_preserves_types (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after)
    (typed : All context.source machine) : All context.source after.state := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, ⟨store, value⟩, allocated, applied⟩ := accepted
  have allocatedTyped := allocateObject_preserves_types _
    { machine with heap := { machine.heap with nextRegion := machine.heap.nextRegion + 1 } }
    _ _ _ _ _ _ allocated typed (by simp [object, Types])
  have frameTyped : All context.source
      { machine with heap := store, stack := .region ⟨machine.heap.nextRegion⟩ :: machine.stack } := by
    simpa only [All, state, List.flatMap_cons, frame, List.nil_append] using allocatedTyped
  exact applyClosure_preserves_types _ _ _ _ _ applied frameTyped


theorem trim_frame_types (context : Context) (saved : Frame)
    (typed : Types context.source (frame saved)) :
    Types context.source (frame (trimFrame context saved)) := by
  cases saved <;> exact typed


private theorem foldlM_preserves (items : List β) (step : α → β → Except Invalid α)
    (property : α → Prop) (preserved : ∀ before item after, step before item = .ok after → property before → property after)
    (before after : α) (accepted : items.foldlM step before = .ok after) (holds : property before) : property after := by
  induction items generalizing before with
  | nil => cases accepted; exact holds
  | cons first rest induction =>
    simp only [List.foldlM_cons, bind, except_bind_ok] at accepted
    obtain ⟨middle, stepped, accepted⟩ := accepted
    exact induction middle accepted (preserved before first middle stepped holds)

theorem installHandler_preserves_types (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after)
    (typed : All context.source machine) :
    All context.source after.state := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  let property (pair : Heap × List Located) : Prop := All context.source { machine with heap := pair.1 }
  have seedTyped : property ({ machine.heap with nextAttachment := machine.heap.nextAttachment + 1 }, []) := typed
  have allTyped := foldlM_preserves _ _ property (by
    intro before item after stepOk beforeTyped
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at stepOk
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := stepOk
    exact allocateObject_preserves_types _ { machine with heap := heap }
      _ _ _ _ _ _ allocated beforeTyped (by simp [object, Types])) _ _ allocated seedTyped
  have framedTyped : All context.source
      { machine with heap := store, stack := (Frame.handler ⟨⟨machine.heap.nextAttachment⟩, handler, handlerEnvironment context definition bindings, stored,
          machine.invocation, machine.scope, (activeAttachments machine.stack).head?⟩) :: machine.stack } := by
    simp only [property, All, Types, state, List.flatMap_cons, frame, List.mem_append, List.not_mem_nil] at allTyped ⊢
    grind only []
  exact applyClosure_preserves_types _ _ _ _ _ applied framedTyped

theorem activateCapture_preserves_types (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture machine context saved successor = .ok after) (typed : All context.source machine)
    (captureTyped : Types context.source (capture saved)) :
    All context.source after := by
  simp only [activateCapture, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none =>
    simp only [Option.isSome_none, Bool.false_or, pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    split
    all_goals simp only [All, Types, state, List.flatMap_append, List.flatMap_cons,
      List.flatMap_nil, frame, capture, List.append_nil, List.mem_append] at typed captureTyped ⊢
    all_goals grind only []
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨definition, _, _, _, _, _, delimiter, rfl, rfl⟩ := accepted
    simp only [All, Types, state, Option.isSome_some, Bool.true_or, if_true,
      List.flatMap_append, List.flatMap_cons, List.flatMap_nil, frame, capture,
      List.append_nil, List.mem_append] at typed captureTyped ⊢
    grind only []

theorem takeCapture_preserves_types (machine : State) (context : Context) (token : Located)
    (after : State × Capture) (accepted : takeCapture machine context token = .ok after)
    (typed : All context.source machine) :
    All context.source after.1 ∧ Types context.source (capture after.2) := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, lookup, accepted⟩ := accepted
  have storedTyped := lookupObject_types _ _ _ _ _ lookup typed
  cases stored <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨store, retired, rfl⟩ := accepted
    exact ⟨retireObject_preserves_types _ _ _ _ retired typed, storedTyped⟩
  · exact instantiateCapture_preserves_types _ _ _ _ accepted typed storedTyped

theorem resumeValue_preserves_types (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after)
    (typed : All context.source machine) :
    All context.source after.state := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have capturedTyped := takeCapture_preserves_types _ _ _ _ captured typed
  have activeTyped := activateCapture_preserves_types _ _ _ _ _ activated capturedTyped.1 capturedTyped.2
  have middleTyped := temporary_preserves_types _ _ _ _ temporaryOk activeTyped
  have movedTyped := moveValues_preserves_types _ _ _ _ _ moved middleTyped
  exact finishTemporary_preserves_types _ _ _ _ finished movedTyped

theorem resumeComputation_preserves_types (machine : State) (context : Context)
    (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after)
    (typed : All context.source machine) : All context.source after.state := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  have capturedTyped := takeCapture_preserves_types _ _ _ _ captured typed
  have activeTyped := activateCapture_preserves_types _ _ _ _ _ activated capturedTyped.1 capturedTyped.2
  exact applyClosure_preserves_types _ _ _ _ _ applied activeTyped

theorem openRequest_preserves_types (machine : State) (context : Context)
    (operation : Operation) (operands : List Located) (after : Transition)
    (accepted : openRequest machine context operation operands = .ok after)
    (typed : All context.source machine) : All context.source after.state := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    simp only [All, Types, state, status, List.mem_append, List.not_mem_nil] at typed ⊢
    grind only []
  · simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
    cases stored <;> try contradiction
    rename_i identity nominal lookup
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, selected, selectedAt, definition, _, clause, _, accepted⟩ := accepted
    have reconstructed := selection_reconstructs identity machine.stack selected selectedAt
    have outsideTyped : Types context.source (selected.outside.flatMap frame) := by
      intro binding member
      apply typed
      simp [state, reconstructed, member]
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_preserves_types _ _ _ _ _ _ invoked typed
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨shape, shapeAt, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i signature
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have moved : moveValues machine.heap (_ :: _) (Custody.Owner.receiver ⟨machine.heap.nextInvocation⟩) = some store :=
        (fromOption_ok _ _ _).mp moved
      have movedTyped := moveValues_preserves_types _ _ _ _ _ moved typed
      have framesTyped : Types context.source ((selected.inside.map (trimFrame context)).flatMap frame) := by
        intro binding member
        simp only [List.flatMap_map, List.mem_flatMap] at member
        obtain ⟨saved, savedMember, member⟩ := member
        apply trim_frame_types context saved _ binding member
        exact frame_types _ _ _ (by simp [reconstructed, savedMember]) typed
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, temporaryOk, ⟨finalStore, token⟩, allocated, staged, stagedOk, rfl⟩ := accepted
        have startingTyped := with_stack_types _ _ selected.outside movedTyped outsideTyped
        have outsideTypes := temporary_preserves_types _ _ _ _ temporaryOk startingTyped
        have allocatedTypes := allocateObject_preserves_types _ _ _ _ _ _ _ _ allocated outsideTypes (by
          try split
          all_goals simp only [object, capture, Types] at framesTyped ⊢
          all_goals grind only [])
        have stagedTypes := finishTemporary_preserves_types _ _ _ _ stagedOk allocatedTypes
        exact with_control_types _ _ _ stagedTypes (by simp [control, Types])

theorem executeEffectTerm_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after)
    (typed : All context.source machine) : All context.source after.state := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases term <;> simp only at accepted <;> try contradiction
  case perform operation => exact openRequest_preserves_types _ _ _ _ _ accepted typed
  case handle =>
    split at accepted <;> try contradiction
    exact installHandler_preserves_types _ _ _ _ _ _ _ _ accepted typed
  case resumeValue =>
    split at accepted <;> try contradiction
    exact resumeValue_preserves_types _ _ _ _ _ _ accepted typed
  case resumeWith =>
    split at accepted <;> try contradiction
    exact resumeValue_preserves_types _ _ _ _ _ _ accepted typed
  case resumeComputation =>
    split at accepted <;> try contradiction
    exact resumeComputation_preserves_types _ _ _ _ _ accepted typed
  case withRegion =>
    split at accepted <;> try contradiction
    exact enterRegion_preserves_types _ _ _ _ _ _ accepted typed

end FailureSchemas
end BoundaryV2.Profile.Source.Machine
