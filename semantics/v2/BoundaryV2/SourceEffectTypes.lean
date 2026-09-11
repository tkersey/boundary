import BoundaryV2.SourceCaptureValueTypes

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

namespace ValueInventory

theorem completeHandler_preserves_all (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) (property : SemanticValue → Prop)
    (holds : All property machine) : All property after.state := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  rename_i value delivered
  split at accepted <;> try contradiction
  rename_i active tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  simp only [All, state, delivered, stacked, control, frame, activation, List.flatMap_cons,
    List.map_append, List.map_cons, List.map_nil, List.mem_append, List.mem_singleton] at holds ⊢
  grind only []

theorem restoreResumeCaller_preserves_all (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) (property : SemanticValue → Prop)
    (holds : All property machine) : All property after.state := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  rename_i value delivered
  split at accepted <;> try contradiction
  rename_i invocation scope tail stacked
  have valueHolds : property value.value := by
    apply holds
    simp [state, delivered, control]
  have startHolds : All property { machine with scope := scope, invocation := invocation, stack := tail } := by
    simp only [All, state, stacked, List.flatMap_cons, frame, List.nil_append] at holds ⊢
    exact holds
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, movedOk, finished⟩ := accepted
  exact finishTemporary_preserves_all _ _ _ finished property
    (moveValues_preserves_all _ _ _ _ movedOk property (temporary_preserves_all _ _ _ temporaryOk property startHolds)) valueHolds

theorem restrict_environment_subset (bindings : Environment) (vars : List VariableId) :
    environment (restrictEnvironment bindings vars) ⊆ environment bindings := by
  intro value member
  obtain ⟨binding, bindingMember, rfl⟩ := List.mem_map.mp member
  exact List.mem_map.mpr ⟨binding, (List.mem_filter.mp bindingMember).1, rfl⟩

theorem trim_frame_subset (context : Context) (saved : Frame) : frame (trimFrame context saved) ⊆ frame saved := by
  cases saved <;> simp only [trimFrame, frame]
  all_goals first
    | exact restrict_environment_subset _ _
    | exact List.Subset.refl _
    | (intro value member
       rcases List.mem_append.mp member with member | member
       · exact List.mem_append_left _ (restrict_environment_subset _ _ member)
       · exact List.mem_append_right _ member)

theorem handler_environment_subset (context : Context) (handler : Handler .source) (bindings : Environment) :
    environment (handlerEnvironment context handler bindings) ⊆ environment bindings :=
  restrict_environment_subset _ _

theorem allocateObject_result (store after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject store schema stored owner exclusive = some (after, value)) :
    value.value = .reference schema ⟨store.objects.length⟩ (if exclusive then some ⟨store.nextCustody⟩ else none) := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨_, rfl⟩ := accepted; rfl
  · obtain ⟨_, _, _, rfl⟩ := accepted; rfl

end ValueInventory

theorem enterRegion_preserves_value_shapes (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine)
    (inputs : ∀ value ∈ arguments, ValueShape context.source.schemas value.value) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, signature, _, schema, _, _, schemaOk, ⟨store, value⟩, allocated, applied⟩ := accepted
  have shape : context.source.schemas[schema.value]? = some (.internal (.region descriptor)) := by
    simpa using require_ok _ _ _ schemaOk
  have allocatedTyped := ValueInventory.allocateObject_preserves_all
    { machine with heap := { machine.heap with nextRegion := machine.heap.nextRegion + 1 } }
    store schema _ _ false value allocated _ typed (by simp [ValueInventory.object])
  have valueTyped : ValueShape context.source.schemas value.value := by
    rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
    exact .reference shape rfl
  have frameTyped : ValueInventory.All (ValueShape context.source.schemas)
      { machine with heap := store, stack := .region ⟨machine.heap.nextRegion⟩ :: machine.stack } := by
    simpa only [ValueInventory.All, ValueInventory.state, List.flatMap_cons, ValueInventory.frame,
      List.nil_append] using allocatedTyped
  exact ValueInventory.applyClosure_preserves_all _ _ _ _ _ applied _ frameTyped
    (by simpa using And.intro valueTyped inputs)


private theorem foldlM_preserves (items : List β) (step : α → β → Except Invalid α)
    (property : α → Prop) (preserved : ∀ before item after, step before item = .ok after → property before → property after)
    (before after : α) (accepted : items.foldlM step before = .ok after) (holds : property before) : property after := by
  induction items generalizing before with
  | nil => cases accepted; exact holds
  | cons first rest induction =>
    simp only [List.foldlM_cons, bind, except_bind_ok] at accepted
    obtain ⟨middle, stepped, accepted⟩ := accepted
    exact induction middle accepted (preserved before first middle stepped holds)

