import BoundaryV2.GeneralizedStateObservations
import BoundaryV2.GeneralizedOrdinaryOwnedExecution
import BoundaryV2.GeneralizedStatefulCellExecution
import BoundaryV2.GeneralizedInjectionExecution
import BoundaryV2.GeneralizedFreshHandlerExecution
import BoundaryV2.GeneralizedProtectionExecution
import BoundaryV2.GeneralizedRegionExecution
import BoundaryV2.GeneralizedPackageExecution

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

variable {retained : List Reference}

/-- The ordinary branch of Source.ExecutionStep (retained := retained) uses this actual neutral gate.
Closure-producing operands, admitted application, and handler installation use
their separate permission-sensitive constructors instead. -/
theorem ordinary_computation_state_step_simulates
    (table : Source.Definitions signature algebra program)
    {body : Source.Computation signature algebra program context input}
    {bindings : Source.RuntimeEnvironment signature algebra program context}
    {after : Source.Program signature algebra program input}
    (step : Source.Step table (.evaluate body bindings) after)
    (neutral : (Source.Program.evaluate body bindings).needsOwnershipStep = false)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region)) :
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (retained := retained) (definitions table)
      ⟨⟨targetStore, .code (computation body) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count targetAfter ∧
      ExecutionStateRelated ⟨⟨sourceStore, sourceOutside.plug after⟩, sourceCells, regions⟩ targetAfter := by
  have plain : body.operandPrefix.arguments.containsClosure = false := (Bool.or_eq_false_iff.mp neutral).1
  cases step with
  | operandFault failed =>
    have owned := body.operandPrefix.arguments.owned_evaluation_of_no_closure bindings (sourceCells.reservations.withSupport retained).custody sourceStore plain
    rw [failed] at owned
    obtain ⟨_, count, targetAfter, positive, steps, related⟩ :=
      compiled_owned_operand_failure (retained := retained) table body bindings _ sourceCells regions owned stores outside
    exact ⟨count, _, positive, steps, related.as_execution⟩
  | returnValue evaluated | primitive evaluated =>
    have owned := Source.Expression.owned_evaluation_of_no_closure _ bindings (sourceCells.reservations.withSupport retained).custody sourceStore
      (by simpa only [Source.Computation.operandPrefix, Source.Arguments.containsClosure, Bool.or_false] using plain)
    rw [evaluated] at owned
    obtain ⟨_, count, targetAfter, positive, steps, related⟩ :=
      compiled_owned_operand_return (retained := retained) table _ bindings _ sourceCells regions owned stores outside
    exact ⟨count, _, positive, steps, related.as_execution⟩
  | bind =>
    exact ⟨1, _, by omega, .single (.cell (.ordinary .block)),
      ⟨stores, rfl, rfl, outside.close_program (.bind _ _ (.evaluate _ _ _))⟩⟩
  | @call definition reference context arguments bindings values evaluated =>
    have owned := arguments.owned_evaluation_of_no_closure bindings (sourceCells.reservations.withSupport retained).custody sourceStore plain
    rw [evaluated] at owned
    obtain ⟨_, count, targetAfter, positive, steps, related⟩ :=
      compiled_owned_named_call (retained := retained) table reference arguments bindings values sourceCells regions owned stores outside
    exact ⟨count, _, positive, steps, related.as_execution⟩
  | apply functionEvaluated argumentsEvaluated =>
    simp [Source.Program.needsOwnershipStep, Source.Arguments.evaluate, functionEvaluated, argumentsEvaluated,
      Except.isOk, Except.toBool] at neutral
  | matchLeft evaluated selected =>
    have owned := Source.Expression.owned_evaluation_of_no_closure _ bindings (sourceCells.reservations.withSupport retained).custody sourceStore
      (by simpa only [Source.Computation.operandPrefix, Source.Arguments.containsClosure, Bool.or_false] using plain)
    rw [evaluated] at owned
    obtain ⟨_, count, targetAfter, positive, steps, related⟩ :=
      compiled_owned_match_left (retained := retained) table _ _ _ bindings _ _ sourceCells regions owned selected stores outside
    exact ⟨count, _, positive, steps, related.as_execution⟩
  | matchRight evaluated selected =>
    have owned := Source.Expression.owned_evaluation_of_no_closure _ bindings (sourceCells.reservations.withSupport retained).custody sourceStore
      (by simpa only [Source.Computation.operandPrefix, Source.Arguments.containsClosure, Bool.or_false] using plain)
    rw [evaluated] at owned
    obtain ⟨_, count, targetAfter, positive, steps, related⟩ :=
      compiled_owned_match_right (retained := retained) table _ _ _ bindings _ _ sourceCells regions owned selected stores outside
    exact ⟨count, _, positive, steps, related.as_execution⟩
  | @perform effect operation context capability payload bodies bindings attachment payloadValue bodyValues capabilityAt payloadAt bodiesAt =>
    have owned := (Source.Arguments.cons capability (.cons payload bodies)).owned_evaluation_of_no_closure
      bindings (sourceCells.reservations.withSupport retained).custody sourceStore plain
    simp only [Source.Arguments.evaluate, capabilityAt, payloadAt, bodiesAt] at owned
    obtain ⟨_, count, targetAfter, positive, steps, related⟩ :=
      compiled_owned_operation (retained := retained) table operation capability payload bodies bindings attachment payloadValue bodyValues
        sourceCells regions owned stores outside
    exact ⟨count, _, positive, steps, related.as_execution⟩
  | handle => simp [Source.Program.needsOwnershipStep] at neutral
  | fail => exact ⟨1, _, by omega, .single (.cell (.ordinary .fault)),
      ⟨stores, rfl, rfl, outside.close_program (.failed _ _)⟩⟩
  | yield => exact ⟨1, _, by omega, .single (.cell (.ordinary .yield)),
      ⟨stores, rfl, rfl, outside.close_program (.yielded (.evaluate _ _ _))⟩⟩

