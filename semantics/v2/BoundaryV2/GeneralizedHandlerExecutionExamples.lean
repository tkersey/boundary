import BoundaryV2.GeneralizedSuccessorExamples
import BoundaryV2.GeneralizedOwnedClauseExamples

namespace BoundaryV2.Generalized.Examples

local instance : DecidableEq (signature.operation .choose) := fun first second => by
  cases first
  cases second
  exact isTrue rfl

def negateFutureBody : Source.Computation signature algebra []
    [.leaf .boolean, .capability .text, .leaf .boolean] (.leaf .boolean) :=
  .primitive Primitive.negate (.cons (.reference .here) .nil)

def sourceNegateFuture : Source.Context signature algebra [] (.leaf .boolean) (.leaf .boolean) :=
  .push (.bind (fun input => .evaluate negateFutureBody (.cons input textBindings))) .done

def targetNegateFuture : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .boolean) :=
  .push (.returnTo (.enter (Defunctionalization.computation negateFutureBody))
    (Defunctionalization.environment textBindings) .nil) .done

def afterChoiceResume : Source.Computation signature algebra []
    [.leaf .boolean, .continuation .shallow .affine .choose (.leaf .boolean) (.leaf .boolean), .unit,
      .capability .text, .leaf .boolean] (.leaf .text) :=
  Source.Computation.perform (signature := signature) (algebra := algebra)
    Operation.text (.reference (.there (.there (.there .here)))) (.reference .here) .nil

def resumingChoiceClause : Source.SelectedClause signature algebra [] Operation.choice .shallow
    [.capability .text, .leaf .boolean] (.leaf .boolean) (.leaf .text) :=
  ⟨.affine, .bind (.resume (.reference .here) (.datum (.leaf true))) afterChoiceResume⟩

def resumingChoiceClauses : Source.Clauses signature algebra [] .choose .shallow
    [.capability .text, .leaf .boolean] (.leaf .boolean) (.leaf .text) :=
  .cons Operation.choice .affine resumingChoiceClause.code .nil

def capturedSourceChoice := Source.captureOwnedClause resumingChoiceClause .affine rfl ⟨8⟩
  distinctNormalReturn resumingChoiceClauses textBindings sourceNegateFuture (.datum .unit) .nil .done
  (.lexical ⟨3⟩ 0) [] [] mixedControlFields.active mixedSourceControls rfl

def capturedTargetChoice := Target.captureOwnedClause (Defunctionalization.selectedClause resumingChoiceClause) .affine rfl ⟨8⟩
  (Defunctionalization.computation distinctNormalReturn) (Defunctionalization.clauses resumingChoiceClauses)
  (Defunctionalization.environment textBindings) targetNegateFuture (.datum .unit) .nil .done
  (.lexical ⟨3⟩ 0) [] [] mixedControlFields.active mixedTargetControls rfl

def resumingChoiceBindings : Source.RuntimeEnvironment signature algebra []
    [.continuation .shallow .affine .choose (.leaf .boolean) (.leaf .boolean), .unit, .capability .text, .leaf .boolean] :=
  .cons (.continuation ⟨12⟩ (some (⟨102⟩, .lexical ⟨3⟩ 0))) (.cons (.datum .unit) textBindings)

def resumingSourceCaller : Source.Context signature algebra [] (.leaf .boolean) (.leaf .text) :=
  .push (.bind (fun value => .evaluate afterChoiceResume (.cons value resumingChoiceBindings))) .done

def resumingTargetCaller : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .text) :=
  .push (.returnTo (.enter (Defunctionalization.computation afterChoiceResume))
    (Defunctionalization.environment resumingChoiceBindings) .nil) .done

def sourceAfterCapturedChoice : Source.ControlHeap signature algebra [] :=
  { mixedSourceControls with fields := { mixedControlFields with spent := [⟨102⟩] } }

def targetAfterCapturedChoice : Target.ControlHeap signature algebra [] :=
  { mixedTargetControls with fields := { mixedControlFields with spent := [⟨102⟩] } }

