import BoundaryV2.GeneralizedComputationCreation
import BoundaryV2.GeneralizedApplicationExamples

namespace BoundaryV2.Generalized.Examples

def creationSourceStore : Source.ControlHeap signature algebra [] :=
  ⟨⟨[.owned ⟨100⟩ (.lexical ⟨0⟩ 1), ownedCellSourceValue.owningField],
    [.package [.closure [.alias ⟨200⟩]]], [⟨17⟩]⟩, [], []⟩

def creationTargetStore : Target.ControlHeap signature algebra [] :=
  ⟨creationSourceStore.fields, [], []⟩

def creationCells : Cells signature algebra (Source.Computation signature algebra []) :=
  [⟨⟨3⟩, ⟨1⟩, .resource ⟨0⟩, .datum (.resource ⟨7⟩ ⟨300⟩ (.lexical ⟨1⟩ 0))⟩]

def createdSourceComputation := createOwnedComputation (parameters := [.leaf Data.boolean])
  .linear applicationBody applicationCaptures applicationOwner
  [.owned ⟨100⟩ (.lexical ⟨0⟩ 1)] [] creationSourceStore rfl creationCells.reservations.custody

def createdTargetComputation := createOwnedComputation (parameters := [.leaf Data.boolean]) .linear
  (Defunctionalization.computation applicationBody) (Defunctionalization.environment applicationCaptures) applicationOwner
  [.owned ⟨100⟩ (.lexical ⟨0⟩ 1)] [] creationTargetStore rfl
  (Defunctionalization.cells creationCells).reservations.custody

def createdApplicationBindings : Source.RuntimeEnvironment signature algebra [] [OwnedApplicationType] :=
  .cons createdSourceComputation.value .nil

def createdApplicationFields : UseScope.State :=
  ⟨creationSourceStore.fields.active, creationSourceStore.fields.retained,
    createdSourceComputation.authority :: creationSourceStore.fields.spent⟩

theorem creation_store_is_valid : UseScope.ControlStore.Valid creationSourceStore := by
  simp [UseScope.ControlStore.Valid, UseScope.Valid, UseScope.inventory, creationSourceStore,
    ownedCellSourceValue, Value.owningField, Datum.owningField, UseScope.tokens, UseScope.Field.tokens]

theorem construction_reserves_dormant_aliases_and_cells :
    createdSourceComputation.authority = ⟨301⟩ ∧
    createdTargetComputation.authority = createdSourceComputation.authority ∧
    createdTargetComputation.value = Defunctionalization.value createdSourceComputation.value := ⟨rfl, rfl, rfl⟩

theorem creation_retains_one_owner_per_capture :
    UseScope.ControlStore.Valid createdSourceComputation.store ∧
    (UseScope.inventory createdSourceComputation.store.fields ++ UseScope.tokens creationCells.fields).Nodup := by
  refine ⟨created_computation_preserves_ownership creation_store_is_valid rfl, ?_⟩
  apply created_computation_preserves_combined_inventory rfl (UseScope.tokens creationCells.fields)
  · simp [UseScope.inventory, creationSourceStore, creationCells, Cells.fields,
      ownedCellSourceValue, Value.owningField, Datum.owningField, UseScope.tokens, UseScope.Field.tokens]
  · exact fun token member => creationCells.owning_tokens_reserved member

theorem created_application_handoff :
    ComputationHandoff applicationCaptures .linear (some (createdSourceComputation.authority, applicationOwner))
      createdSourceComputation.store.fields createdApplicationFields := by
  simpa only [createdSourceComputation, createdApplicationFields, creationSourceStore,
    applicationCaptures, Environment.owningFields, List.append_nil, List.cons_append,
    List.nil_append, UseScope.OneShotUse.type] using
    (created_computation_can_enter (use := .linear) (parameters := [.leaf Data.boolean])
    (body := applicationBody) (captured := applicationCaptures) (owner := applicationOwner)
    (before := [.owned ⟨100⟩ (.lexical ⟨0⟩ 1)]) (after := []) (store := creationSourceStore)
    (reserved := creationCells.reservations.custody) rfl)

