import BoundaryV2.GeneralizedPackageExecution
import BoundaryV2.GeneralizedOwnedOperandExamples

namespace BoundaryV2.Generalized.Examples

def packageMovedFields : UseScope.State :=
  ⟨[.owned ⟨100⟩ (.lexical ⟨0⟩ 1)], creationSourceStore.fields.retained, [⟨17⟩]⟩

theorem packageValueHandoff : ValueHandoff createdSourceComputation.value createdSourceComputation.store.fields packageMovedFields :=
  .move (before := [.owned ⟨100⟩ (.lexical ⟨0⟩ 1)]) (after := [])

def createdOwnedPackage := createPackage createdSourceComputation.value (.lexical ⟨0⟩ 2)
  createdSourceComputation.store packageMovedFields packageValueHandoff creationCells.reservations.custody

def packageProgram : Source.Computation signature algebra []
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer] (.package OwnedApplicationType) := .package compoundOwnedFunction

theorem authored_closure_can_be_packaged_with_its_actual_owners :
    createdOwnedPackage.authority = ⟨302⟩ ∧
    UseScope.inventory createdOwnedPackage.store.fields = [⟨100⟩, ⟨302⟩, ⟨301⟩, ⟨6⟩] ∧
    Source.ExecutionStep (.nil : Source.Definitions signature algebra [])
      ⟨⟨creationSourceStore, .evaluate packageProgram lambdaBindings⟩, creationCells, [⟨1⟩]⟩
      ⟨⟨createdOwnedPackage.store, .returned createdOwnedPackage.value⟩, creationCells, [⟨1⟩]⟩ ∧
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨creationTargetStore, .code (Defunctionalization.computation packageProgram)
        (Defunctionalization.environment lambdaBindings) .nil .done⟩, Defunctionalization.cells creationCells, [⟨1⟩]⟩ count targetAfter ∧
      Defunctionalization.CellStateRelated
        ⟨⟨createdOwnedPackage.store, .returned createdOwnedPackage.value⟩, creationCells, [⟨1⟩]⟩ targetAfter := by
  have compiled := Defunctionalization.compiled_package (retained := []) (signature := signature) (algebra := algebra)
    .nil compoundOwnedFunction lambdaBindings createdSourceComputation.value (.lexical ⟨0⟩ 2) creationCells [⟨1⟩]
    (targetStore := creationTargetStore) compound_function_evaluates_with_its_grant packageMovedFields packageValueHandoff
    ⟨rfl, .nil, .nil⟩ .done
  exact ⟨rfl, rfl, compiled⟩

def unpackedPackageFields : UseScope.State :=
  ⟨[.owned ⟨100⟩ (.lexical ⟨0⟩ 1), createdSourceComputation.value.owningField],
    creationSourceStore.fields.retained, [⟨302⟩, ⟨17⟩]⟩

theorem ownedPackageHandoff : PackageHandoff createdSourceComputation.value createdOwnedPackage.authority
    (.lexical ⟨0⟩ 2) createdOwnedPackage.store.fields unpackedPackageFields :=
  .unpack [.owned ⟨100⟩ (.lexical ⟨0⟩ 1)] [] creationSourceStore.fields.retained [⟨17⟩]

def packagedBindings : Source.RuntimeEnvironment signature algebra [] [.package OwnedApplicationType] :=
  .cons createdOwnedPackage.value .nil

def createdPackageTargetStore : Target.ControlHeap signature algebra [] :=
  ⟨createdOwnedPackage.store.fields, [], []⟩

theorem unpacking_consumes_the_package_without_consuming_its_contents :
    Source.ExecutionStep (.nil : Source.Definitions signature algebra [])
      ⟨⟨createdOwnedPackage.store, .evaluate (.unpackage (.reference .here)) packagedBindings⟩, creationCells, [⟨1⟩]⟩
      ⟨⟨{ createdOwnedPackage.store with fields := unpackedPackageFields }, .returned createdSourceComputation.value⟩,
        creationCells, [⟨1⟩]⟩ ∧
    (∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨createdPackageTargetStore, .code (Defunctionalization.computation (.unpackage (.reference .here)))
        (Defunctionalization.environment packagedBindings) .nil .done⟩, Defunctionalization.cells creationCells, [⟨1⟩]⟩ count targetAfter) ∧
    UseScope.inventory unpackedPackageFields = [⟨100⟩, ⟨301⟩, ⟨6⟩] ∧
    unpackedPackageFields.spent = [⟨302⟩, ⟨17⟩] := by
  obtain ⟨sourceStep, count, targetAfter, positive, targetSteps, _⟩ := Defunctionalization.compiled_unpackage (retained := [])
    (signature := signature) (algebra := algebra) .nil (.reference .here) packagedBindings createdSourceComputation.value
    createdOwnedPackage.authority (.lexical ⟨0⟩ 2) creationCells [⟨1⟩] (targetStore := createdPackageTargetStore)
    .reference ownedPackageHandoff ⟨rfl, .nil, .nil⟩ .done
  exact ⟨sourceStep, ⟨count, targetAfter, positive, targetSteps⟩, rfl, rfl⟩

theorem unwrapped_package_view_cannot_be_used_again (later : UseScope.State) :
    ¬ PackageHandoff createdSourceComputation.value createdOwnedPackage.authority
      (.lexical ⟨0⟩ 2) unpackedPackageFields later :=
  ownedPackageHandoff.cannot_repeat
    (created_package_preserves_ownership createdSourceComputation.value creation_retains_one_owner_per_capture.1 packageValueHandoff).1

theorem package_creation_preserves_cell_owned_authority :
    (UseScope.inventory createdOwnedPackage.store.fields ++ UseScope.tokens creationCells.fields).Nodup :=
  created_package_preserves_external_owners createdSourceComputation.value packageValueHandoff
    (UseScope.tokens creationCells.fields) creation_retains_one_owner_per_capture.2
    (fun _ member => creationCells.owning_tokens_reserved member)

theorem unpacked_closure_still_has_its_entry_authority :
    ComputationHandoff applicationCaptures .linear (some (⟨301⟩, applicationOwner)) unpackedPackageFields
      ⟨creationSourceStore.fields.active, creationSourceStore.fields.retained, [⟨301⟩, ⟨302⟩, ⟨17⟩]⟩ :=
  ComputationHandoff.owned (captured := applicationCaptures) .linear ⟨301⟩ applicationOwner
    [.owned ⟨100⟩ (.lexical ⟨0⟩ 1)] [] creationSourceStore.fields.retained [⟨302⟩, ⟨17⟩]

theorem plain_values_need_no_fictitious_source_owner :
    ValueHandoff (.datum (.leaf (type := Data.integer) 42) : Source.RuntimeValue signature algebra [] (.leaf .integer))
      creationSourceStore.fields creationSourceStore.fields := .unowned rfl

end BoundaryV2.Generalized.Examples
