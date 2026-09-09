import BoundaryV2.EffectsExamples
import BoundaryV2.EffectsTrace

namespace BoundaryV2.Effects.Checks

open Core Control Examples

set_option maxRecDepth 10000

/-- Slot 1 denotes the ambient capability, not the newly entered handler. The
requested supply deliberately collides with that ambient identity. -/
def ambientUnderHandler : Flow Expr 0 1 [] .number :=
  .handle ⟨.ref .here, .dispose (constant 99)⟩ (.perform 1 (constant 41))

def ambientStart : Machine Expr 0 .number := initial ambientUnderHandler #[0].toVector 0

theorem ambient_identity_is_reserved : ambientStart.freshAttachment = 1 := rfl

theorem ambient_operation_remains_residual :
    observe (ticks Expr.eval 2 ambientStart) = some (.request 0 41) := rfl

theorem compiled_ambient_operation_remains_residual :
    observe (ticks evaluateBlock 2 (compileMachine ambientStart)) = some (.request 0 41) := rfl

/-- Two distinct requests have identical identities and payloads. Extra internal
polls occur while pending and after completion. Only polling is silent. -/
def identicalRequests : Flow Expr 0 1 [] .number :=
  .bind (.perform 0 (constant 41)) (.perform 0 (constant 41))

def identicalStart : Machine Expr 0 .number := initial identicalRequests #[7].toVector 8

def polledInputs : List Input := [.internal, .internal, .internal, .resume 10,
  .internal, .internal, .internal, .resume 20, .internal, .internal, .internal]

theorem distinct_equal_requests_are_not_deduplicated :
    (driveEvents Expr.eval identicalStart polledInputs).map Prod.snd =
      some [.request 7 41, .request 7 41, .returned (.number 20)] := rfl

theorem compiled_event_trace_matches :
    (driveEvents evaluateBlock (compileMachine identicalStart) polledInputs).map Prod.snd =
      some [.request 7 41, .request 7 41, .returned (.number 20)] := rfl

theorem sampling_api_is_unchanged :
    (drive Expr.eval identicalStart [.internal, .internal, .internal]).map Prod.snd =
      some [.request 7 41, .request 7 41] := rfl

theorem disposal_is_emitted_once :
    (driveEvents Expr.eval identicalStart [.internal, .internal, .dispose, .internal, .internal]).map Prod.snd =
      some [.request 7 41, .disposed] := rfl

theorem transfer_is_emitted_once :
    (driveEvents Expr.eval identicalStart [.internal, .internal, .transfer, .internal, .internal]).map Prod.snd =
      some [.request 7 41, .transferred 7 41] := rfl

theorem repeated_disposition_still_rejects :
    driveEvents Expr.eval identicalStart [.internal, .internal, .dispose, .dispose] = none := rfl

/-- The dormant inner template contains both a captured capability alias and
an outside capability. Activation must rename the former and retain the latter. -/
def aliasTemplate (identity : Nat) : Stack Expr 0 .number 0 .number :=
  .push (.delimiter identity ⟨.ref .here, .dispose (constant 0)⟩ .nil)
    (.push (.repeat
      (.push (.bind (.perform 0 (constant 0)) .nil #[identity, 7].toVector) .done)
      .done [1] (.number 0) (.ref .here) .nil) .done)

theorem dormant_aliases_are_renamed_together :
    (aliasTemplate 3).activate 10 = (aliasTemplate 10, 11) := by
  simp [aliasTemplate, Stack.activate, Stack.attachments, Stack.rename, Frame.rename, renameLocal]

theorem next_activation_uses_a_disjoint_interval :
    (aliasTemplate 3).activate 11 = (aliasTemplate 11, 12) := by
  simp [aliasTemplate, Stack.activate, Stack.attachments, Stack.rename, Frame.rename, renameLocal]

theorem dormant_aliases_are_bounded : (aliasTemplate 3).Below 10 := by
  simp [aliasTemplate, Stack.Below, Frame.Below, NamesBelow]

end BoundaryV2.Effects.Checks