/-- The callable value and its authority come from the construction, rather
than a manually supplied token. The core compiler enters the captured body. -/
theorem created_closure_has_corresponding_application :
    ∃ count, 0 < count ∧ Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨createdTargetComputation.store,
        .code (Defunctionalization.computation (.apply (.reference .here) applicationArguments))
          (Defunctionalization.environment createdApplicationBindings) .nil .done⟩,
        Defunctionalization.cells creationCells, [⟨1⟩]⟩ count
      ⟨⟨{ createdTargetComputation.store with fields := createdApplicationFields },
        .code (Defunctionalization.computation applicationBody)
          (Defunctionalization.environment (.cons (.datum (.leaf false)) applicationCaptures)) .nil
          (.push (.returnTo .ret (Defunctionalization.environment createdApplicationBindings) .nil) .done)⟩,
        Defunctionalization.cells creationCells, [⟨1⟩]⟩ := by
  obtain ⟨_, count, positive, steps, _⟩ := Defunctionalization.compiled_owned_operand_application (retained := [])
    (signature := signature) (algebra := algebra) .nil (.reference .here) applicationArguments createdApplicationBindings
    applicationBody applicationCaptures (.cons (.datum (.leaf false)) .nil)
    (some (createdSourceComputation.authority, applicationOwner)) creationCells [⟨1⟩]
    (sourceStore := createdSourceComputation.store) (sourceEvaluated := createdSourceComputation.store)
    (targetStore := createdTargetComputation.store)
    (.cons .reference (.cons .datum .nil)) created_application_handoff ⟨rfl, .nil, .nil⟩ .done
  exact ⟨count, positive, steps⟩

theorem created_closure_application_preserves_existing_owners :
    UseScope.inventory createdApplicationFields = [⟨100⟩, ⟨6⟩] ∧
    UseScope.tokens creationCells.fields = [⟨300⟩] ∧
    createdApplicationFields.retained = [.package [.closure [.alias ⟨200⟩]]] ∧
    createdApplicationFields.spent = [⟨301⟩, ⟨17⟩] := ⟨rfl, rfl, rfl, rfl⟩

theorem created_closure_cannot_enter_again (later : UseScope.State) :
    ¬ ComputationHandoff applicationCaptures .linear (some (createdSourceComputation.authority, applicationOwner))
      createdApplicationFields later :=
  created_application_handoff.owned_entry_cannot_repeat creation_retains_one_owner_per_capture.1.1

def duplicatedCreationCaptures : Source.RuntimeEnvironment signature algebra [] [.resource ⟨0⟩, .resource ⟨0⟩] :=
  .cons ownedCellSourceValue (.cons ownedCellSourceValue .nil)

def duplicatedCreationBody : Source.Computation signature algebra [] [.resource ⟨0⟩, .resource ⟨0⟩] .unit :=
  .returnValue (.datum .unit)

def duplicatedCreationStore : Source.ControlHeap signature algebra [] :=
  ⟨⟨duplicatedCreationCaptures.owningFields, [], []⟩, [], []⟩

theorem sealing_duplicate_captures_cannot_establish_ownership :
    ¬ UseScope.ControlStore.Valid
      (createOwnedComputation (parameters := []) .affine duplicatedCreationBody duplicatedCreationCaptures
        applicationOwner [] [] duplicatedCreationStore rfl []).store := by
  simp [createOwnedComputation, authorityFields, UseScope.ControlStore.Valid, UseScope.Valid,
    UseScope.inventory, duplicatedCreationStore,
    duplicatedCreationCaptures, ownedCellSourceValue, Environment.owningFields, Value.owningField,
    Datum.owningField, UseScope.tokens, UseScope.Field.tokens]

end BoundaryV2.Generalized.Examples
