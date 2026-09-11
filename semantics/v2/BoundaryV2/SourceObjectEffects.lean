import BoundaryV2.SourceObjectStorage

namespace BoundaryV2.Profile.Source.Machine
namespace ObjectSchemas
namespace Preservation

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


theorem createScope_preserves (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located) (bindings : Environment)
    (after : State) (entered : Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered)) :
    Preserves (source := context.source) machine.heap.objects after.heap.objects := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact .refl _
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, moved, movedOk, equal⟩ := accepted
    have result := move_preserves (source := context.source) _ _ _ _ movedOk
    cases equal; exact result

theorem invokeFunction_preserves (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, ⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have result := createScope_preserves _ _ _ _ _ _ _ _ _ scopeOk
  exact result

theorem applyClosure_preserves (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  obtain ⟨⟨schema, token, reference⟩, _⟩ := CellStability.lookupObject_reference _ _ _ _ looked
  rw [reference] at accepted
  cases token with
  | none =>
    simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_preserves _ _ _ _ _ _ accepted
  | some token =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, retired, accepted⟩ := accepted
    have first := retire_noncell_preserves (source := context.source) _ _ _ _ _ looked rfl retired
    have second := invokeFunction_preserves _ _ _ _ _ _ accepted
    exact first.trans second

theorem enterInvocation_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) : Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_preserves _ _ _ _ _ _ accepted

theorem enterBinding_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) : Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have result := createScope_preserves _ _ _ _ _ _ _ _ _ scopeOk
  split <;> exact result