/-- Neutral source reductions compose under every related enclosing frame.
Administrative target steps use the actual owning execution relation; the
source store and its physical fields are related at the resulting boundary. -/
theorem ordinary_program_state_step_simulates
    (table : Source.Definitions signature algebra program)
    {source after : Source.Program signature algebra program input}
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    {target : Target.Configuration signature algebra program result}
    (related : ProgramRelated source targetOutside target)
    (step : Source.Step table source after) (neutral : source.needsOwnershipStep = false)
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region)) :
    ∃ count targetAfter, Target.ExecutionSteps (retained := retained) (definitions table)
      ⟨⟨targetStore, target⟩, cells sourceCells, regions⟩ count targetAfter ∧
      ExecutionStateRelated ⟨⟨sourceStore, sourceOutside.plug after⟩, sourceCells, regions⟩ targetAfter := by
  induction related with
  | evaluate body bindings future =>
    obtain ⟨count, targetAfter, _, steps, matched⟩ :=
      ordinary_computation_state_step_simulates (retained := retained) table step neutral outside stores sourceCells regions
    exact ⟨count, targetAfter, steps, matched⟩
  | returned | failed | requested | yielded => cases step
  | passthrough bindings inner induction => exact induction step neutral (.passthrough bindings outside)
  | bind body bindings inner induction =>
    cases step with
    | bindValue =>
      obtain ⟨count, steps⟩ := inner.returned_state_drains (retained := retained) (definitions table) _ rfl targetStore (cells sourceCells) regions
      exact ⟨count + 2, _, steps.trans (.cons (.cell (.ordinary .caller)) (.cons (.cell (.ordinary .enter)) .refl)),
        ⟨stores, rfl, rfl, outside.close_program (.evaluate body (.cons _ bindings) _)⟩⟩
    | bindFault =>
      obtain ⟨count, steps⟩ := inner.failed_state_drains (retained := retained) (definitions table) _ rfl targetStore (cells sourceCells) regions
      exact ⟨count + 1, _, steps.trans (.single (.cell (.ordinary .callerFault))),
        ⟨stores, rfl, rfl, outside.close_program (.failed _ _)⟩⟩
    | bindYield =>
      obtain ⟨targetNext, rfl, nextRelated⟩ := inner.yielded_view _ rfl
      exact ⟨0, _, .refl, ⟨stores, rfl, rfl, outside.close_program (.yielded (.bind body bindings nextRelated))⟩⟩
    | bindRequest =>
      obtain ⟨future, saved, rfl⟩ := inner.requested_view _ _ _ _ _ rfl
      refine ⟨0, _, .refl, ⟨stores, rfl, rfl, outside.close_program ?_⟩⟩
      simpa only [Target.Stack.append_associative, Target.Stack.append, Source.Frame.bindAuthored] using
        ProgramRelated.requested _ _ _ _ (context_composition saved (.push (.bind body bindings) .done)) _
    | bindStep sourceStep =>
      simpa only [Source.Context.plug, Source.Frame.plug, Source.Frame.bindAuthored, Source.Program.bindAuthored] using
        induction sourceStep neutral (.push (.bind body bindings) outside)
  | handler effect mode attachment returned clauses bindings inner induction =>
    cases step with
    | handlerValue =>
      obtain ⟨count, steps⟩ := inner.returned_state_drains (retained := retained) (definitions table) _ rfl targetStore (cells sourceCells) regions
      exact ⟨count + 1, _, steps.trans (.single (.cell (.ordinary .handlerReturned))),
        ⟨stores, rfl, rfl, outside.close_program (.evaluate returned (.cons _ bindings) _)⟩⟩
    | handlerFault =>
      obtain ⟨count, steps⟩ := inner.failed_state_drains (retained := retained) (definitions table) _ rfl targetStore (cells sourceCells) regions
      exact ⟨count + 1, _, steps.trans (.single (.cell (.ordinary .handlerFault))),
        ⟨stores, rfl, rfl, outside.close_program (.failed _ _)⟩⟩
    | handlerYield =>
      obtain ⟨targetNext, rfl, nextRelated⟩ := inner.yielded_view _ rfl
      exact ⟨0, _, .refl,
        ⟨stores, rfl, rfl, outside.close_program (.yielded (.handler effect mode attachment returned clauses bindings nextRelated))⟩⟩
    | handlerForward different | handlerUnhandled absent =>
      obtain ⟨future, saved, rfl⟩ := inner.requested_view _ _ _ _ _ rfl
      refine ⟨0, _, .refl, ⟨stores, rfl, rfl, outside.close_program ?_⟩⟩
      simpa only [Target.Stack.append_associative, Target.Stack.append] using
        ProgramRelated.requested _ _ _ _ (context_composition saved
          (.push (.handler effect mode attachment returned clauses bindings) .done)) _
    | handlerStep sourceStep =>
      simpa only [Source.Context.plug, Source.Frame.plug] using
        induction sourceStep neutral (.push (.handler effect mode attachment returned clauses bindings) outside)
  | region identity inner induction =>
    cases step with
    | regionStep sourceStep =>
      simpa only [Source.Context.plug, Source.Frame.plug] using induction sourceStep neutral (.push (.region identity) outside)
    | regionYield =>
      obtain ⟨targetNext, rfl, nextRelated⟩ := inner.yielded_view _ rfl
      exact ⟨0, _, .refl, ⟨stores, rfl, rfl, outside.close_program (.yielded (.region identity nextRelated))⟩⟩
    | regionRequest =>
      obtain ⟨future, saved, rfl⟩ := inner.requested_view _ _ _ _ _ rfl
      refine ⟨0, _, .refl, ⟨stores, rfl, rfl, outside.close_program ?_⟩⟩
      simpa only [Target.Stack.append_associative, Target.Stack.append] using
        ProgramRelated.requested _ _ _ _ (context_composition saved (.push (.region identity) .done)) _
  | cleaning identity original exit inner induction =>
    cases step with
    | cleaningReturn normal =>
      obtain ⟨count, steps⟩ := inner.returned_state_drains (retained := retained) (definitions table) _ rfl targetStore (cells sourceCells) regions
      exact ⟨count + 1, _, steps.trans (.single (.cell (.ordinary (.cleanupReturn normal)))),
        ⟨stores, rfl, rfl, outside.close_program (.returned _ _)⟩⟩
    | cleaningStep sourceStep =>
      simpa only [Source.Context.plug, Source.Frame.plug] using
        induction sourceStep neutral (.push (.cleanupReturn identity original exit) outside)
    | cleaningYield =>
      obtain ⟨targetNext, rfl, nextRelated⟩ := inner.yielded_view _ rfl
      exact ⟨0, _, .refl,
        ⟨stores, rfl, rfl, outside.close_program (.yielded (.cleaning identity original exit nextRelated))⟩⟩
    | cleaningRequest =>
      obtain ⟨future, saved, rfl⟩ := inner.requested_view _ _ _ _ _ rfl
      refine ⟨0, _, .refl, ⟨stores, rfl, rfl, outside.close_program ?_⟩⟩
      simpa only [Target.Stack.append_associative, Target.Stack.append] using
        ProgramRelated.requested _ _ _ _ (context_composition saved (.push (.cleanupReturn identity original exit) .done)) _
  | protection identity cleanup bindings inner induction =>
    cases step with
    | protectionReturn =>
      obtain ⟨count, steps⟩ := inner.returned_state_drains (retained := retained) (definitions table) _ rfl targetStore (cells sourceCells) regions
      exact ⟨count + 1, _, steps.trans (.single (.cell (.ordinary .protectionReturn))),
        ⟨stores, rfl, rfl, outside.close_program
          (.cleaning identity _ _ (.evaluate cleanup (.cons (.exit ⟨.normal, [], none⟩) bindings) _))⟩⟩
    | protectionStep sourceStep =>
      simpa only [Source.Context.plug, Source.Frame.plug] using
        induction sourceStep neutral (.push (.protection identity cleanup bindings) outside)
    | protectionYield =>
      obtain ⟨targetNext, rfl, nextRelated⟩ := inner.yielded_view _ rfl
      exact ⟨0, _, .refl,
        ⟨stores, rfl, rfl, outside.close_program (.yielded (.protection identity cleanup bindings nextRelated))⟩⟩
    | protectionRequest =>
      obtain ⟨future, saved, rfl⟩ := inner.requested_view _ _ _ _ _ rfl
      refine ⟨0, _, .refl, ⟨stores, rfl, rfl, outside.close_program ?_⟩⟩
      simpa only [Target.Stack.append_associative, Target.Stack.append] using
        ProgramRelated.requested _ _ _ _ (context_composition saved (.push (.protection identity cleanup bindings) .done)) _

