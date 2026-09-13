import BoundaryV2.GeneralizedDisposalExecution
import BoundaryV2.GeneralizedExamples

namespace BoundaryV2.Generalized.Examples

def disposeView : UseScope.ControlView := ⟨⟨10⟩, ⟨100⟩, .lexical ⟨0⟩ 0⟩
abbrev DisposeType : TypeOf signature := .continuation .shallow .linear .choose (.leaf .boolean) .unit
abbrev disposeShape : ControlShape signature := ⟨.shallow, .choose, .leaf .boolean, .unit⟩
def disposalCleanup : Source.Computation signature algebra [] [.exit] .unit :=
  .yieldThen (.returnValue (.datum .unit))
def disposalReturn : Source.Computation signature algebra [] [.leaf .boolean] .unit := .returnValue (.datum .unit)
def disposalCaller : Source.Computation signature algebra [] [.unit] (.leaf .integer) := .returnValue (.datum (.leaf 42))
def disposalSourceFuture : Source.Resumption signature algebra [] .shallow .choose (.leaf .boolean) .unit :=
  ⟨⟨8⟩, .push (.protection ⟨7⟩ disposalCleanup .nil)
    (.push (.bind (fun value => .evaluate disposalReturn (.cons value .nil))) .done)⟩
def disposalTargetFuture : Target.Resumption signature algebra [] .shallow .choose (.leaf .boolean) .unit :=
  ⟨⟨8⟩, .push (.protection ⟨7⟩ (Defunctionalization.computation disposalCleanup) .nil)
    (.push (.returnTo (.enter (Defunctionalization.computation disposalReturn)) .nil .nil) .done)⟩
def disposalFields : UseScope.State :=
  ⟨[.owned ⟨100⟩ disposeView.owner, .owned ⟨900⟩ (.lexical ⟨0⟩ 1)], [.continuation ⟨10⟩ [.cleanup ⟨7⟩ []]], []⟩
def disposalSourceStore : Source.ControlHeap signature algebra [] :=
  ⟨disposalFields, [⟨⟨10⟩, ⟨100⟩, .linear, ⟨disposeShape, disposalSourceFuture⟩⟩], []⟩
def disposalTargetStore : Target.ControlHeap signature algebra [] :=
  ⟨disposalFields, [⟨⟨10⟩, ⟨100⟩, .linear, ⟨disposeShape, disposalTargetFuture⟩⟩], []⟩
def disposalFinishedFields : UseScope.State :=
  ⟨[.cleanup ⟨7⟩ [], .owned ⟨900⟩ (.lexical ⟨0⟩ 1)], [], [⟨100⟩]⟩
def disposalSourceAfter : Source.ControlHeap signature algebra [] := ⟨disposalFinishedFields, [], []⟩
def disposalTargetAfter : Target.ControlHeap signature algebra [] := ⟨disposalFinishedFields, [], []⟩
def disposalBindings : Source.RuntimeEnvironment signature algebra [] [DisposeType] :=
  .cons (.continuation disposeView.identity (some (disposeView.authority, disposeView.owner))) .nil

def disposalSourceOutside : Source.Context signature algebra [] .unit (.leaf .integer) :=
  .push (.bind (fun value => .evaluate disposalCaller (.cons value .nil))) .done
def disposalTargetOutside : Target.Stack signature algebra [] .unit (.leaf .integer) :=
  .push (.returnTo (.enter (Defunctionalization.computation disposalCaller)) .nil .nil) .done

def disposalTargetStart : Target.DisposalStart signature algebra [] (.leaf .integer) :=
  ⟨disposalTargetAfter, [], [], ⟨disposeShape, disposalTargetFuture⟩,
    .push (.returnTo .ret (Defunctionalization.environment disposalBindings) .nil) disposalTargetOutside⟩