theorem installHandler_preserves_value_shapes (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine)
    (inputs : ∀ value ∈ arguments, ValueShape context.source.schemas value.value)
    (storedTyped : ∀ value ∈ stored, ValueShape context.source.schemas value.value)
    (outer : ∀ binding ∈ bindings, ValueShape context.source.schemas binding.located.value) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  let property (pair : Heap × List Located) : Prop :=
    ValueInventory.All (ValueShape context.source.schemas) { machine with heap := pair.1 } ∧
    ∀ value ∈ pair.2, ValueShape context.source.schemas value.value
  have seedTyped : property ({ machine.heap with nextAttachment := machine.heap.nextAttachment + 1 }, []) :=
    ⟨typed, by simp⟩
  have allTyped := foldlM_preserves _ _ property (by
    intro before item after stepOk beforeTyped
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at stepOk
    obtain ⟨_, schemaOk, ⟨next, value⟩, allocated, rfl⟩ := stepOk
    have shape : context.source.schemas[schema.value]? = some (.internal (.capability clause.effect)) := by
      simpa using require_ok _ _ _ schemaOk
    have heapTyped := ValueInventory.allocateObject_preserves_all { machine with heap := heap }
      next schema _ _ false value allocated _ beforeTyped.1 (by simp [ValueInventory.object])
    have valueTyped : ValueShape context.source.schemas value.value := by
      rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
      exact .reference shape rfl
    refine ⟨heapTyped, ?_⟩
    intro child member
    rcases List.mem_append.mp member with member | member
    · exact beforeTyped.2 child member
    · cases List.mem_singleton.mp member; exact valueTyped) _ _ allocated seedTyped
  have selectedTyped : ∀ value ∈ ValueInventory.environment (handlerEnvironment context definition bindings),
      ValueShape context.source.schemas value := by
    intro value member
    have originalMember := ValueInventory.handler_environment_subset context definition bindings member
    obtain ⟨binding, bindingMember, rfl⟩ := List.mem_map.mp originalMember
    exact outer binding bindingMember
  have framedTyped : ValueInventory.All (ValueShape context.source.schemas)
      { machine with heap := store, stack := (Frame.handler ⟨⟨machine.heap.nextAttachment⟩, handler, handlerEnvironment context definition bindings, stored,
          machine.invocation, machine.scope, (activeAttachments machine.stack).head?⟩) :: machine.stack } := by
    have storeTyped := allTyped.1
    simp only [ValueInventory.All, ValueInventory.state, List.flatMap_cons, ValueInventory.frame,
      ValueInventory.activation, List.mem_append, List.mem_map] at storeTyped ⊢
    grind only []
  apply ValueInventory.applyClosure_preserves_all _ _ _ _ _ applied _ framedTyped
  intro value member
  rcases List.mem_append.mp member with member | member
  · exact allTyped.2 value member
  · exact inputs value member