section Inversion
omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- Open one authored frame in the structural relation. The bind case uses the
stored authored description as well as the callback; extensional callback
equality alone does not provide a frame correspondence. -/
theorem ProgramRelated.peel_frame
    {targetOutside : Target.Stack signature algebra program answer result}
    {target : Target.Configuration signature algebra program result}
    (related : ProgramRelated (whole : Source.Program signature algebra program answer) targetOutside target)
    (frame : Source.Frame signature algebra program input answer)
    (source : Source.Program signature algebra program input) (same : whole = frame.plug source)
    {sourceOutside : Source.Context signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    ∃ targetInside, ContextRelated signature algebra program (.push frame sourceOutside) targetInside ∧
      ProgramRelated source targetInside target := by
  induction related with
  | evaluate | returned | failed | requested | yielded => cases frame <;> cases same
  | passthrough bindings inner induction => exact induction frame same (.passthrough bindings outside)
  | bind body bindings inner induction =>
    cases frame <;> cases same
    exact ⟨_, .push (.bind body bindings) outside, inner⟩
  | handler effect mode attachment returned clauses bindings inner induction =>
    cases frame <;> cases same
    exact ⟨_, .push (.handler effect mode attachment returned clauses bindings) outside, inner⟩
  | region identity inner induction =>
    cases frame <;> cases same
    exact ⟨_, .push (.region identity) outside, inner⟩
  | protection identity cleanup bindings inner induction =>
    cases frame <;> cases same
    exact ⟨_, .push (.protection identity cleanup bindings) outside, inner⟩
  | cleaning identity original exit inner induction =>
    cases frame <;> cases same
    exact ⟨_, .push (.cleanupReturn identity original exit) outside, inner⟩

/-- Open an existing source context; the target's real frames, including silent
return frames, are recovered rather than replaced by a freshly compiled stack. -/
theorem open_program_context
    {targetOutside : Target.Stack signature algebra program answer result}
    {target : Target.Configuration signature algebra program result}
    (context : Source.Context signature algebra program input answer)
    (source : Source.Program signature algebra program input)
    (related : ProgramRelated (context.plug source) targetOutside target)
    {sourceOutside : Source.Context signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    ∃ targetInside, ContextRelated signature algebra program (context.append sourceOutside) targetInside ∧
      ProgramRelated source targetInside target := by
  cases context with
  | done => exact ⟨_, outside, related⟩
  | push frame rest =>
    obtain ⟨middle, remaining, inner⟩ := open_program_context rest (frame.plug source) related outside
    exact inner.peel_frame frame source rfl remaining
termination_by context.length
decreasing_by simp_all [Source.Context.length]

theorem ProgramRelated.evaluation_view
    {targetOutside : Target.Stack signature algebra program input result}
    {target : Target.Configuration signature algebra program result}
    (related : ProgramRelated (whole : Source.Program signature algebra program input) targetOutside target)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (same : whole = .evaluate body bindings)
    {sourceOutside : Source.Context signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    ∃ targetInside, ContextRelated signature algebra program sourceOutside targetInside ∧
      target = .code (computation body) (environment bindings) .nil targetInside := by
  induction related with
  | evaluate => cases same; exact ⟨_, outside, rfl⟩
  | passthrough captured inner induction => exact induction body same (.passthrough captured outside)
  | returned | failed | requested | yielded | bind | handler | region | protection | cleaning => cases same

/-- A stateful operation reuses the target caller recovered from the current
relation. Resource correspondence is retained when that entry is exposed. -/
theorem ExecutionStateRelated.evaluation_view
    {sourceStore : Source.ControlHeap signature algebra program}
    {sourceCells : Cells signature algebra (Source.Computation signature algebra program)}
    {regions : List (Id .region)} {target : Target.State signature algebra program result}
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (sourceOutside : Source.Context signature algebra program input result)
    (related : ExecutionStateRelated
      (⟨⟨sourceStore, sourceOutside.plug (.evaluate body bindings)⟩, sourceCells, regions⟩ : Source.State signature algebra program result)
      target) :
    ∃ targetOutside, ContextRelated signature algebra program sourceOutside targetOutside ∧
      target = ⟨⟨target.control.store, .code (Defunctionalization.computation body) (environment bindings) .nil targetOutside⟩,
        Defunctionalization.cells sourceCells, regions⟩ := by
  obtain ⟨middle, outside, inner⟩ := open_program_context sourceOutside (.evaluate body bindings) related.computation .done
  obtain ⟨targetOutside, matched, configuration⟩ := inner.evaluation_view body bindings rfl outside
  refine ⟨targetOutside, ?_, ?_⟩
  · simpa only [Source.Context.append_done] using matched
  · cases target with
    | mk control storage live => cases control with
      | mk store state =>
        have storageEq := related.cells
        have regionsEq := related.regions
        dsimp only at configuration storageEq regionsEq
        simp only [configuration, storageEq, ← regionsEq]

theorem ExecutionStateRelated.target_state
    {source : Source.State signature algebra program result}
    {target : Target.State signature algebra program result}
    (related : ExecutionStateRelated source target) :
    target = ⟨target.control, Defunctionalization.cells source.cells, source.liveRegions⟩ :=
  (congrArg (fun storage => Target.State.mk target.control storage target.liveRegions) related.cells).trans
    (congrArg (Target.State.mk target.control (Defunctionalization.cells source.cells)) related.regions.symm)


end Inversion

/-- All source cell transitions, including their ordered owned operands,
preserve the execution relation at the actual target caller. -/
theorem cell_state_step_simulates (table : Source.Definitions signature algebra program)
    {source after : Source.State signature algebra program result}
    {target : Target.State signature algebra program result}
    (step : Source.CellStep (retained := retained) table source after) (related : ExecutionStateRelated source target) :
    ∃ count targetAfter, Target.ExecutionSteps (retained := retained) (definitions table) target count targetAfter ∧
      ExecutionStateRelated after targetAfter := by
  cases step with
  | @ordinary type first last sourceStore storage regions _ ordinary neutral =>
    rw [related.target_state]
    exact ordinary_program_state_step_simulates (retained := retained) table related.computation ordinary neutral .done related.store storage regions
  | @allocate context type result _ region evaluated regions fields reserved regionExpr valueExpr bindings sourceOutside sourceStore storage value operands live handoff =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.cellNew regionExpr valueExpr) bindings sourceOutside
    rw [configuration]
    obtain ⟨count, _, _, steps, matched⟩ := compiled_cell_allocation (retained := retained) table regionExpr valueExpr bindings region value
      storage reserved regions live operands related.store fields handoff outside
    exact ⟨count, _, steps, matched.as_execution⟩
  | @read context type result _ sourceStore identity region evaluated regions value reference bindings sourceOutside storage operands live read =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.cellRead reference) bindings sourceOutside
    rw [configuration]
    obtain ⟨count, _, _, steps, matched⟩ := compiled_cell_read (retained := retained) table reference bindings identity region value
      storage regions live operands read related.store outside
    exact ⟨count, _, steps, matched.as_execution⟩
  | @write context type result _ sourceStore identity region value evaluated regions afterCells reference replacement bindings sourceOutside storage operands live written =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.cellWrite reference replacement) bindings sourceOutside
    rw [configuration]
    obtain ⟨count, _, _, steps, matched⟩ := compiled_cell_write (retained := retained) table reference replacement bindings identity region value
      storage afterCells regions live operands written related.store outside
    exact ⟨count, _, steps, matched.as_execution⟩