theorem authored_dispose_has_corresponding_owned_entry :
    Source.DisposeEntry (.nil : Source.Definitions signature algebra [])
      ⟨⟨disposalSourceStore, disposalSourceOutside.plug (.evaluate (.dispose (.reference .here)) disposalBindings)⟩, [], []⟩
      ⟨disposalSourceAfter, [], [], ⟨disposeShape, disposalSourceFuture⟩, disposalSourceOutside⟩ ∧
    ∃ start count, 0 < count ∧ Defunctionalization.DisposalStartRelated
      ⟨disposalSourceAfter, [], [], ⟨disposeShape, disposalSourceFuture⟩, disposalSourceOutside⟩ start ∧
      Target.DisposalRun (.nil : Target.Definitions signature algebra [])
        (.evaluating ⟨⟨disposalTargetStore, .code (Defunctionalization.computation (.dispose (.reference .here)))
          (Defunctionalization.environment disposalBindings) .nil disposalTargetOutside⟩, [], []⟩) count (.disposing start.begin) := by
  have future : Defunctionalization.ResumptionRelated disposalSourceFuture disposalTargetFuture :=
    ⟨rfl, .push (.protection ⟨7⟩ disposalCleanup .nil) (.push (.bind disposalReturn .nil) .done)⟩
  exact Defunctionalization.compiled_disposal_entry (signature := signature) (algebra := algebra)
    .nil .linear (.reference .here) disposalBindings disposeView [] []
    (sourceStore := disposalSourceStore) (evaluated := disposalSourceStore) (targetStore := disposalTargetStore) .reference
    ⟨rfl, .cons ⟨rfl, rfl, rfl, .same future⟩ .nil, .nil⟩
    ⟨disposalSourceAfter, ⟨disposeShape, disposalSourceFuture⟩⟩ rfl (.push (.bind disposalCaller .nil) .done)

def disposalRuntime (phase : ExitComposition.Phase signature algebra []) : ExitComposition.Runtime signature algebra [] :=
  ⟨⟨7⟩, phase, disposalTargetAfter, [], [], ⟨.abandoned, [], none⟩⟩
def disposalPending := disposalRuntime (.pending ⟨[], Defunctionalization.computation disposalCleanup, .nil⟩)
def disposalYielded := disposalRuntime (.running
  (.yielded (.code (.push .unit .ret) (.cons (.exit ⟨.abandoned, [], none⟩) .nil) .nil .done)) .parked)
def disposalCompleted := disposalRuntime (.finished .returned)

theorem explicit_disposal_runs_cleanup_through_its_real_yield :
    ExitComposition.RuntimeSteps (.nil : Target.Definitions signature algebra []) disposalPending 1 disposalYielded ∧
    ExitComposition.RuntimeSteps (.nil : Target.Definitions signature algebra []) disposalYielded 0 disposalCompleted := by
  let started := disposalRuntime (.running (.code (Defunctionalization.computation disposalCleanup)
    (.cons (.exit ⟨.abandoned, [], none⟩) .nil) .nil .done) .active)
  let yielded := disposalRuntime (.running (.yielded (.code (.push .unit .ret)
    (.cons (.exit ⟨.abandoned, [], none⟩) .nil) .nil .done)) .active)
  let resumed := disposalRuntime (.running (.code (.push .unit .ret)
    (.cons (.exit ⟨.abandoned, [], none⟩) .nil) .nil .done) .active)
  let pushed := disposalRuntime (.running (.code .ret
    (.cons (.exit ⟨.abandoned, [], none⟩) .nil) (.cons (.datum .unit) .nil) .done) .active)
  let returned := disposalRuntime (.running (.returned (.datum .unit) .done) .active)
  have first : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) disposalPending 1 started := .lifecycle .begin
  have second : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) started 0 yielded :=
    .execute (Target.ExecutionStep.cell (signature := signature) (algebra := algebra) (.ordinary .yield))
  have third : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) yielded 0 disposalYielded := .lifecycle .parkYield
  have fourth : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) disposalYielded 0 resumed := .lifecycle .continueYield
  have fifth : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) resumed 0 pushed :=
    .execute (Target.ExecutionStep.cell (signature := signature) (algebra := algebra) (.ordinary (.operand .push)))
  have sixth : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) pushed 0 returned :=
    .execute (Target.ExecutionStep.cell (signature := signature) (algebra := algebra) (.ordinary .returned))
  have last : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) returned 0 disposalCompleted := .lifecycle .returned
  exact ⟨.cons first (.cons second (.cons third .refl)), .cons fourth (.cons fifth (.cons sixth (.cons last .refl)))⟩

def disposalTail : Target.Stack signature algebra [] (.leaf .boolean) .unit :=
  .push (.returnTo (.enter (Defunctionalization.computation disposalReturn)) .nil .nil) .done

theorem yielding_disposal_has_not_returned_to_its_caller :
    Target.Disposal.finish ⟨.unit, .cleaning ⟨disposalYielded, .unwind disposalTail⟩, disposalTargetStart.outside⟩ = none := rfl

