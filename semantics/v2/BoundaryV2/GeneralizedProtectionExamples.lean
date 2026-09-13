import BoundaryV2.GeneralizedProtectionExecution
import BoundaryV2.GeneralizedExamples

namespace BoundaryV2.Generalized.Examples

def protectionBindings : Source.RuntimeEnvironment signature algebra [] [.capability .text] :=
  .cons (.datum (.capability ⟨4⟩)) .nil

def requestingCleanup : Source.Computation signature algebra [] [.exit, .capability .text] .unit :=
  .bind (.perform (signature := signature) (algebra := algebra) Operation.text (.reference (.there .here)) (.datum (.leaf true)) .nil)
    (.returnValue (.datum .unit))

def protectedBody : Source.Computation signature algebra [] [.capability .text] (.leaf .boolean) :=
  .yieldThen (.returnValue (.datum (.leaf true)))

def protectedProgram : Source.Computation signature algebra [] [.capability .text] (.leaf .boolean) :=
  .protect requestingCleanup protectedBody

def protectionSourceStore : Source.ControlHeap signature algebra [] := ⟨⟨[.cleanup ⟨19⟩ []], [], []⟩, [], []⟩
def protectionTargetStore : Target.ControlHeap signature algebra [] := ⟨protectionSourceStore.fields, [], []⟩

def protectionIdentity := Target.freshObligation (.nil : Target.Definitions signature algebra [])
  (Defunctionalization.computation protectedProgram) (Defunctionalization.environment protectionBindings) .nil
  (.done : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .boolean)) protectionTargetStore [] []

def protectionFuture : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .boolean) :=
  .push (.protection protectionIdentity (Defunctionalization.computation requestingCleanup) (Defunctionalization.environment protectionBindings))
    (.push (.returnTo .ret (Defunctionalization.environment protectionBindings) .nil) .done)

theorem protection_entry_avoids_existing_obligation_fields : protectionIdentity = ⟨20⟩ := rfl

theorem protected_body_yields_with_cleanup_still_attached :
    Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨protectionTargetStore, .code (Defunctionalization.computation protectedProgram)
        (Defunctionalization.environment protectionBindings) .nil .done⟩, [], []⟩ 2
      ⟨⟨protectionTargetStore, .yielded (.code (.push (.leaf true) .ret)
        (Defunctionalization.environment protectionBindings) .nil protectionFuture)⟩, [], []⟩ ∧
    ExitComposition.pendingProtections protectionFuture = [⟨20⟩] := by
  obtain ⟨_, entered, _⟩ := Defunctionalization.compiled_protection_entry
    (signature := signature) (algebra := algebra) .nil requestingCleanup protectedBody protectionBindings .done
    (sourceStore := protectionSourceStore) (targetStore := protectionTargetStore) ⟨rfl, .nil, .nil⟩ [] [] []
  exact ⟨entered.trans (.single (.cell (.ordinary .yield))), rfl⟩

def cleanupExit : ExitInfo Fault String := ⟨.failure .overflow, [], none⟩

def sourceCleanupBindings : Source.RuntimeEnvironment signature algebra [] [.exit, .capability .text] :=
  .cons (.exit cleanupExit) protectionBindings

def sourceCleanupFuture : Source.Context signature algebra [] (.leaf .text) .unit :=
  .push (.bindAuthored (.returnValue (.datum .unit)) sourceCleanupBindings) .done

theorem source_cleanup_reaches_its_effect_request :
    Source.Steps (.nil : Source.Definitions signature algebra []) (.evaluate requestingCleanup sourceCleanupBindings) 3
      (.request Operation.text ⟨4⟩ (.datum (.leaf true)) .nil sourceCleanupFuture) :=
  .cons .bind (.cons (.bindStep (.perform rfl rfl rfl)) (.cons .bindRequest .refl))

def pendingRequestingCleanup : ExitComposition.Obligation signature algebra [] :=
  ⟨⟨20⟩, .pending ⟨[.capability .text], Defunctionalization.computation requestingCleanup,
    Defunctionalization.environment protectionBindings⟩, [.owned ⟨7⟩ (.cleanup 20)], cleanupExit⟩

theorem protected_scope_hands_off_its_actual_cleanup_descriptor :
    ExitComposition.detachProtection protectionFuture pendingRequestingCleanup.fields cleanupExit =
      some ⟨pendingRequestingCleanup, .push (.returnTo .ret (Defunctionalization.environment protectionBindings) .nil) .done⟩ := rfl

theorem detached_cleanup_has_no_second_pending_frame :
    (⟨20⟩ : Id .obligation) ∉ ExitComposition.pendingProtections
      (.push (.returnTo .ret (Defunctionalization.environment protectionBindings) .nil)
        (.done : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .boolean))) := by
  exact ExitComposition.detached_pending_frame_is_not_in_the_remaining_continuation
    (by simp [ExitComposition.pendingProtections, protectionFuture]) protected_scope_hands_off_its_actual_cleanup_descriptor

/-- The captured object contains the actual compiled request cursor. Cancelling
it twice preserves that cursor, the original fault, and its first reason. -/
theorem effectful_cleanup_capture_keeps_its_cursor_and_single_start :
    ∃ cursor : ExitComposition.Cursor signature algebra [],
      ExitComposition.Steps (.nil : Target.Definitions signature algebra []) pendingRequestingCleanup 1
        ⟨⟨20⟩, .running cursor (.captured ⟨55⟩), pendingRequestingCleanup.fields, (cleanupExit.cancel "first").cancel "later"⟩ ∧
      Defunctionalization.ProgramRelated
        (.request Operation.text ⟨4⟩ (.datum (.leaf true)) .nil sourceCleanupFuture) .done cursor ∧
      ((cleanupExit.cancel "first").cancel "later").cancellation = some "first" ∧
      ((cleanupExit.cancel "first").cancel "later").primary = .failure .overflow := by
  obtain ⟨cursor, steps, related⟩ := Defunctionalization.finite_cleanup_execution_corresponds
    (signature := signature) (algebra := algebra) .nil requestingCleanup protectionBindings ⟨20⟩ pendingRequestingCleanup.fields
    cleanupExit source_cleanup_reaches_its_effect_request
  have later : ExitComposition.Steps (.nil : Target.Definitions signature algebra [])
      ⟨⟨20⟩, .running cursor .active, pendingRequestingCleanup.fields, cleanupExit⟩ 0
      ⟨⟨20⟩, .running cursor (.captured ⟨55⟩), pendingRequestingCleanup.fields, (cleanupExit.cancel "first").cancel "later"⟩ :=
    .cons (.lifecycle (.capture (signature := signature) (algebra := algebra) (obligationId := ⟨20⟩) (cursor := cursor)
      (controlId := ⟨55⟩) (fields := pendingRequestingCleanup.fields) (exit := cleanupExit)))
      (.cons (.lifecycle (.cancelled (reason := "first"))) (.cons (.lifecycle (.cancelled (reason := "later"))) .refl))
  exact ⟨cursor, steps.trans later, related, rfl, rfl⟩

end BoundaryV2.Generalized.Examples