theorem enterPattern_preserves (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have result := createScope_preserves _ _ _ _ _ _ _ _ _ scopeOk
  split <;> exact result

theorem instantiateCapture_preserves (machine : State) (context : Context) (saved : Capture) (after : State × Capture)
    (accepted : instantiateCapture machine context saved = .ok after)
    (valid : FrozenContracts.Valid machine.heap saved) : Preserves (source := context.source) machine.heap.objects after.1.heap.objects := by
  intro heapValid
  exact ⟨ObjectSchemas.instantiate_valid machine after.1 context saved after.2 accepted heapValid.1 heapValid.2 valid,
    (FrozenContracts.instantiate_preserves_heap_and_frozen_contracts machine after.1 context saved after.2 accepted heapValid.2 valid).1⟩

theorem takeCapture_preserves (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture machine context token = .ok after) : Preserves (source := context.source) machine.heap.objects after.1.heap.objects := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨store, retired, rfl⟩ := accepted
    exact retire_noncell_preserves (source := context.source) _ _ _ _ _ looked rfl retired
  · intro heapValid
    have captureValid := FrozenContracts.heap_lookup _ _ _ (CellStability.lookupObject_reference _ _ _ _ looked).2 heapValid.2
    exact instantiateCapture_preserves _ _ _ _ accepted captureValid heapValid

theorem activateCapture_preserves (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture machine context saved successor = .ok after) : Preserves (source := context.source) machine.heap.objects after.heap.objects := by
  simp only [activateCapture, bind, except_bind_ok, pure, Except.pure] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none => cases accepted; exact .refl _
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    exact .refl _

theorem resumeValue_preserves (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  simp only [resumeValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have first := takeCapture_preserves _ _ _ _ captured
  have second := activateCapture_preserves _ _ _ _ _ activated
  have third := temporary_preserves (source := context.source) _ _ _ temporaryOk
  have fourth := move_preserves (source := context.source) _ _ _ _ moved
  have fifth := finishTemporary_preserves (source := context.source) _ _ _ finished
  exact first.trans (second.trans (third.trans (fourth.trans fifth)))

theorem resumeComputation_preserves (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  have first := takeCapture_preserves _ _ _ _ captured
  have second := activateCapture_preserves _ _ _ _ _ activated
  have third := applyClosure_preserves _ _ _ _ _ applied
  exact first.trans (second.trans third)

private theorem foldlM_preserves (items : List β) (step : α → β → Except Invalid α)
    (property : α → Prop) (preserved : ∀ before item after, step before item = .ok after → property before → property after)
    (before after : α) (accepted : items.foldlM step before = .ok after) (holds : property before) : property after := by
  induction items generalizing before with
  | nil => cases accepted; exact holds
  | cons first rest induction =>
    simp only [List.foldlM_cons, bind, except_bind_ok] at accepted
    obtain ⟨middle, stepped, accepted⟩ := accepted
    exact induction middle accepted (preserved before first middle stepped holds)

theorem installHandler_preserves (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  let property (pair : Heap × List Located) : Prop := Preserves (source := context.source) machine.heap.objects pair.1.objects
  have seed : property ({ machine.heap with nextAttachment := machine.heap.nextAttachment + 1 }, []) := .refl _
  have allPreserved := foldlM_preserves _ _ property (by
    intro before item after stepOk beforePreserved
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at stepOk
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := stepOk
    exact beforePreserved.trans (allocate_preserves (source := context.source) _ _ _ _ _ _ _ allocated (by simp only [ObjectSchemas.ObjectValid, FrozenContracts.ObjectValid]; grind only [→ require_ok, retainAt]))) _ _ allocated seed
  exact allPreserved.trans (applyClosure_preserves _ _ _ _ _ applied)

theorem enterRegion_preserves (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, ⟨store, value⟩, allocated, applied⟩ := accepted
  have first := allocate_preserves (source := context.source) _ _ _ _ _ _ _ allocated (by simp only [ObjectSchemas.ObjectValid, FrozenContracts.ObjectValid]; grind only [→ require_ok, retainAt])
  have second := applyClosure_preserves _ _ _ _ _ applied
  exact first.trans second

theorem openRequest_preserves (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition) (accepted : openRequest machine context operation operands = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  simp only [openRequest, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact .refl _
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
    split at accepted
    · simp only [except_bind_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_preserves _ _ _ _ _ _ invoked
    · simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have first := move_preserves (source := context.source) _ store _ _ ((fromOption_ok _ _ _).mp moved)
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, temporaryOk, ⟨allocatedHeap, token⟩, allocated, staged, stagedOk, invoked⟩ := accepted
        have second := temporary_preserves (source := context.source) _ _ _ temporaryOk
        have stable := CellStability.temporary_preserves _ _ _ temporaryOk
        have third := allocate_preserves (source := context.source) _ _ _ _ _ _ _ allocated (by
          constructor
          · simp only [ObjectSchemas.ObjectValid]
            grind only [→ require_ok, fromOption_ok]
          · intro saved member
            have snapshot := FrozenContracts.snapshot_valid store _ saved member
            exact ⟨FrozenContracts.cell_stability_preserves _ _ _ stable snapshot.1, snapshot.2⟩)
        have fourth := finishTemporary_preserves (source := context.source) _ _ _ stagedOk
        exact first.trans (second.trans (third.trans (fourth.trans (invokeFunction_preserves _ _ _ _ _ _ invoked))))

theorem installProtection_preserves (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  have first := move_preserves (source := context.source) _ _ _ _ moved
  cases resource <;> cases loan <;> try contradiction
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact first.trans (applyClosure_preserves _ _ _ _ _ accepted)
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, ⟨allocatedHeap, value⟩, allocated, _, rfl, applied⟩ := accepted
    have second := allocate_preserves (source := context.source) _ _ _ _ _ _ _ allocated (by simp only [ObjectSchemas.ObjectValid, FrozenContracts.ObjectValid]; grind only [→ require_ok, retainAt])
    have third := applyClosure_preserves _ _ _ _ _ applied
    exact first.trans (second.trans third)

theorem beginCleanup_preserves (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  simp only [beginCleanup, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, applied, rfl⟩ := accepted
  have result := applyClosure_preserves _ _ _ _ _ applied
  exact result

theorem resumeRelease_preserves (machine : State) (after : AfterRelease) :
    Preserves (source := source) machine.heap.objects (resumeRelease machine after).state.heap.objects := by
  cases after <;> exact .refl _

theorem finishCleanup_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) : Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, next, _, rfl⟩ := accepted
  cases next <;> exact .refl _

theorem discardValues_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) : Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  split at accepted
  · cases accepted; exact resumeRelease_preserves (source := context.source) _ _
  · split at accepted
    · cases accepted; exact .refl _
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
      cases stored <;> try contradiction
      all_goals simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      all_goals obtain ⟨store, retired, rfl⟩ := accepted
      all_goals exact retire_noncell_preserves (source := context.source) _ _ _ _ _ looked rfl retired

theorem leaveScope_preserves (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after) :
    Preserves (source := source) machine.heap.objects after.state.heap.objects := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, moved, finished, finishedOk, rfl⟩ := accepted
  have first := temporary_preserves (source := source) _ _ _ temporaryOk
  have second := move_preserves (source := source) _ _ _ _ moved
  have third := finishTemporary_preserves (source := source) _ _ _ finishedOk
  exact first.trans (second.trans third)

theorem restoreResumeCaller_preserves (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) : Preserves (source := source) machine.heap.objects after.state.heap.objects := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have first := temporary_preserves (source := source) _ _ _ temporaryOk
  have second := move_preserves (source := source) _ _ _ _ moved
  have third := finishTemporary_preserves (source := source) _ _ _ finished
  exact first.trans (second.trans third)


end Preservation
end ObjectSchemas
end BoundaryV2.Profile.Source.Machine