theorem source_captured_choice_acquires : UseScope.acquireAt choiceShape capturedSourceChoice.view capturedSourceChoice.store =
    some ⟨sourceAfterCapturedChoice, ⟨⟨8⟩, sourceNegateFuture⟩⟩ := UseScope.acquire_at_recovers_typed_future rfl

theorem target_captured_choice_acquires : UseScope.acquireAt choiceShape capturedTargetChoice.view capturedTargetChoice.store =
    some ⟨targetAfterCapturedChoice, ⟨⟨8⟩, targetNegateFuture⟩⟩ := UseScope.acquire_at_recovers_typed_future rfl

def sourceResumedChoice : Source.ControlState signature algebra [] (.leaf .text) :=
  ⟨sourceAfterCapturedChoice, resumingSourceCaller.plug (sourceNegateFuture.plug (.returned (.datum (.leaf true))))⟩

def targetResumedChoice : Target.ControlState signature algebra [] (.leaf .text) :=
  ⟨targetAfterCapturedChoice, .returned (.datum (.leaf true))
    (targetNegateFuture.append (.push (.returnTo .ret (Defunctionalization.environment resumingChoiceBindings) .nil) resumingTargetCaller))⟩

theorem source_resumes_newly_captured_future :
    Source.resumeControl choiceShape capturedSourceChoice.view capturedSourceChoice.store (.datum (.leaf true))
      resumingSourceCaller = some sourceResumedChoice := by
  unfold Source.resumeControl
  rw [source_captured_choice_acquires]
  rfl

theorem target_resumes_newly_captured_future :
    Target.resumeControl choiceShape capturedTargetChoice.view capturedTargetChoice.store (.datum (.leaf true))
      (.push (.returnTo .ret (Defunctionalization.environment resumingChoiceBindings) .nil) resumingTargetCaller) =
      some targetResumedChoice := by
  unfold Target.resumeControl
  rw [target_captured_choice_acquires]
  rfl

def sourceHandledChoice : Source.ControlState signature algebra [] (.leaf .text) :=
  ⟨mixedSourceControls, .handler .choose .shallow ⟨8⟩ distinctNormalReturn resumingChoiceClauses textBindings
    (.request Operation.choice ⟨8⟩ (.datum .unit) .nil sourceNegateFuture)⟩

def targetHandledChoice : Target.ControlState signature algebra [] (.leaf .text) :=
  ⟨mixedTargetControls, .requested Operation.choice ⟨8⟩ (.datum .unit) .nil
    (targetNegateFuture.append (.push (.handler .choose .shallow ⟨8⟩
      (Defunctionalization.computation distinctNormalReturn) (Defunctionalization.clauses resumingChoiceClauses)
      (Defunctionalization.environment textBindings)) .done))⟩

def afterChoiceRequestFuture : Target.Stack signature algebra [] (.leaf .text) (.leaf .text) :=
  .push (.returnTo .ret
    (Defunctionalization.environment (.cons (.datum (.leaf (type := Data.boolean) false)) resumingChoiceBindings)) .nil) .done

/-- Source control captures, evaluates the effectful clause, resumes the saved
negation, and sends its result to the next effect. It retains both older owners. -/
theorem source_handler_capture_resume_and_postprocessing : Source.OwnedSteps .nil sourceHandledChoice 7
    ⟨sourceAfterCapturedChoice, .request Operation.text ⟨4⟩ (.datum (.leaf false)) .nil .done⟩ := by
  refine .cons (.handled (signature := signature) (algebra := algebra) (operation := Operation.choice) (outside := .done)
    (inside := sourceNegateFuture) (returned := distinctNormalReturn) (clauses := resumingChoiceClauses)
    (bindings := textBindings) (owner := .lexical ⟨3⟩ 0) (before := []) (captured := [])
    (after := mixedControlFields.active) (partition := rfl) (clause := capturedSourceChoice) rfl rfl) (.cons (.ordinary .bind)
    (.cons (.resume (use := .affine) (continuation := .reference .here)
      (response := .datum (.leaf true)) (bindings := resumingChoiceBindings)
      (outside := resumingSourceCaller) (view := capturedSourceChoice.view)
      rfl rfl source_resumes_newly_captured_future) ?_))
  exact .cons (.ordinary (.bindStep .bindValue)) (.cons (.ordinary (.bindStep (.primitive rfl)))
    (.cons (.ordinary .bindValue) (.cons (.ordinary (.perform rfl rfl rfl)) .refl)))

