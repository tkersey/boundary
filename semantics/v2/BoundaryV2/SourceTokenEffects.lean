import BoundaryV2.SourceTokenStorage

namespace BoundaryV2.Profile.Source.Machine
namespace TokenInventory

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

theorem enterRegion_preserves_token_bounds (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine)
    (inputs : ∀ value ∈ arguments, ValueTokensBounded limit value.value) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, signature, _, schema, _, _, schemaOk, ⟨store, value⟩, allocated, applied⟩ := accepted
  have shape : context.source.schemas[schema.value]? = some (.internal (.region descriptor)) := by
    simpa using require_ok _ _ _ schemaOk
  have allocatedTyped := ValueInventory.allocateObject_preserves_all
    { machine with heap := { machine.heap with nextRegion := machine.heap.nextRegion + 1 } }
    store schema _ _ false value allocated _ typed (by simp [ValueInventory.object])
  have valueTyped : ValueTokensBounded limit value.value := by
    rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
    simp [ValueTokensBounded, ownedTokens]
  have frameTyped : ValueInventory.All (ValueTokensBounded limit)
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

theorem installHandler_preserves_token_bounds (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine)
    (inputs : ∀ value ∈ arguments, ValueTokensBounded limit value.value)
    (storedTyped : ∀ value ∈ stored, ValueTokensBounded limit value.value)
    (outer : ∀ binding ∈ bindings, ValueTokensBounded limit binding.located.value) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  let property (pair : Heap × List Located) : Prop :=
    ValueInventory.All (ValueTokensBounded limit) { machine with heap := pair.1 } ∧
    ∀ value ∈ pair.2, ValueTokensBounded limit value.value
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
    have valueTyped : ValueTokensBounded limit value.value := by
      rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
      simp [ValueTokensBounded, ownedTokens]
    refine ⟨heapTyped, ?_⟩
    intro child member
    rcases List.mem_append.mp member with member | member
    · exact beforeTyped.2 child member
    · cases List.mem_singleton.mp member; exact valueTyped) _ _ allocated seedTyped
  have selectedTyped : ∀ value ∈ ValueInventory.environment (handlerEnvironment context definition bindings),
      ValueTokensBounded limit value := by
    intro value member
    have originalMember := ValueInventory.handler_environment_subset context definition bindings member
    obtain ⟨binding, bindingMember, rfl⟩ := List.mem_map.mp originalMember
    exact outer binding bindingMember
  have framedTyped : ValueInventory.All (ValueTokensBounded limit)
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

theorem takeCapture_preserves_token_bounds (machine : State) (context : Context) (token : Located)
    (after : State × Capture) (accepted : takeCapture machine context token = .ok after)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine) :
    ValueInventory.All (ValueTokensBounded limit) after.1 ∧
    (∀ value ∈ ValueInventory.capture after.2, ValueTokensBounded limit value) := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, lookup, accepted⟩ := accepted
  have storedTyped := ValueInventory.lookupObject_preserves_all machine token node stored lookup _ typed
  cases stored <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨store, retired, rfl⟩ := accepted
    exact ⟨ValueInventory.retireObject_preserves_all machine token store retired _ typed, storedTyped⟩
  · exact instantiate_preserves _ _ _ _ _ accepted typed storedTyped

theorem resumeValue_preserves_token_bounds (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine)
    (argumentTyped : ValueTokensBounded limit argument.value)
    (successorTyped : match successor with
      | none => True
      | some (_, stored, bindings) => (∀ value ∈ stored, ValueTokensBounded limit value.value) ∧
          (∀ binding ∈ bindings, ValueTokensBounded limit binding.located.value)) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, shape, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have capturedTyped := takeCapture_preserves_token_bounds _ _ _ _ captured typed
  have activeTyped := activateCapture_preserves_all _ _ _ _ _ activated _ capturedTyped.1 capturedTyped.2 (by cases successor <;> exact successorTyped)
  exact ValueInventory.finishTemporary_preserves_all _ _ _ finished _
    (ValueInventory.moveValues_preserves_all _ _ _ _ moved _
      (ValueInventory.temporary_preserves_all _ _ _ temporaryOk _ activeTyped)) argumentTyped

