import BoundaryV2.GeneralizedInjectionExamples
import BoundaryV2.GeneralizedComputationCreationExamples

namespace BoundaryV2.Generalized.Examples

def authoredInjectionBindings : Source.RuntimeEnvironment signature algebra [] (InjectionControl :: InjectionCaptures) :=
  .cons (.continuation injectionView.identity (some (injectionView.authority, injectionView.owner))) injectionCaptures

def authoredInjectionCaptures : Selection (Index := TypeOf signature)
    (InjectionControl :: InjectionCaptures) InjectionCaptures :=
  .cons (.there .here) (.cons (.there (.there .here)) (.cons (.there (.there (.there .here))) .nil))

def authoredInjectedLambda : Source.Expression signature algebra [] (InjectionControl :: InjectionCaptures) InjectionBody :=
  .lambda authoredInjectionCaptures injectedBody

def authoredInjection : Source.Computation signature algebra [] (InjectionControl :: InjectionCaptures) (.leaf .boolean) :=
  .inject (.reference .here) authoredInjectedLambda

def authoredInjectionSourceStore : Source.ControlHeap signature algebra [] :=
  { injectionSourceStore with fields :=
    ⟨[.owned ⟨1⟩ injectionOwner] ++ injectionCaptures.owningFields, [.continuation ⟨0⟩ []], []⟩ }

def authoredInjectionTargetStore : Target.ControlHeap signature algebra [] :=
  { injectionTargetStore with fields := authoredInjectionSourceStore.fields }

def allocatedInjection := createOwnedComputation (parameters := []) .linear injectedBody injectionCaptures injectionOwner
  [.owned ⟨1⟩ injectionOwner] [] authoredInjectionSourceStore rfl creationCells.reservations.custody

def allocatedInjectionFields : UseScope.State :=
  { authoredInjectionSourceStore.fields with spent := [allocatedInjection.authority] }

def allocatedInjectionSourceAfter : Source.ControlState signature algebra [] (.leaf .boolean) :=
  ⟨⟨⟨[.owned ⟨6⟩ injectionOwner], [], [⟨1⟩, allocatedInjection.authority]⟩, [], []⟩,
    injectionSourceOutside.plug (Source.reenter injectionSourceSaved (.evaluate injectedBody injectionCaptures))⟩

theorem authored_injection_stores_correspond :
    Defunctionalization.ControlHeapRelated authoredInjectionSourceStore authoredInjectionTargetStore :=
  ⟨rfl, injection_stores_are_related.controls, injection_stores_are_related.disposing⟩

theorem authored_injection_allocates_its_operand :
    Source.ArgumentsEvaluation authoredInjectionBindings creationCells.reservations.custody authoredInjectionSourceStore
      authoredInjection.operandPrefix.arguments
      (.ok (.cons (.continuation injectionView.identity (some (injectionView.authority, injectionView.owner)))
        (.cons allocatedInjection.value .nil))) allocatedInjection.store := by
  apply Source.ArgumentsEvaluation.cons .reference
  apply Source.ArgumentsEvaluation.cons
  · apply Source.ExpressionEvaluation.closure
    exact Source.ClosureEvaluation.owned (bindings := authoredInjectionBindings)
      (reserved := creationCells.reservations.custody) (parameters := []) .linear authoredInjectionCaptures
      injectedBody injectionOwner [.owned ⟨1⟩ injectionOwner] [] authoredInjectionSourceStore rfl
  · exact .nil

theorem allocated_injection_handoff :
    ComputationHandoff injectionCaptures .linear (some (allocatedInjection.authority, injectionOwner))
      allocatedInjection.store.fields allocatedInjectionFields := by
  simpa only [allocatedInjection, allocatedInjectionFields, authoredInjectionSourceStore,
    UseScope.OneShotUse.type, List.append_nil] using
    (created_computation_can_enter (use := .linear) (parameters := []) (body := injectedBody)
      (captured := injectionCaptures) (owner := injectionOwner) (before := [.owned ⟨1⟩ injectionOwner])
      (after := []) (store := authoredInjectionSourceStore) (reserved := creationCells.reservations.custody) rfl)

theorem allocated_injection_source_accepts :
    Source.injectControl injectionShape injectionView { allocatedInjection.store with fields := allocatedInjectionFields }
      injectedBody injectionCaptures injectionSourceOutside = some allocatedInjectionSourceAfter := by
  simp [Source.injectControl, UseScope.acquireAt, UseScope.acquire, allocatedInjection, createOwnedComputation,
    allocatedInjectionFields, authoredInjectionSourceStore, injectionSourceStore, injectionView, injectionOwner,
    UseScope.takeControl, UseScope.takeGrant, UseScope.takeCapture, UseScope.activeFields, UseScope.exposeField,
    injectionCaptures, Environment.owningFields, Value.owningField, Datum.owningField, ownedCellSourceValue,
    UseScope.unpack_control_exact, allocatedInjectionSourceAfter]

/-- The body is authored as a lambda here. Its grant is allocated after reading
the continuation, avoids a cell-owned resource, and is consumed before entry. -/
theorem authored_injection_consumes_both_grants_after_operand_allocation :
    allocatedInjection.authority = ⟨301⟩ ∧
    ∃ targetAfter count, 0 < count ∧
      Source.ExecutionStep (.nil : Source.Definitions signature algebra [])
        ⟨⟨authoredInjectionSourceStore, injectionSourceOutside.plug (.evaluate authoredInjection authoredInjectionBindings)⟩,
          creationCells, [⟨0⟩, ⟨1⟩]⟩ ⟨allocatedInjectionSourceAfter, creationCells, [⟨0⟩, ⟨1⟩]⟩ ∧
      Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
        ⟨⟨authoredInjectionTargetStore, .code (Defunctionalization.computation authoredInjection)
          (Defunctionalization.environment authoredInjectionBindings) .nil injectionTargetOutside⟩,
          Defunctionalization.cells creationCells, [⟨0⟩, ⟨1⟩]⟩ count
        ⟨targetAfter, Defunctionalization.cells creationCells, [⟨0⟩, ⟨1⟩]⟩ ∧
      Defunctionalization.ControlStateRelated allocatedInjectionSourceAfter targetAfter ∧
      targetAfter.store.fields.spent = [⟨1⟩, ⟨301⟩] ∧
      UseScope.inventory targetAfter.store.fields = [⟨6⟩] := by
  obtain ⟨targetAfter, count, positive, related, sourceStep, targetSteps⟩ :=
    Defunctionalization.compiled_computation_injection (retained := []) (signature := signature) (algebra := algebra)
      .nil .linear (.reference .here) authoredInjectedLambda authoredInjectionBindings injectedBody injectionCaptures
      (some (allocatedInjection.authority, injectionOwner)) injectionView creationCells [⟨0⟩, ⟨1⟩]
      authored_injection_allocates_its_operand authored_injection_stores_correspond allocated_injection_handoff
      injection_outsides_are_related allocated_injection_source_accepts
  refine ⟨rfl, targetAfter, count, positive, sourceStep, targetSteps, related.control, ?_, ?_⟩
  · rw [← related.control.store.fields]; rfl
  · rw [← related.control.store.fields]; rfl

end BoundaryV2.Generalized.Examples
