import BoundaryV2.GeneralizedExitSimulation
import BoundaryV2.GeneralizedDisposalExecution

namespace BoundaryV2.Generalized.Source

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Authored disposal retains its caller while the acquired source future
executes through the same cleanup, value, control, and region operations. -/
structure Disposal (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  answer : TypeOf signature
  progress : ControlProgress signature algebra program answer
  outside : Context signature algebra program .unit result

def DisposalStart.begin (start : DisposalStart signature algebra program result) : Disposal signature algebra program result :=
  ⟨start.future.fst.answer, ControlProgress.seeking
    ⟨⟨0⟩, .abandoned, start.store, start.cells, start.regions, ⟨.abandoned, [], none⟩⟩
    start.future.snd.future, start.outside⟩

def Disposal.finish (disposal : Disposal signature algebra program result) : Option (ExitResolution signature algebra program result) :=
  match disposal.progress with
  | .complete runtime => match runtime.exit.primary with
    | .normal | .abandoned => some (.reenter
        ⟨⟨runtime.store, disposal.outside.plug (.returned (.datum .unit))⟩, runtime.cells, runtime.regions⟩
        { runtime.exit with primary := .normal })
    | .failure fault => some (.reenter
        ⟨⟨runtime.store, disposal.outside.plug (.failed fault)⟩, runtime.cells, runtime.regions⟩ runtime.exit)
    | .cancelled => some (.unwind runtime disposal.outside)
  | _ => none

inductive DisposalProgress (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | evaluating : State signature algebra program result → DisposalProgress signature algebra program result
  | disposing : Disposal signature algebra program result → DisposalProgress signature algebra program result
  | resolved : ExitResolution signature algebra program result → DisposalProgress signature algebra program result

inductive DisposalRunStep [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    (table : Definitions signature algebra program) : DisposalProgress signature algebra program result →
    DisposalProgress signature algebra program result → Prop where
  | evaluate : ExecutionStep table before after → DisposalRunStep table (.evaluating before) (.evaluating after)
  | enter : DisposeEntry table before start → DisposalRunStep table (.evaluating before) (.disposing start.begin)
  | operandFault {outside : Context signature algebra program input result} :
      DisposalRunStep table (.evaluating ⟨⟨store, outside.plug (.failed fault)⟩, cells, regions⟩)
        (.resolved (.reenter ⟨⟨store, outside.plug (.failed fault)⟩, cells, regions⟩ ⟨.failure fault, [], none⟩))
  | dispose {before after : ControlProgress signature algebra program answer}
      {outside : Context signature algebra program .unit result} :
      ControlProgressStep table before after outside.referenceSupport →
      DisposalRunStep table (.disposing ⟨answer, before, outside⟩) (.disposing ⟨answer, after, outside⟩)
  | finish : disposal.finish = some result → DisposalRunStep table (.disposing disposal) (.resolved result)

inductive DisposalRun [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    (table : Definitions signature algebra program) : DisposalProgress signature algebra program result →
    Nat → DisposalProgress signature algebra program result → Prop where
  | refl : DisposalRun table state 0 state
  | cons : DisposalRunStep table before middle → DisposalRun table middle count after → DisposalRun table before (count + 1) after

end BoundaryV2.Generalized.Source

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

inductive DisposalRelated : Source.Disposal signature algebra program result → Target.Disposal signature algebra program result → Prop where
  | same {source : Source.ControlProgress signature algebra program answer}
      {target : ExitComposition.ControlProgress signature algebra program answer} :
      ControlProgressRelated source target → ContextRelated signature algebra program sourceOutside targetOutside →
      DisposalRelated ⟨answer, source, sourceOutside⟩ ⟨answer, target, targetOutside⟩

inductive DisposalProgressRelated : Source.DisposalProgress signature algebra program result →
    Target.DisposalProgress signature algebra program result → Prop where
  | evaluating : ExecutionStateRelated source target → DisposalProgressRelated (.evaluating source) (.evaluating target)
  | disposing : DisposalRelated source target → DisposalProgressRelated (.disposing source) (.disposing target)
  | resolved : ExitResolutionRelated source target → DisposalProgressRelated (.resolved source) (.resolved target)

theorem DisposalStartRelated.begin [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    {source : Source.DisposalStart signature algebra program result}
    {target : Target.DisposalStart signature algebra program result}
    (related : DisposalStartRelated source target) : DisposalRelated source.begin target.begin := by
  rcases source with ⟨sourceStore, sourceCells, sourceRegions, sourceFuture, sourceOutside⟩
  rcases target with ⟨targetStore, targetCells, targetRegions, targetFuture, targetOutside⟩
  rcases related with ⟨stores, storage, regions, future, outside⟩
  dsimp only at stores storage regions future outside
  subst targetCells targetRegions
  rcases sourceFuture with ⟨shape, sourceFuture⟩
  rcases targetFuture with ⟨targetShape, targetFuture⟩
  cases future with
  | same future =>
    exact .same (.frames (.running (.unwind ⟨rfl, rfl, stores, rfl, rfl, rfl⟩ future.future))) outside

theorem DisposalRelated.finish {source : Source.Disposal signature algebra program result}
    {target : Target.Disposal signature algebra program result} (related : DisposalRelated source target) :
    Option.Rel ExitResolutionRelated source.finish target.finish := by
  cases related with
  | same progress outside =>
    cases progress with
    | frames => exact .none
    | returnedValue => exact .none
    | complete runtime =>
      rename_i sourceRuntime targetRuntime
      rcases sourceRuntime with ⟨sourceId, completion, sourceStore, sourceCells, regions, exit⟩
      rcases targetRuntime with ⟨targetId, phase, targetStore, targetCells, targetRegions, targetExit⟩
      rcases runtime with ⟨sameId, completed, stores, storage, live, sameExit⟩
      dsimp only at sameId completed stores storage live sameExit
      subst targetId phase targetCells targetRegions targetExit
      cases exit with
      | mk primary failures cancellation =>
        cases primary with
        | normal | abandoned => exact .some (.reenter ⟨stores, rfl, rfl, outside.close_program (.returned (.datum .unit) _)⟩)
        | failure fault => exact .some (.reenter ⟨stores, rfl, rfl, outside.close_program (.failed fault _)⟩)
        | cancelled => exact .some (.unwind ⟨rfl, rfl, stores, rfl, rfl, rfl⟩ outside)

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

theorem authored_disposal_entry_preserved (table : Source.Definitions signature algebra program)
    {source : Source.State signature algebra program result} {target : Target.State signature algebra program result}
    {start : Source.DisposalStart signature algebra program result}
    (entry : Source.DisposeEntry table source start) (related : ExecutionStateRelated source target) :
    ∃ count targetStart, Target.DisposalRun (definitions table) (.evaluating target) count (.disposing targetStart.begin) ∧
      DisposalStartRelated start targetStart := by
  cases entry with
  | enter operands released =>
    obtain ⟨targetOutside, outside, configuration⟩ := related.evaluation_view _ _ _
    rw [configuration]
    obtain ⟨_, targetStart, count, _, joined, steps⟩ :=
      compiled_disposal_entry table _ _ _ _ _ _ operands related.store _ released outside
    exact ⟨count, targetStart, steps, joined⟩

theorem authored_disposal_step_preserved (table : Source.Definitions signature algebra program)
    {source after : Source.DisposalProgress signature algebra program result}
    {target : Target.DisposalProgress signature algebra program result}
    (step : Source.DisposalRunStep table source after) (related : DisposalProgressRelated source target) :
    ∃ count targetAfter, Target.DisposalRun (definitions table) target count targetAfter ∧
      DisposalProgressRelated after targetAfter := by
  cases step with
  | evaluate core =>
    cases related with
    | evaluating states =>
      obtain ⟨count, targetAfter, steps, joined⟩ := stateful_execution_step_simulates table core states
      exact ⟨count, _, Target.DisposalRun.of_execution steps, .evaluating joined⟩
  | enter entry =>
    cases related with
    | evaluating states =>
      obtain ⟨count, targetAfter, steps, joined⟩ := authored_disposal_entry_preserved table entry states
      exact ⟨count, _, steps, .disposing joined.begin⟩
  | operandFault =>
    cases related with
    | evaluating states =>
      rename_i targetState
      rcases targetState with ⟨⟨store, configuration⟩, cells, regions⟩
      obtain ⟨targetOutside, outside, inner⟩ := open_program_context _ (.failed _) states.computation .done
      simp only [Source.Context.append_done] at outside
      obtain ⟨count, steps⟩ := inner.failed_state_drains (retained := []) (definitions table) _ rfl store cells regions
      exact ⟨count + 1, _, Target.DisposalRun.operand_failure steps,
        .resolved (.reenter ⟨states.store, states.cells, states.regions, outside.close_program (.failed _ _)⟩)⟩
  | dispose step =>
    cases related with
    | disposing disposal =>
      cases disposal with
      | same progress outside =>
        obtain ⟨count, targetAfter, steps, joined⟩ := control_progress_step_preserved table step progress
        rw [← context_reference_support outside] at steps
        exact ⟨count, _, Target.DisposalRun.control_steps _ steps, .disposing (.same joined outside)⟩
  | finish accepted =>
    cases related with
    | disposing disposal =>
      obtain ⟨targetAfter, finished, joined⟩ := option_related_some disposal.finish accepted
      exact ⟨1, _, .cons (.finish finished) .refl, .resolved joined⟩

theorem finite_authored_disposal_preserved (table : Source.Definitions signature algebra program)
    {source after : Source.DisposalProgress signature algebra program result}
    {target : Target.DisposalProgress signature algebra program result}
    (steps : Source.DisposalRun table source count after) (related : DisposalProgressRelated source target) :
    ∃ targetCount targetAfter, Target.DisposalRun (definitions table) target targetCount targetAfter ∧
      DisposalProgressRelated after targetAfter := by
  induction steps generalizing target with
  | refl => exact ⟨0, target, .refl, related⟩
  | cons step tail induction =>
    obtain ⟨firstCount, middle, first, joined⟩ := authored_disposal_step_preserved table step related
    obtain ⟨restCount, final, rest, last⟩ := induction joined
    exact ⟨firstCount + restCount, final, first.trans rest, last⟩

end BoundaryV2.Generalized.Defunctionalization