theorem activateCapture_preserves_all (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture machine context saved successor = .ok after)
    (property : SemanticValue → Prop) (holds : ValueInventory.All property machine)
    (captureHolds : ∀ value ∈ ValueInventory.capture saved, property value)
    (successorHolds : match successor with
      | none => True
      | some (_, stored, bindings) => (∀ value ∈ stored, property value.value) ∧
          (∀ binding ∈ bindings, property binding.located.value)) : ValueInventory.All property after := by
  simp only [activateCapture, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨shape, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none =>
    simp only [Option.isSome_none, Bool.false_or, pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    split
    all_goals simp only [ValueInventory.All, ValueInventory.state, List.flatMap_append, List.flatMap_cons,
      List.flatMap_nil, ValueInventory.frame, ValueInventory.capture, List.append_nil,
      List.mem_append] at holds captureHolds ⊢
    all_goals grind only []
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨definition, _, _, _, _, _, delimiter, rfl, rfl⟩ := accepted
    have selectedHolds : ∀ value ∈ ValueInventory.environment (handlerEnvironment context definition bindings), property value := by
      intro value member
      have originalMember := ValueInventory.handler_environment_subset context definition bindings member
      obtain ⟨binding, bindingMember, rfl⟩ := List.mem_map.mp originalMember
      exact successorHolds.2 binding bindingMember
    simp only [ValueInventory.All, ValueInventory.state, Option.isSome_some, Bool.true_or, if_true,
      List.flatMap_append, List.flatMap_cons, List.flatMap_nil, ValueInventory.frame, ValueInventory.capture,
      ValueInventory.activation, List.append_nil, List.mem_append, List.mem_map] at holds captureHolds ⊢
    grind only []

theorem takeCapture_preserves_value_shapes (machine : State) (context : Context) (token : Located)
    (after : State × Capture) (accepted : takeCapture machine context token = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine) :
    ValueInventory.All (ValueShape context.source.schemas) after.1 ∧
    (∀ value ∈ ValueInventory.capture after.2, ValueShape context.source.schemas value) := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, lookup, accepted⟩ := accepted
  have storedTyped := ValueInventory.lookupObject_preserves_all machine token node stored lookup _ typed
  cases stored <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨store, retired, rfl⟩ := accepted
    exact ⟨ValueInventory.retireObject_preserves_all machine token store retired _ typed, storedTyped⟩
  · exact instantiateCapture_preserves_value_shapes _ _ _ _ accepted typed storedTyped

theorem resumeValue_preserves_value_shapes (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine)
    (argumentTyped : ValueShape context.source.schemas argument.value)
    (successorTyped : match successor with
      | none => True
      | some (_, stored, bindings) => (∀ value ∈ stored, ValueShape context.source.schemas value.value) ∧
          (∀ binding ∈ bindings, ValueShape context.source.schemas binding.located.value)) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, shape, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have capturedTyped := takeCapture_preserves_value_shapes _ _ _ _ captured typed
  have activeTyped := activateCapture_preserves_all _ _ _ _ _ activated _ capturedTyped.1 capturedTyped.2 (by cases successor <;> exact successorTyped)
  exact ValueInventory.finishTemporary_preserves_all _ _ _ finished _
    (ValueInventory.moveValues_preserves_all _ _ _ _ moved _
      (ValueInventory.temporary_preserves_all _ _ _ temporaryOk _ activeTyped)) argumentTyped

theorem resumeComputation_preserves_value_shapes (machine : State) (context : Context)
    (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  have capturedTyped := takeCapture_preserves_value_shapes _ _ _ _ captured typed
  have activeTyped := activateCapture_preserves_all _ _ _ _ _ activated _ capturedTyped.1 capturedTyped.2 trivial
  apply ValueInventory.applyClosure_preserves_all _ _ _ _ _ applied _ activeTyped
  intro value member
  apply capturedTyped.2
  simp only [ValueInventory.capture, List.mem_append, List.mem_map]
  exact Or.inl (Or.inr ⟨value, member, rfl⟩)

namespace ValueInventory

theorem frozen_cells_preserve_all (machine : State) (regions : List RegionInstanceId)
    (property : SemanticValue → Prop) (holds : All property machine) :
    ∀ cell ∈ frozenCells machine.heap regions, property cell.content.value := by
  intro cell member
  obtain ⟨⟨entry, index⟩, entryMember, found⟩ := List.mem_filterMap.mp member
  have originalMember := List.fst_mem_of_mem_zipIdx entryMember
  cases entry with
  | none => contradiction
  | some stored =>
    cases stored <;> simp only at found <;> try contradiction
    rename_i identity schema region content
    split at found <;> try contradiction
    cases found
    apply holds
    simp only [state, heap, List.mem_append, List.mem_flatMap]
    refine Or.inl (Or.inr (Or.inl (Or.inl ⟨some (.cell identity schema region content), originalMember, ?_⟩)))
    simp [object]

end ValueInventory

theorem openRequest_preserves_value_shapes (machine : State) (context : Context)
    (operation : Operation) (operands : List Located) (after : Transition)
    (accepted : openRequest machine context operation operands = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine)
    (inputs : ∀ value ∈ operands, ValueShape context.source.schemas value.value) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨effect, _, _, _, payload, payloadAt, _, _, accepted⟩ := accepted
  have payloadTyped := inputs payload (List.mem_of_mem_drop (List.mem_of_head? payloadAt))
  have bodiesTyped : ∀ value ∈ ((operands.drop operation.capability.toList.length).drop 1).take operation.bodies.length,
      ValueShape context.source.schemas value.value := by
    intro value member
    exact inputs value (List.mem_of_mem_drop (List.mem_of_mem_drop (List.mem_of_mem_take member)))
  have capsTyped : ∀ value ∈ (operands.drop operation.capability.toList.length).drop (1 + operation.bodies.length),
      ValueShape context.source.schemas value.value := by
    intro value member
    exact inputs value (List.mem_of_mem_drop (List.mem_of_mem_drop member))
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
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
    have activationTyped : ∀ value ∈ ValueInventory.activation selected.activation, ValueShape context.source.schemas value := by
      intro value member
      apply typed
      simp [ValueInventory.state, reconstructed, ValueInventory.frame, member]
    have outer : ∀ binding ∈ selected.activation.environment, ValueShape context.source.schemas binding.located.value := by
      intro binding member
      apply activationTyped
      simp only [ValueInventory.activation, ValueInventory.environment, List.mem_append, List.mem_map]
      exact Or.inl ⟨binding, member, rfl⟩
    have storedTyped : ∀ value ∈ selected.activation.state, ValueShape context.source.schemas value.value := by
      intro value member
      apply activationTyped
      simp only [ValueInventory.activation, List.mem_append, List.mem_map]
      exact Or.inr ⟨value, member, rfl⟩
    have outsideTyped : ∀ value ∈ selected.outside.flatMap ValueInventory.frame, ValueShape context.source.schemas value := by
      intro value member
      apply typed
      simp [ValueInventory.state, reconstructed, member]
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      apply ValueInventory.invokeFunction_preserves_all _ _ _ _ _ _ invoked _ typed outer
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
        have movedTyped := ValueInventory.moveValues_preserves_all machine store _ _ moved _ typed
        have framesTyped : ∀ value ∈ (selected.inside.map (trimFrame context)).flatMap ValueInventory.frame,
            ValueShape context.source.schemas value := by
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
            ValueShape context.source.schemas value := by
          simp only [ValueInventory.capture, List.mem_append, List.mem_map]
          grind only []
        have startingTyped : ValueInventory.All (ValueShape context.source.schemas)
            { machine with heap := store, stack := selected.outside, scope := selected.activation.scope, invocation := selected.activation.invocation } := by
          simp only [ValueInventory.All, ValueInventory.state, List.mem_append] at movedTyped ⊢
          grind only []
        have outsideTypes := ValueInventory.temporary_preserves_all _ _ _ temporaryOk _ startingTyped
        have allocatedTypes := ValueInventory.allocateObject_preserves_all outside finalStore clause.resumption
          _ owner (signature.use != .multi) token allocated _ outsideTypes (by
            first | exact captureTyped | (split <;> exact captureTyped))
        have tokenTyped : ValueShape context.source.schemas token.value := by
          rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
          apply Profile.Value.Typed.reference shapeAt
          cases useMode : signature.use <;> simp [ReferenceOwnership, useMode]
        have stagedTypes := ValueInventory.finishTemporary_preserves_all _ _ _ stagedOk _ allocatedTypes tokenTyped
        have outgoingTyped : ∀ value ∈ (payload :: ((operands.drop operation.capability.toList.length).drop 1).take operation.bodies.length).mapIdx
            (fun index value => retainAt value (.receiver ⟨machine.heap.nextInvocation⟩ index)),
            ValueShape context.source.schemas value.value := by
          intro value member
          simp only [List.mapIdx_eq_zipIdx_map, List.mem_map] at member
          obtain ⟨⟨original, index⟩, member, rfl⟩ := member
          rcases List.mem_cons.mp (List.fst_mem_of_mem_zipIdx member) with equal | member
          · cases equal; exact payloadTyped
          · exact bodiesTyped original member
        simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.environment,
          List.map_append, List.mem_append, List.mem_map, List.mem_singleton] at stagedTypes ⊢
        grind only []

/-- Every successful effect-term transition preserves finite value typing.
The input assumptions concern only the predecessor state. -/
theorem executeEffectTerm_preserves_value_shapes (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  have outer : ∀ binding ∈ bindings, ValueShape context.source.schemas binding.located.value := by
    intro binding member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, ValueInventory.environment,
      List.mem_append, List.mem_map]
    grind only []
  have inputs : ∀ value ∈ operands, ValueShape context.source.schemas value.value := by
    intro value member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    grind only []
  cases term <;> simp only at accepted <;> try contradiction
  case perform operation => exact openRequest_preserves_value_shapes _ _ _ _ _ accepted typed inputs
  case handle handler body arguments stored =>
    split at accepted <;> try contradiction
    rename_i closure rest operandsEqual
    apply installHandler_preserves_value_shapes _ _ _ _ _ _ _ _ accepted typed
    · intro value member
      exact inputs value (by simp [List.mem_of_mem_take member])
    · intro value member
      exact inputs value (by simp [List.mem_of_mem_drop member])
    · exact outer
  case resumeValue token argument =>
    split at accepted <;> try contradiction
    rename_i tokenValue argumentValue operandsEqual
    exact resumeValue_preserves_value_shapes _ _ _ _ _ _ accepted typed
      (inputs argumentValue (by simp)) trivial
  case resumeWith token argument handler stored =>
    split at accepted <;> try contradiction
    rename_i tokenValue argumentValue rest operandsEqual
    apply resumeValue_preserves_value_shapes _ _ _ _ _ _ accepted typed (inputs argumentValue (by simp))
    exact ⟨fun value member => inputs value (by simp [member]), outer⟩
  case resumeComputation token computation =>
    split at accepted <;> try contradiction
    exact resumeComputation_preserves_value_shapes _ _ _ _ _ accepted typed
  case withRegion descriptor body arguments =>
    split at accepted <;> try contradiction
    rename_i closure rest operandsEqual
    exact enterRegion_preserves_value_shapes _ _ _ _ _ _ accepted typed
      (fun value member => inputs value (by simp [member]))

end BoundaryV2.Profile.Source.Machine