def disposedResolution : ExitComposition.Resolution signature algebra [] (.leaf .integer) :=
  .reenter ⟨⟨disposalTargetAfter, .returned (.datum .unit) disposalTargetStart.outside⟩, [], []⟩ ⟨.normal, [], none⟩

theorem explicit_disposal_completes_before_returning_unit_to_its_caller :
    ∃ count, Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.evaluating ⟨⟨disposalTargetStore, .code (Defunctionalization.computation (.dispose (.reference .here)))
        (Defunctionalization.environment disposalBindings) .nil disposalTargetOutside⟩, [], []⟩) count
      (.resolved disposedResolution) := by
  have admission : Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.evaluating ⟨⟨disposalTargetStore, .code (Defunctionalization.computation (.dispose (.reference .here)))
        (Defunctionalization.environment disposalBindings) .nil disposalTargetOutside⟩, [], []⟩) 2
      (.disposing disposalTargetStart.begin) :=
    Target.DisposalRun.cons (signature := signature) (algebra := algebra)
      (.evaluate (Target.ExecutionStep.cell (signature := signature) (algebra := algebra) (.ordinary (.operand .load))))
      (.cons (.enter (Target.DisposeEntry.enter (use := .linear) rfl)) .refl)
  have cleanup := explicit_disposal_runs_cleanup_through_its_real_yield.1.trans explicit_disposal_runs_cleanup_through_its_real_yield.2
  have tail := ExitComposition.run_selected_cleanup disposalTail cleanup rfl (by intro impossible; cases impossible)
  have unwind : ExitComposition.UnwindSteps (.nil : Target.Definitions signature algebra [])
      disposalTargetStart.begin.progress [⟨7⟩] (.complete disposalCompleted) :=
    ExitComposition.UnwindSteps.cons (signature := signature) (algebra := algebra)
      (.select (by intro impossible; cases impossible) rfl) (tail.trans (.cons (.complete rfl) .refl))
  have steps := Target.DisposalSteps.of_unwind disposalTargetStart.outside unwind
  obtain ⟨count, finished⟩ := Target.DisposalRun.finish_after_unwind steps (show Target.Disposal.finish
    ⟨.unit, .complete disposalCompleted, disposalTargetStart.outside⟩ = some disposedResolution from rfl)
  exact ⟨2 + count, admission.trans finished⟩

theorem disposed_grant_is_spent_and_other_owner_is_preserved :
    disposalTargetAfter.fields.spent = [⟨100⟩] ∧ UseScope.inventory disposalTargetAfter.fields = [⟨900⟩] ∧
    UseScope.disposeOwned disposeView disposalTargetAfter = none := ⟨rfl, rfl, rfl⟩

theorem disposal_caller_can_continue_after_cleanup :
    Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨disposalTargetAfter, .returned (.datum .unit) disposalTargetStart.outside⟩, [], []⟩ 6
      ⟨⟨disposalTargetAfter, .returned (.datum (.leaf (type := Data.integer) 42)) .done⟩, [], []⟩ := by
  refine .cons (.cell (.ordinary .caller)) ?_
  refine .cons (.cell (.ordinary .returned)) ?_
  refine .cons (.cell (.ordinary .caller)) ?_
  refine .cons (.cell (.ordinary .enter)) ?_
  refine .cons (.cell (.ordinary (.operand .push))) ?_
  exact .single (.cell (.ordinary .returned))

theorem disposal_failure_and_cancellation_keep_their_distinct_outcomes :
    let failed := { disposalCompleted with exit := ⟨.failure .overflow, [.overflow], some "first"⟩ }
    let cancelled := { disposalCompleted with exit := (disposalCompleted.exit.cancel "first").cancel "later" }
    Target.Disposal.finish ⟨.unit, .complete failed, disposalTargetStart.outside⟩ =
      some (.reenter ⟨⟨disposalTargetAfter, .failed .overflow disposalTargetStart.outside⟩, [], []⟩ failed.exit) ∧
    Target.Disposal.finish ⟨.unit, .complete cancelled, disposalTargetStart.outside⟩ =
      some (.unwind cancelled disposalTargetStart.outside) ∧
    cancelled.exit.cancellation = some "first" := ⟨rfl, rfl, rfl⟩

end BoundaryV2.Generalized.Examples
