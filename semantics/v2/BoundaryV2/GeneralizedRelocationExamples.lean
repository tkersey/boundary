import BoundaryV2.GeneralizedSelectionRelocation
import BoundaryV2.GeneralizedExitRelocation
import BoundaryV2.GeneralizedObservationExamples

namespace BoundaryV2.Generalized.Examples

def shiftReferences : UseScope.Relocation := {
  name := fun _ identity => ⟨identity.index + 100⟩
  owner := fun owner => match owner with
    | .lexical identity slot => .lexical ⟨identity.index + 100⟩ slot
    | .control identity slot => .control (identity + 100) slot
    | .package identity slot => .package (identity + 100) slot
    | .cleanup identity => .cleanup (identity + 100)
}

theorem shift_references_is_injective {first second : Id domain}
    (same : shiftReferences.name domain first = shiftReferences.name domain second) : first = second := by
  cases first with
  | mk first => cases second with
    | mk second =>
      have equal : first + 100 = second + 100 := congrArg Id.index same
      have original := Nat.add_right_cancel equal
      cases original
      rfl

abbrev DormantAliasType : TypeOf signature := .package (.computation .reusable [] (.capability .choose))

/-- Both cell references are dormant inside a closure, and a capability name
also occurs in its code rather than in the surrounding environment. -/
def dormantAliasValue : Target.RuntimeValue signature algebra [] DormantAliasType :=
  .package ⟨8⟩ (.lexical ⟨2⟩ 0)
    (.closure (.push (.capability ⟨9⟩) .ret)
      (.cons (.cell (type := .leaf Data.integer) ⟨7⟩ ⟨3⟩) (.cons (.cell (type := .leaf Data.integer) ⟨7⟩ ⟨3⟩) .nil)) none)

theorem dormant_code_and_aliases_move_together : Target.relocateValue shiftReferences dormantAliasValue =
    .package ⟨108⟩ (.lexical ⟨102⟩ 0)
      (.closure (.push (.capability ⟨109⟩) .ret)
        (.cons (.cell (type := .leaf Data.integer) ⟨107⟩ ⟨103⟩)
          (.cons (.cell (type := .leaf Data.integer) ⟨107⟩ ⟨103⟩) .nil)) none) := rfl

theorem relocating_dormant_aliases_does_not_duplicate_the_package_owner :
    (Target.relocateValue shiftReferences dormantAliasValue).owningField.tokens = [⟨108⟩] := rfl

def localMoveSupport : ∀ domain, List (Id domain)
  | .cell => [⟨2⟩, ⟨7⟩, ⟨7⟩]
  | .attachment => [⟨4⟩, ⟨9⟩]
  | .region => [⟨3⟩]
  | .custody => [⟨8⟩]
  | .scope => [⟨2⟩]
  | _ => []

def localMoveNames : ∀ domain, List (Id domain)
  | .cell => [⟨7⟩]
  | .attachment => [⟨9⟩]
  | _ => []

def localMove : UseScope.Relocation := UseScope.freshRelocation localMoveSupport localMoveNames (fun owner => owner)

theorem computed_local_relocation_preserves_external_region_and_owner :
    Target.relocateValue localMove dormantAliasValue =
      .package ⟨8⟩ (.lexical ⟨2⟩ 0)
        (.closure (.push (.capability ⟨19⟩) .ret)
          (.cons (.cell (type := .leaf Data.integer) ⟨15⟩ ⟨3⟩)
            (.cons (.cell (type := .leaf Data.integer) ⟨15⟩ ⟨3⟩) .nil)) none) := rfl

theorem relocated_closure_still_executes_and_opens_the_corresponding_request : ∃ count,
    Target.CallSteps (.nil : Target.Definitions signature algebra [])
      ((Target.Configuration.code (Defunctionalization.computation (.apply textClosure textArguments))
        (Defunctionalization.environment textBindings) .nil .done).relocate shiftReferences) count
      (.requested Operation.text ⟨104⟩ (.datum (.leaf true)) .nil (textTargetFuture.relocate shiftReferences)) := by
  obtain ⟨count, steps⟩ := compiled_captured_closure_opens_effect
  exact ⟨count, steps.relocate shiftReferences⟩

theorem relocated_selection_preserves_the_matching_handler :
    Target.select ⟨108⟩ (handledChoiceFuture.relocate shiftReferences) =
      (Target.select ⟨8⟩ handledChoiceFuture).map (Target.Selection.relocate shiftReferences) := by
  apply Target.selection_relocation shiftReferences ⟨8⟩ handledChoiceFuture
  intro first _ second _ same
  exact shift_references_is_injective same

def twoNominalHandlers : Target.Stack signature algebra [] .unit .unit :=
  .push (.handler .choose .deep ⟨9⟩ (.load .here .ret) choiceClauses .nil)
    (.push (.handler .choose .deep ⟨8⟩ (.load .here .ret) choiceClauses .nil) .done)

def collapseReferences : UseScope.Relocation := ⟨fun _ _ => ⟨0⟩, fun owner => owner⟩

/-- Collapsing the names selects the formerly nonmatching inner handler and
loses the captured prefix. The injectivity premise excludes this actual failure. -/
theorem noninjective_relocation_changes_selection :
    ((Target.select ⟨0⟩ (twoNominalHandlers.relocate collapseReferences)).map fun selected => selected.inside.attachments) = some [] ∧
      (((Target.select ⟨8⟩ twoNominalHandlers).map (Target.Selection.relocate collapseReferences)).map
        fun selected => selected.inside.attachments) = some [⟨0⟩] := ⟨rfl, rfl⟩

theorem captured_cleanup_relocation_preserves_completion_without_restarting :
    ExitComposition.Steps (.nil : Target.Definitions signature algebra [])
      ((ExitComposition.cancel "stop" capturedCleanup).relocate shiftReferences) 0
      ⟨⟨102⟩, .finished .returned,
        [.owned ⟨103⟩ (.cleanup 102), .owned ⟨104⟩ (.cleanup 102)], ⟨.failure .overflow, [], some "stop"⟩⟩ :=
  captured_cleanup_executes_its_saved_future.relocate shiftReferences

end BoundaryV2.Generalized.Examples