/-- This trace uses target code, operand instructions, registry capture and
acquisition, and return frames. No source-evaluator step occurs in the target. -/
theorem target_handler_capture_resume_and_postprocessing : Target.OwnedSteps .nil targetHandledChoice 17
    ⟨targetAfterCapturedChoice, .requested Operation.text ⟨4⟩ (.datum (.leaf false)) .nil afterChoiceRequestFuture⟩ := by
  refine .cons (.handled (clause := capturedTargetChoice) rfl rfl) (.cons (.ordinary .block)
    (.cons (.ordinary (.operand .load)) (.cons (.ordinary (.operand .push))
      (.cons (.resume (use := .affine) (bindings := Defunctionalization.environment resumingChoiceBindings)
        (values := .nil) (outside := resumingTargetCaller) (next := .ret)
        (view := capturedTargetChoice.view) target_resumes_newly_captured_future) ?_))))
  exact .cons (.ordinary .caller) (.cons (.ordinary .enter) (.cons (.ordinary (.operand .load))
    (.cons (.ordinary (.operand (.primitive (signature := signature) (algebra := algebra)
      (operation := Primitive.negate) (arguments := .cons (.datum (.leaf true)) .nil) rfl)))
      (.cons (.ordinary .returned) (.cons (.ordinary .caller) (.cons (.ordinary .returned)
        (.cons (.ordinary .caller) (.cons (.ordinary .enter) (.cons (.ordinary (.operand .load))
          (.cons (.ordinary (.operand .load)) (.cons (.ordinary
            (.dispatch (signature := signature) (algebra := algebra) (operation := Operation.text)
              (bodies := .nil) (payload := .datum (.leaf false)) (attachment := ⟨4⟩))) .refl)))))))))))

theorem completed_handler_run_preserves_older_owners :
    UseScope.ControlStore.Valid targetAfterCapturedChoice ∧
      UseScope.inventory targetAfterCapturedChoice.fields = [⟨100⟩, ⟨101⟩] ∧
      UseScope.acquire capturedTargetChoice.view targetAfterCapturedChoice = none := by
  exact ⟨target_handler_capture_resume_and_postprocessing.preserves_ownership mixed_control_heap_valid, rfl, rfl⟩

theorem handler_open_observations_correspond :
    Defunctionalization.ControlHeapRelated sourceAfterCapturedChoice targetAfterCapturedChoice ∧
      Defunctionalization.ObservationRelated
        (Source.Observation.requested (signature := signature) (algebra := algebra)
          Operation.text ⟨4⟩ (.datum (.leaf false)) .nil .done)
        (.requested Operation.text ⟨4⟩ (.datum (.leaf false)) .nil afterChoiceRequestFuture) := by
  exact ⟨⟨rfl, mixed_controls_correspond.controls, .nil⟩,
    .requested Operation.text ⟨4⟩ (.datum (.leaf false)) .nil
      (.passthrough (.cons (.datum (.leaf (type := Data.boolean) false)) resumingChoiceBindings) .done)⟩

theorem handled_future_accepts_every_text (text : String) :
    Source.Observes (signature := signature) (algebra := algebra) .nil
      (.returned (.datum (.leaf (type := Data.text) text))) (.returned (.datum (.leaf text))) ∧
    Target.Observes .nil (.returned (.datum (.leaf text)) afterChoiceRequestFuture) (.returned (.datum (.leaf text))) :=
  Defunctionalization.empty_future_preserves_every_response (signature := signature) (algebra := algebra) .nil
    (.passthrough (.cons (show Source.RuntimeValue signature algebra [] (.leaf .boolean) from .datum (.leaf false))
      resumingChoiceBindings) .done)
    (.datum (.leaf (type := Data.text) text))

end BoundaryV2.Generalized.Examples