theorem resumeComputation_preserves_token_bounds (machine : State) (context : Context)
    (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  have capturedTyped := takeCapture_preserves_token_bounds _ _ _ _ captured typed
  have activeTyped := activateCapture_preserves_all _ _ _ _ _ activated _ capturedTyped.1 capturedTyped.2 trivial
  apply ValueInventory.applyClosure_preserves_all _ _ _ _ _ applied _ activeTyped
  intro value member
  apply capturedTyped.2
  simp only [ValueInventory.capture, List.mem_append, List.mem_map]
  exact Or.inl (Or.inr ⟨value, member, rfl⟩)

theorem openRequest_preserves_token_bounds (machine : State) (context : Context)
    (operation : Operation) (operands : List Located) (after : Transition)
    (accepted : openRequest machine context operation operands = .ok after)
    (upper : after.state.heap.nextCustody ≤ limit)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine)
    (inputs : ∀ value ∈ operands, ValueTokensBounded limit value.value) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨effect, _, _, _, payload, payloadAt, _, _, accepted⟩ := accepted
  have payloadTyped := inputs payload (List.mem_of_mem_drop (List.mem_of_head? payloadAt))
  have bodiesTyped : ∀ value ∈ ((operands.drop operation.capability.toList.length).drop 1).take operation.bodies.length,
      ValueTokensBounded limit value.value := by
    intro value member
    exact inputs value (List.mem_of_mem_drop (List.mem_of_mem_drop (List.mem_of_mem_take member)))
  have capsTyped : ∀ value ∈ (operands.drop operation.capability.toList.length).drop (1 + operation.bodies.length),
      ValueTokensBounded limit value.value := by
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
    have activationTyped : ∀ value ∈ ValueInventory.activation selected.activation, ValueTokensBounded limit value := by
      intro value member
      apply typed
      simp [ValueInventory.state, reconstructed, ValueInventory.frame, member]
    have outer : ∀ binding ∈ selected.activation.environment, ValueTokensBounded limit binding.located.value := by
      intro binding member
      apply activationTyped
      simp only [ValueInventory.activation, ValueInventory.environment, List.mem_append, List.mem_map]
      exact Or.inl ⟨binding, member, rfl⟩
    have storedTyped : ∀ value ∈ selected.activation.state, ValueTokensBounded limit value.value := by
      intro value member
      apply activationTyped
      simp only [ValueInventory.activation, List.mem_append, List.mem_map]
      exact Or.inr ⟨value, member, rfl⟩
    have outsideTyped : ∀ value ∈ selected.outside.flatMap ValueInventory.frame, ValueTokensBounded limit value := by
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
            ValueTokensBounded limit value := by
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
            ValueTokensBounded limit value := by
          simp only [ValueInventory.capture, List.mem_append, List.mem_map]
          grind only []
        have startingTyped : ValueInventory.All (ValueTokensBounded limit)
            { machine with heap := store, stack := selected.outside, scope := selected.activation.scope, invocation := selected.activation.invocation } := by
          simp only [ValueInventory.All, ValueInventory.state, List.mem_append] at movedTyped ⊢
          grind only []
        have outsideTypes := ValueInventory.temporary_preserves_all _ _ _ temporaryOk _ startingTyped
        have allocatedTypes := ValueInventory.allocateObject_preserves_all outside finalStore clause.resumption
          _ owner (signature.use != .multi) token allocated _ outsideTypes (by
            first | exact captureTyped | (split <;> exact captureTyped))
        have tokenTyped := allocation_result _ _ _ _ _ _ _ allocated
          (Nat.le_trans (finishTemporary_allocation _ _ _ stagedOk).heap.custody upper)
        have stagedTypes := ValueInventory.finishTemporary_preserves_all _ _ _ stagedOk _ allocatedTypes tokenTyped
        have outgoingTyped : ∀ value ∈ (payload :: ((operands.drop operation.capability.toList.length).drop 1).take operation.bodies.length).mapIdx
            (fun index value => retainAt value (.receiver ⟨machine.heap.nextInvocation⟩ index)),
            ValueTokensBounded limit value.value := by
          intro value member
          simp only [List.mapIdx_eq_zipIdx_map, List.mem_map] at member
          obtain ⟨⟨original, index⟩, member, rfl⟩ := member
          rcases List.mem_cons.mp (List.fst_mem_of_mem_zipIdx member) with equal | member
          · cases equal; exact payloadTyped
          · exact bodiesTyped original member
        simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.environment,
          List.map_append, List.mem_append, List.mem_map, List.mem_singleton] at stagedTypes ⊢
        grind only []

/-- Every successful effect-term transition preserves bounds on retained custody tokens.
The token limit bounds the returned allocation supply. -/
theorem executeEffectTerm_preserves_token_bounds (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after)
    (upper : after.state.heap.nextCustody ≤ limit)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  have outer : ∀ binding ∈ bindings, ValueTokensBounded limit binding.located.value := by
    intro binding member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, ValueInventory.environment,
      List.mem_append, List.mem_map]
    grind only []
  have inputs : ∀ value ∈ operands, ValueTokensBounded limit value.value := by
    intro value member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    grind only []
  cases term <;> simp only at accepted <;> try contradiction
  case perform operation => exact openRequest_preserves_token_bounds _ _ _ _ _ accepted upper typed inputs
  case handle handler body arguments stored =>
    split at accepted <;> try contradiction
    rename_i closure rest operandsEqual
    apply installHandler_preserves_token_bounds _ _ _ _ _ _ _ _ accepted typed
    · intro value member
      exact inputs value (by simp [List.mem_of_mem_take member])
    · intro value member
      exact inputs value (by simp [List.mem_of_mem_drop member])
    · exact outer
  case resumeValue token argument =>
    split at accepted <;> try contradiction
    rename_i tokenValue argumentValue operandsEqual
    exact resumeValue_preserves_token_bounds _ _ _ _ _ _ accepted typed
      (inputs argumentValue (by simp)) trivial
  case resumeWith token argument handler stored =>
    split at accepted <;> try contradiction
    rename_i tokenValue argumentValue rest operandsEqual
    apply resumeValue_preserves_token_bounds _ _ _ _ _ _ accepted typed (inputs argumentValue (by simp))
    exact ⟨fun value member => inputs value (by simp [member]), outer⟩
  case resumeComputation token computation =>
    split at accepted <;> try contradiction
    exact resumeComputation_preserves_token_bounds _ _ _ _ _ accepted typed
  case withRegion descriptor body arguments =>
    split at accepted <;> try contradiction
    rename_i closure rest operandsEqual
    exact enterRegion_preserves_token_bounds _ _ _ _ _ _ accepted typed
      (fun value member => inputs value (by simp [member]))

end TokenInventory
end BoundaryV2.Profile.Source.Machine