/-- One-shot resumption, successor, injection, and handled-clause entry all use
the same state relation as ordinary execution. Their actual grants, captured
fields, computed control identities, and current cell reservations participate. -/
theorem control_state_step_simulates (table : Source.Definitions signature algebra program)
    {source after : Source.ControlState signature algebra program result}
    {target : Target.State signature algebra program result}
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region))
    (step : Source.OwnedStep table (sourceCells.reservations.withSupport retained) source after)
    (related : ExecutionStateRelated ⟨source, sourceCells, regions⟩ target) :
    ∃ count targetAfter, Target.ExecutionSteps (retained := retained) (definitions table) target count targetAfter ∧
      ExecutionStateRelated ⟨after, sourceCells, regions⟩ targetAfter := by
  cases step with
  | @ordinary type first last sourceStore ordinary neutral =>
    rw [related.target_state]
    exact ordinary_program_state_step_simulates (retained := retained) table related.computation ordinary neutral .done related.store sourceCells regions
  | @resume context mode effect input body result sourceStore value evaluated view after use continuation response bindings sourceOutside operands accepted =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.resume continuation response) bindings sourceOutside
    rw [configuration]
    obtain ⟨targetAfter, count, _, matched, _, steps⟩ :=
      compiled_owned_resumption table (sourceCells.reservations.withSupport retained) use continuation response bindings view value operands related.store outside accepted
    have reserved : ((cells sourceCells).reservations.withSupport retained) = (sourceCells.reservations.withSupport retained) := Cells.reservations_with_support_mapBodies _ sourceCells retained
    rw [← reserved] at steps
    exact ⟨count, _, steps.in_execution (retained := retained) (cells sourceCells) regions,
      ⟨matched.store, rfl, rfl, matched.entry.as_program⟩⟩
  | @successor context effect input body answer result sourceStore value evaluated view after use continuation response returned clauses bindings sourceOutside operands accepted =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view
      (.resumeWith effect continuation response returned clauses) bindings sourceOutside
    rw [configuration]
    obtain ⟨targetAfter, count, _, matched, _, steps⟩ :=
      compiled_owned_successor table (sourceCells.reservations.withSupport retained) use continuation response returned clauses bindings view value
        operands related.store outside accepted
    have reserved : ((cells sourceCells).reservations.withSupport retained) = (sourceCells.reservations.withSupport retained) := Cells.reservations_with_support_mapBodies _ sourceCells retained
    rw [← reserved] at steps
    exact ⟨count, _, steps.in_execution (retained := retained) (cells sourceCells) regions,
      ⟨matched.store, rfl, rfl, matched.entry.as_program⟩⟩
  | @injection context mode effect input answer capturedTypes result sourceStore authority evaluated fields view after use bodyUse continuation injected body captured bindings sourceOutside operands handoff accepted =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.inject continuation injected) bindings sourceOutside
    rw [configuration]
    obtain ⟨targetAfter, count, _, matched, _, steps⟩ :=
      compiled_computation_injection (retained := retained) table use continuation injected bindings body captured authority view sourceCells regions
        operands related.store handoff outside accepted
    exact ⟨count, _, steps, matched.as_execution⟩
  | @handledRequest attachment owner effect operation operationEquality mode context body answer result returned clauses bindings payload bodies input saved around sourceInside sourceOutside sourceStore before captured after partition clause selected accepted =>
    obtain ⟨targetAround, aroundRelated, inner⟩ := open_program_context around
      (.request operation attachment payload bodies saved) related.computation .done
    obtain ⟨targetSaved, savedRelated, configuration⟩ := inner.requested_view _ _ _ _ _ rfl
    have combined : ContextRelated signature algebra program (saved.append around) (targetSaved.append targetAround) := by
      simpa only [Source.Context.append_done] using context_composition savedRelated aroundRelated
    have nearest := Source.selection_inside_has_no_match (saved.append around) attachment _ selected
    obtain ⟨targetSelected, targetFound, selectedRelated⟩ := corresponding_acceptance (selection_corresponds attachment combined) selected
    have reconstructed := Target.selection_reconstructs (targetSaved.append targetAround) attachment targetSelected targetFound
    cases selectedRelated with
    | selected effect mode identity returned clauses bindings inside outside =>
      have targetPartition : target.control.store.fields.active = before ++ captured ++ after := by
        rw [← related.store.fields]
        exact partition
      obtain ⟨targetAfter, matched, _, steps⟩ := handled_operation_with_cells_corresponds (retained := retained) table operation attachment returned clauses bindings
        inside payload bodies outside owner before captured after related.store sourceCells regions partition targetPartition nearest accepted
      refine ⟨1, _, ?_, matched.as_execution⟩
      rw [related.target_state]
      change Target.ExecutionSteps (retained := retained) (definitions table)
        ⟨⟨target.control.store, target.control.configuration⟩, cells sourceCells, regions⟩ 1 _
      rw [configuration, ← reconstructed]
      exact steps

