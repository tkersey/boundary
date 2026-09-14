import BoundaryV2.GeneralizedInteraction
import BoundaryV2.GeneralizedObservationExamples
import BoundaryV2.GeneralizedFieldRelocation

namespace BoundaryV2.Generalized.Examples

def firstTextOpening : Target.Opened signature algebra [] Operation.text (.leaf .text) :=
  Target.openRequest (signature := signature) (algebra := algebra) Operation.text ⟨0⟩ ⟨4⟩
    (.datum (.leaf true)) .nil textTargetFuture ⟨[], [], []⟩
    (Target.no_selection_is_external (signature := signature) (algebra := algebra) Operation.text ⟨4⟩ textTargetFuture rfl)

def secondTextOpening : Target.Opened signature algebra [] Operation.text (.leaf .text) :=
  Target.openRequest (signature := signature) (algebra := algebra) Operation.text firstTextOpening.supply ⟨4⟩
    (.datum (.leaf true)) .nil textTargetFuture ⟨[], [], []⟩
    (Target.no_selection_is_external (signature := signature) (algebra := algebra) Operation.text ⟨4⟩ textTargetFuture rfl)

def firstTextResponse (value : String) : Target.Response signature algebra [] Operation.text :=
  ⟨firstTextOpening.pending.occurrence, ⟨4⟩, .datum (.leaf value)⟩

theorem equal_payloads_still_open_two_occurrences :
    firstTextOpening.pending.payload = secondTextOpening.pending.payload ∧
      firstTextOpening.pending.occurrence ≠ secondTextOpening.pending.occurrence := by
  exact ⟨rfl, by decide⟩

theorem polling_does_not_open_again :
    Target.interactMany (.parked firstTextOpening.pending) [.poll, .poll, .invalid, .poll] =
      .parked firstTextOpening.pending := rfl

theorem response_to_previous_equal_request_rejects (value : String) :
    Target.interact (.parked secondTextOpening.pending) (.response (firstTextResponse value)) =
      .parked secondTextOpening.pending := rfl

theorem typed_response_reenters_the_saved_text_future (value : String) :
    Target.interact (.parked firstTextOpening.pending) (.response (firstTextResponse value)) =
      .running (.returned (.datum (.leaf value)) textTargetFuture) ⟨[], [], []⟩ := rfl

theorem repeated_response_does_not_reenter_again (value : String) :
    Target.interactMany (.parked firstTextOpening.pending)
      [.response (firstTextResponse value), .response (firstTextResponse value)] =
      .running (.returned (.datum (.leaf value)) textTargetFuture) ⟨[], [], []⟩ := rfl

def dormantOwnedFields : UseScope.Field :=
  .closure [.continuation ⟨7⟩ [.owned ⟨8⟩ (.control 7 0), .alias ⟨8⟩,
    .cleanup ⟨9⟩ [.alias ⟨8⟩, .borrowed ⟨2⟩]]]

def moveDormantFields : UseScope.Relocation := {
  name := fun domain name => match domain with
    | .scope => name
    | _ => ⟨100 + name.index⟩
  owner := fun owner => match owner with
    | .control identity slot => .control (100 + identity) slot
    | other => other
}

theorem dormant_nested_aliases_and_obligations_relocate :
    dormantOwnedFields.relocate moveDormantFields =
      .closure [.continuation ⟨107⟩ [.owned ⟨108⟩ (.control 107 0), .alias ⟨108⟩,
        .cleanup ⟨109⟩ [.alias ⟨108⟩, .borrowed ⟨2⟩]]] := rfl

theorem aliases_do_not_become_owners_during_relocation :
    (dormantOwnedFields.relocate moveDormantFields).tokens = [⟨108⟩] := rfl

theorem computed_fresh_branches_do_not_share_a_local_cell :
    let support : List (Id .cell) := [⟨2⟩, ⟨7⟩, ⟨7⟩]
    let locals : List (Id .cell) := [⟨7⟩, ⟨7⟩]
    let first := FreshNames.allocate support locals
    FreshNames.rename locals first.start ⟨7⟩ ≠ FreshNames.rename locals first.next ⟨7⟩ := by
  decide

end BoundaryV2.Generalized.Examples
