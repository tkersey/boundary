import BoundaryV2.GeneralizedApplicationExecution
import BoundaryV2.GeneralizedCellExecutionExamples

namespace BoundaryV2.Generalized.Examples

abbrev OwnedApplicationType : TypeOf signature := .computation .linear [.leaf .boolean] (.leaf .boolean)

def applicationBody : Source.Computation signature algebra [] [.leaf .boolean, .resource ⟨0⟩] (.leaf .boolean) :=
  .yieldThen (.returnValue (.reference .here))

def applicationCaptures : Source.RuntimeEnvironment signature algebra [] [.resource ⟨0⟩] :=
  .cons ownedCellSourceValue .nil

def applicationOwner : Owner := .lexical ⟨0⟩ 0

def ownedApplication : Source.RuntimeValue signature algebra [] OwnedApplicationType :=
  .closure applicationBody applicationCaptures (some (⟨8⟩, applicationOwner))

def applicationBindings : Source.RuntimeEnvironment signature algebra [] [OwnedApplicationType] := .cons ownedApplication .nil

def applicationArguments : Source.Arguments signature algebra [] [OwnedApplicationType] [.leaf .boolean] :=
  .cons (.datum (.leaf false)) .nil

def applicationSourceStore : Source.ControlHeap signature algebra [] :=
  ⟨⟨[.owned ⟨100⟩ (.lexical ⟨0⟩ 1), ownedApplication.owningField], [], []⟩, [], []⟩

def applicationTargetStore : Target.ControlHeap signature algebra [] := ⟨applicationSourceStore.fields, [], []⟩

def applicationFieldsAfter : UseScope.State :=
  ⟨[.owned ⟨100⟩ (.lexical ⟨0⟩ 1), .owned ⟨6⟩ applicationOwner], [], [⟨8⟩]⟩

theorem application_handoff : ComputationHandoff applicationCaptures .linear (some (⟨8⟩, applicationOwner))
    applicationSourceStore.fields applicationFieldsAfter :=
  .owned .linear ⟨8⟩ applicationOwner [.owned ⟨100⟩ (.lexical ⟨0⟩ 1)] [] [] []

theorem owned_application_has_corresponding_stateful_execution :
    ∃ count, 0 < count ∧ Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨applicationTargetStore, .code (Defunctionalization.computation (.apply (.reference .here) applicationArguments))
        (Defunctionalization.environment applicationBindings) .nil .done⟩, [], []⟩ count
      ⟨⟨{ applicationTargetStore with fields := applicationFieldsAfter },
        .code (Defunctionalization.computation applicationBody)
          (Defunctionalization.environment (.cons (.datum (.leaf false)) applicationCaptures)) .nil
          (.push (.returnTo .ret (Defunctionalization.environment applicationBindings) .nil) .done)⟩, [], []⟩ := by
  obtain ⟨_, count, positive, steps, _⟩ := Defunctionalization.compiled_computation_application
    (signature := signature) (algebra := algebra) .nil (.reference .here) applicationArguments applicationBindings
    applicationBody applicationCaptures (.cons (.datum (.leaf false)) .nil) (some (⟨8⟩, applicationOwner)) rfl rfl
    (sourceStore := applicationSourceStore) (targetStore := applicationTargetStore) ⟨rfl, .nil, .nil⟩ application_handoff .done [] []
  exact ⟨count, positive, steps⟩

theorem application_spends_its_grant_and_preserves_other_owners :
    UseScope.inventory applicationFieldsAfter = [⟨100⟩, ⟨6⟩] ∧ applicationFieldsAfter.spent = [⟨8⟩] := ⟨rfl, rfl⟩

theorem ready_source_application_cannot_use_the_ordinary_path :
    (Source.Program.evaluate (.apply (.reference .here) applicationArguments) applicationBindings).needsComputationEntry = true := rfl

theorem ready_target_application_cannot_use_the_ordinary_path :
    (Target.Configuration.code (.callClosure (use := .linear) (parameters := [.leaf Data.boolean]) .ret)
      (Defunctionalization.environment applicationBindings)
      (.cons (.datum (.leaf false)) (.cons (Defunctionalization.value ownedApplication) .nil))
      (.done : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .boolean))).needsComputationEntry = true := rfl

theorem application_cannot_reuse_a_consumed_grant (later : UseScope.State) :
    ¬ ComputationHandoff applicationCaptures .linear (some (⟨8⟩, applicationOwner)) applicationFieldsAfter later := by
  apply application_handoff.owned_entry_cannot_repeat
  simp [UseScope.Valid, UseScope.inventory, applicationSourceStore, ownedApplication, applicationCaptures,
    Value.owningField, Environment.owningFields, authorityFields, Datum.owningField, ownedCellSourceValue,
    UseScope.tokens, UseScope.Field.tokens]

def sharedApplicationCaptures : Source.RuntimeEnvironment signature algebra [] [.leaf .boolean] := .cons (.datum (.leaf true)) .nil

theorem shared_application_remains_admissible :
    ComputationHandoff sharedApplicationCaptures .reusable none applicationFieldsAfter applicationFieldsAfter :=
  .shared .reusable (Or.inl rfl) rfl

end BoundaryV2.Generalized.Examples