/-- Preservation for every constructor of the current stateful execution
relation. The proof invokes the actual operation laws with the caller recovered
from the structural relation, including their local permission premises. -/
theorem stateful_execution_step_simulates (table : Source.Definitions signature algebra program)
    {source after : Source.State signature algebra program result}
    {target : Target.State signature algebra program result}
    (step : Source.ExecutionStep (retained := retained) table source after) (related : ExecutionStateRelated source target) :
    ∃ count targetAfter, Target.ExecutionSteps (retained := retained) (definitions table) target count targetAfter ∧
      ExecutionStateRelated after targetAfter := by
  cases step with
  | cell step => exact cell_state_step_simulates (retained := retained) table step related
  | control step => exact control_state_step_simulates (retained := retained) table _ _ step related
  | @installHandler bodyType context answer effect mode result outsideSupport sourceStore storedSupport attachment _ regions returned clauses body bindings sourceOutside sourceCells extra supported stored created =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.handle effect mode returned clauses body) bindings sourceOutside
    rw [configuration]
    have sameOutside := supported.unique (context_installation_support outside)
    have sameStore := stored.unique (store_installation_support related.store)
    rw [sameOutside, sameStore, fresh_attachment_corresponds] at created
    rw [created]
    obtain ⟨_, steps, matched⟩ := compiled_fresh_handler (retained := retained) table effect mode returned clauses body bindings outside related.store sourceCells regions extra
    exact ⟨1, _, steps, matched.as_execution⟩
  | @enterProtection context answer result outsideSupport sourceStore storedSupport identity _ regions cleanup body bindings sourceOutside sourceCells extra supported stored created =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.protect cleanup body) bindings sourceOutside
    rw [configuration]
    have sameOutside := supported.unique (context_installation_support outside)
    have sameStore := stored.unique (store_installation_support related.store)
    rw [sameOutside, sameStore, fresh_obligation_corresponds] at created
    rw [created]
    obtain ⟨_, steps, matched⟩ := compiled_protection_entry (retained := retained) table cleanup body bindings outside related.store sourceCells regions extra
    exact ⟨1, _, steps, matched.as_execution⟩
  | @enterRegion context answer result outsideSupport sourceStore storedSupport identity regions _ body bindings sourceOutside sourceCells extra supported stored created =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.withRegion body) bindings sourceOutside
    rw [configuration]
    have sameOutside := supported.unique (context_installation_support outside)
    have sameStore := stored.unique (store_installation_support related.store)
    rw [sameOutside, sameStore, fresh_region_corresponds] at created
    rw [created]
    obtain ⟨_, steps, matched⟩ := compiled_region_entry (retained := retained) table body bindings outside related.store sourceCells regions extra
    exact ⟨1, _, steps, matched.as_execution⟩
  | @packageOperand context content result _ regions expression value bindings sourceOutside sourceStore evaluated moved sourceCells owner handoff operands =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.package expression) bindings sourceOutside
    rw [configuration]
    obtain ⟨_, count, targetAfter, _, steps, matched⟩ :=
      compiled_package (retained := retained) table expression bindings value owner sourceCells regions operands moved handoff related.store outside
    exact ⟨count, targetAfter, steps, matched.as_execution⟩
  | @unpackageOperand context content result _ token owner fields regions expression value bindings sourceOutside sourceStore evaluated sourceCells operands handoff =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.unpackage expression) bindings sourceOutside
    rw [configuration]
    obtain ⟨_, count, targetAfter, _, steps, matched⟩ :=
      compiled_unpackage (retained := retained) table expression bindings value token owner sourceCells regions operands handoff related.store outside
    exact ⟨count, targetAfter, steps, matched.as_execution⟩
  | @returnOperand context answer result _ sourceStore value afterStore regions expression bindings sourceOutside sourceCells operands =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.returnValue expression) bindings sourceOutside
    rw [configuration]
    obtain ⟨_, count, targetAfter, _, steps, matched⟩ :=
      compiled_owned_operand_return (retained := retained) table expression bindings value sourceCells regions operands related.store outside
    exact ⟨count, _, steps, matched.as_execution⟩
  | @operandFault context answer result _ sourceStore fault afterStore regions body bindings sourceOutside sourceCells operands =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view body bindings sourceOutside
    rw [configuration]
    obtain ⟨_, count, targetAfter, _, steps, matched⟩ :=
      compiled_owned_operand_failure (retained := retained) table body bindings fault sourceCells regions operands related.store outside
    exact ⟨count, _, steps, matched.as_execution⟩
  | @applicationOperands context use parameters answer capturedTypes result _ sourceStore authority evaluated fields regions function arguments body captured actual bindings sourceOutside sourceCells operands handoff =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.apply function arguments) bindings sourceOutside
    rw [configuration]
    obtain ⟨_, count, _, steps, matched⟩ :=
      compiled_owned_operand_application (retained := retained) table function arguments bindings body captured actual authority sourceCells regions
        operands handoff related.store outside
    exact ⟨count, _, steps, matched.as_execution⟩
  | @namedOperands body context result _ sourceStore actual afterStore regions reference arguments bindings sourceOutside sourceCells operands =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.call reference arguments) bindings sourceOutside
    rw [configuration]
    obtain ⟨_, count, targetAfter, _, steps, matched⟩ :=
      compiled_owned_named_call (retained := retained) table reference arguments bindings actual sourceCells regions operands related.store outside
    exact ⟨count, _, steps, matched.as_execution⟩
  | @primitiveOperands context result _ sourceStore afterStore regions parameters answer operation value inputs bindings sourceOutside sourceCells operands =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.primitive operation inputs) bindings sourceOutside
    rw [configuration]
    obtain ⟨_, count, targetAfter, _, steps, matched⟩ :=
      compiled_owned_primitive (retained := retained) table operation inputs bindings value sourceCells regions operands related.store outside
    exact ⟨count, _, steps, matched.as_execution⟩
  | @branchLeftOperands context leftType rightType answer result _ sourceStore value afterStore payload regions test left right bindings sourceOutside sourceCells operands selected =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.matchSum test left right) bindings sourceOutside
    rw [configuration]
    obtain ⟨_, count, targetAfter, _, steps, matched⟩ :=
      compiled_owned_match_left (retained := retained) table test left right bindings value payload sourceCells regions operands selected related.store outside
    exact ⟨count, _, steps, matched.as_execution⟩
  | @branchRightOperands context leftType rightType answer result _ sourceStore value afterStore payload regions test left right bindings sourceOutside sourceCells operands selected =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.matchSum test left right) bindings sourceOutside
    rw [configuration]
    obtain ⟨_, count, targetAfter, _, steps, matched⟩ :=
      compiled_owned_match_right (retained := retained) table test left right bindings value payload sourceCells regions operands selected related.store outside
    exact ⟨count, _, steps, matched.as_execution⟩
  | @performOperands effect context result _ sourceStore attachment afterStore regions operation payloadValue bodyValues capability payload bodies bindings sourceOutside sourceCells operands =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view (.perform operation capability payload bodies) bindings sourceOutside
    rw [configuration]
    obtain ⟨_, count, targetAfter, _, steps, matched⟩ :=
      compiled_owned_operation (retained := retained) table operation capability payload bodies bindings attachment payloadValue bodyValues sourceCells regions
        operands related.store outside
    exact ⟨count, _, steps, matched.as_execution⟩

/-- Induction on an arbitrary finite source derivation, with related current
state threaded from one operation to the next. No simulation is assumed. -/
theorem finite_stateful_execution_preserved (table : Source.Definitions signature algebra program)
    {source after : Source.State signature algebra program result}
    {target : Target.State signature algebra program result}
    (steps : Source.ExecutionSteps (retained := retained) table source sourceCount after)
    (related : ExecutionStateRelated source target) :
    ∃ count targetAfter, Target.ExecutionSteps (retained := retained) (definitions table) target count targetAfter ∧
      ExecutionStateRelated after targetAfter := by
  induction sourceCount generalizing source after target with
  | zero => cases steps; exact ⟨0, target, .refl, related⟩
  | succ sourceCount induction =>
    cases steps with
    | cons step tail =>
      obtain ⟨firstCount, middle, first, middleRelated⟩ := stateful_execution_step_simulates (retained := retained) table step related
      obtain ⟨restCount, final, rest, finalRelated⟩ := induction tail middleRelated
      exact ⟨firstCount + restCount, final, first.trans rest, finalRelated⟩

/-- The preservation field of D for the current stateful relation. Its remaining
registry/exit coverage obligations stay explicit in the exported contract. -/
theorem stateful_observation_preserved (table : Source.Definitions signature algebra program)
    {source final : Source.State signature algebra program result}
    {target : Target.State signature algebra program result}
    (related : ExecutionStateRelated source target)
    (observed : Source.StateObserves (retained := retained) table source final observation) :
    ∃ targetFinal targetObservation,
      Target.StateObserves (retained := retained) (definitions table) target targetFinal targetObservation ∧
      StateObservationRelated final targetFinal observation targetObservation := by
  obtain ⟨sourceCount, sourceSteps, sourceHead⟩ := observed
  obtain ⟨targetCount, targetAfter, targetSteps, matched⟩ := finite_stateful_execution_preserved (retained := retained) table sourceSteps related
  obtain ⟨targetFinal, targetObservation, targetObserved, same⟩ := stateful_head_observation_preserved (retained := retained) table matched sourceHead
  exact ⟨targetFinal, targetObservation, targetObserved.prepend targetSteps, same⟩

end BoundaryV2.Generalized.Defunctionalization
